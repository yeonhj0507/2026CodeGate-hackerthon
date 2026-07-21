import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prober_local/data/dto/graph.dart';
import 'package:prober_local/data/dto/recommendation.dart';
import 'package:prober_local/providers/providers.dart';
import 'package:prober_local/ui/graph_view.dart';
import 'package:prober_local/ui/node_detail_card.dart';
import 'package:prober_local/ui/recommendation_panel.dart';

/// 화면 단위 검증. Windows 네이티브 빌드 없이 돌아간다.
void main() {
  const graph = Graph(
    nodes: [
      GraphNode(
        id: 'c_기준금리',
        concept: '기준금리',
        state: NodeState.understood,
        isPrereq: false,
        sourceArticles: [SourceArticle(url: 'https://n.example/a', title: '기사 A')],
      ),
      GraphNode(
        id: 'c_실질금리',
        concept: '실질금리',
        state: NodeState.notUnderstood,
        isPrereq: false,
        sourceArticles: [
          SourceArticle(url: 'https://n.example/a', title: '기사 A'),
          SourceArticle(url: 'https://n.example/b', title: '기사 B'),
        ],
        summaryMeta: '명목금리에서 물가상승률을 뺀 값입니다.',
      ),
      GraphNode(
        id: 'c_물가상승률',
        concept: '물가상승률',
        state: NodeState.notUnderstood,
        isPrereq: true,
        sourceArticles: [SourceArticle(url: 'https://n.example/a', title: '기사 A')],
      ),
    ],
    // 엣지는 `from`=후행 → `to`=선행이다(서버가 방향을 뒤집었다).
    edges: [
      GraphEdge(from: 'c_실질금리', to: 'c_물가상승률'),
      GraphEdge(from: 'c_실질금리', to: 'c_기준금리', type: EdgeType.related),
    ],
  );

  Widget host(Widget child) => ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: SizedBox(width: 1200, height: 800, child: child)),
        ),
      );

  group('ThoughtMapView', () {
    testWidgets('모든 개념 노드를 렌더한다', (tester) async {
      await tester.pumpWidget(host(const ThoughtMapView(graph: graph)));
      await tester.pumpAndSettle();

      expect(find.text('기준금리'), findsOneWidget);
      expect(find.text('실질금리'), findsOneWidget);
      expect(find.text('물가상승률'), findsOneWidget);
    });

    testWidgets('노드를 탭하면 선택 상태가 바뀐다', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1200,
              height: 800,
              child: ThoughtMapView(graph: graph),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(container.read(selectedNodeIdProvider), isNull);

      // 선택되면 상세 카드가 노드 옆에 뜨는데 카드 제목도 같은 텍스트라
      // find.text 가 둘을 구분 못 한다 — 선택 전(유일할 때) 좌표를 잡아
      // 이후로는 좌표로만 탭한다.
      final nodeCenter = tester.getCenter(find.text('실질금리'));

      await tester.tapAt(nodeCenter);
      await tester.pumpAndSettle();
      expect(container.read(selectedNodeIdProvider), 'c_실질금리');

      // 같은 노드를 다시 누르면 선택이 풀린다.
      await tester.tapAt(nodeCenter);
      await tester.pumpAndSettle();
      expect(container.read(selectedNodeIdProvider), isNull);
    });

    testWidgets('그래프가 비면 안내 문구를 보여준다', (tester) async {
      await tester.pumpWidget(host(const ThoughtMapView(graph: Graph.empty)));
      await tester.pumpAndSettle();

      expect(find.textContaining('생각 지도가 비어 있어요'), findsOneWidget);
    });

    testWidgets('없는 노드를 가리키는 엣지가 있어도 렌더가 깨지지 않는다', (tester) async {
      const broken = Graph(
        nodes: [
          GraphNode(
              id: 'a', concept: 'A', state: NodeState.understood,
              isPrereq: false),
        ],
        edges: [GraphEdge(from: 'a', to: '존재하지_않음')],
      );

      await tester.pumpWidget(host(const ThoughtMapView(graph: broken)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('A'), findsOneWidget);
    });
  });

  group('NodeDetailCard', () {
    testWidgets('재요약·출처 기사·연결 개념을 보여준다', (tester) async {
      await tester.pumpWidget(host(
        NodeDetailCard(
          node: graph.nodeById('c_실질금리')!,
          graph: graph,
          onClose: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('실질금리'), findsOneWidget);
      expect(find.text('미이해'), findsOneWidget);
      // 개인화 요약(명세 §4.4)이 노드 메타로 노출된다.
      expect(find.textContaining('명목금리에서 물가상승률을'), findsOneWidget);
      // 크로스기사 병합이 출처 건수로 드러난다(명세 §5.1).
      expect(find.textContaining('출처 기사 2건'), findsOneWidget);
      expect(find.text('기사 A'), findsOneWidget);
      expect(find.text('기사 B'), findsOneWidget);
      // 선행 개념과 연관 개념이 각각 잡힌다.
      expect(find.text('먼저 알아야 하는 개념'), findsOneWidget);
      expect(find.text('연관 개념'), findsOneWidget);
    });

    testWidgets('summaryMeta가 없으면 재요약 섹션을 숨긴다', (tester) async {
      await tester.pumpWidget(host(
        NodeDetailCard(
          node: graph.nodeById('c_기준금리')!,
          graph: graph,
          onClose: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('이 개념, 다시 정리하면'), findsNothing);
    });
  });

  group('RecommendationPanel', () {
    const recs = Recommendations(
      gapConcepts: [
        ConceptRecommendation(
          conceptId: 'c_실질금리',
          conceptTag: '실질금리',
          reason: '진단에서 놓친 개념',
        ),
      ],
      expansionConcepts: [
        ExpansionRecommendation(
          conceptId: 'c_수입물가',
          conceptTag: '수입물가',
          viaConcepts: ['환율'],
          articleTitle: '환율 1400원 시대, 수입물가는 어떻게 소비자물가가 되나',
          articleUrl: 'https://partner.example.com/fx/passthrough',
        ),
      ],
      retryConcepts: [
        RetryRecommendation(
          conceptId: 'c_기준금리',
          conceptTag: '기준금리',
          reason: RetryReason.retry,
        ),
      ],
      articles: [
        ArticleRecommendation(
          title: '30초 만에 이해하는 실질금리',
          url: 'https://example.com/a',
          publisher: '한겨레',
          reason: '미이해 개념 보충',
        ),
      ],
    );

    testWidgets('네 갈래를 섹션으로 나눠 보여준다(명세 §5.3)', (tester) async {
      await tester
          .pumpWidget(host(const RecommendationPanel(recommendations: recs, graph: Graph.empty)));
      await tester.pumpAndSettle();

      expect(find.text('모를 것 같은 개념'), findsOneWidget);
      expect(find.text('확장 개념'), findsOneWidget);
      expect(find.text('다시 도전할 개념'), findsOneWidget);
      expect(find.text('읽을 만한 기사'), findsOneWidget);
      // 확장은 그래프에 없는 새 개념이고, 무엇을 발판으로 왔는지를 말한다.
      expect(find.text('수입물가'), findsOneWidget);
      expect(find.textContaining('환율'), findsWidgets);
      // 낱말만 던지지 않고 그 개념이 쓰인 기사를 함께 건넨다.
      expect(find.textContaining('수입물가는 어떻게 소비자물가가 되나'), findsOneWidget);
      expect(find.text('실질금리'), findsOneWidget);
      expect(find.text('기준금리'), findsOneWidget);
      // 서버는 신호 종류만 주고 문구는 앱이 만든다.
      expect(find.text(RetryReason.retry.label), findsOneWidget);
      expect(find.text('30초 만에 이해하는 실질금리'), findsOneWidget);
      expect(find.textContaining('한겨레'), findsOneWidget);
    });

    testWidgets('확장 후보가 없으면 안내 문구를 보여준다', (tester) async {
      const onlyGap = Recommendations(
        gapConcepts: [
          ConceptRecommendation(conceptId: 'c_a', conceptTag: 'A'),
        ],
      );
      await tester
          .pumpWidget(host(const RecommendationPanel(recommendations: onlyGap, graph: Graph.empty)));
      await tester.pumpAndSettle();

      expect(find.textContaining('아직 추천할 키워드가 없어요'), findsOneWidget);
    });

    testWidgets('다시 도전할 개념이 없으면 그 섹션은 통째로 숨긴다', (tester) async {
      // 확장과 달리 "틀린 게 없다"는 안내할 일이 아니다.
      const onlyGap = Recommendations(
        gapConcepts: [ConceptRecommendation(conceptId: 'c_a', conceptTag: 'A')],
      );
      await tester.pumpWidget(host(
          const RecommendationPanel(recommendations: onlyGap, graph: Graph.empty)));
      await tester.pumpAndSettle();

      expect(find.text('다시 도전할 개념'), findsNothing);
    });

    // 개념 카드를 누르면 **이 패널 안에서** 상세가 열린다. 예전에는 지도 선택도
    // 함께 옮겼는데, 그러면 같은 개념의 상세가 지도와 패널 양쪽에 동시에 떠서
    // 같은 내용이 두 번 나왔다. 지도 탭과 추천 탭은 각자의 상세를 갖는다.
    testWidgets('개념 추천을 누르면 패널 상세가 열리고, 지도 선택은 그대로다', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: RecommendationPanel(recommendations: recs, graph: Graph.empty)),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('실질금리'));
      await tester.pumpAndSettle();

      expect(container.read(inlineConceptDetailProvider), 'c_실질금리');
      expect(container.read(selectedNodeIdProvider), isNull);
    });

    testWidgets('확장 추천을 누르면 패널 상세가 열리고, 지도 선택은 그대로다', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: RecommendationPanel(recommendations: recs, graph: Graph.empty)),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('기준금리'));
      await tester.pumpAndSettle();

      expect(container.read(inlineConceptDetailProvider), 'c_기준금리');
      expect(container.read(selectedNodeIdProvider), isNull);
    });

    testWidgets('추천이 없으면 안내 문구를 보여준다', (tester) async {
      await tester.pumpWidget(
          host(const RecommendationPanel(recommendations: Recommendations.empty, graph: Graph.empty)));
      await tester.pumpAndSettle();

      expect(find.textContaining('동기화하면 여기에'), findsOneWidget);
    });
  });
}
