import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prober_local/data/dto/graph.dart';
import 'package:prober_local/data/dto/recommendation.dart';
import 'package:prober_local/providers/providers.dart';
import 'package:prober_local/ui/graph_view.dart';
import 'package:prober_local/ui/node_detail_panel.dart';
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
    edges: [
      GraphEdge(from: 'c_물가상승률', to: 'c_실질금리'),
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

    testWidgets('선행개념 노드에 라벨을 붙인다', (tester) async {
      await tester.pumpWidget(host(const ThoughtMapView(graph: graph)));
      await tester.pumpAndSettle();

      // 물가상승률만 isPrereq = true.
      expect(find.text('선행개념'), findsOneWidget);
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

      await tester.tap(find.text('실질금리'));
      await tester.pumpAndSettle();
      expect(container.read(selectedNodeIdProvider), 'c_실질금리');

      // 같은 노드를 다시 누르면 선택이 풀린다.
      await tester.tap(find.text('실질금리'));
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

  group('NodeDetailPanel', () {
    testWidgets('재요약·출처 기사·연결 개념을 보여준다', (tester) async {
      await tester.pumpWidget(host(
        NodeDetailPanel(node: graph.nodeById('c_실질금리')!, graph: graph),
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
        NodeDetailPanel(node: graph.nodeById('c_기준금리')!, graph: graph),
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
          conceptId: 'c_기준금리',
          conceptTag: '기준금리',
          reason: ExpansionReason.retry,
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

    testWidgets('세 섹션으로 나눠 보여준다(명세 §5.3)', (tester) async {
      await tester
          .pumpWidget(host(const RecommendationPanel(recommendations: recs)));
      await tester.pumpAndSettle();

      expect(find.text('모를 것 같은 개념'), findsOneWidget);
      expect(find.text('확장 개념'), findsOneWidget);
      expect(find.text('읽을 만한 기사'), findsOneWidget);
      expect(find.text('실질금리'), findsOneWidget);
      expect(find.text('기준금리'), findsOneWidget);
      // 서버는 신호 종류만 주고 문구는 앱이 만든다.
      expect(find.text(ExpansionReason.retry.label), findsOneWidget);
      expect(find.text('30초 만에 이해하는 실질금리'), findsOneWidget);
      expect(find.textContaining('한겨레'), findsOneWidget);
    });

    testWidgets('확장 추천이 없으면 콜드스타트 안내를 보여준다(명세 §4.4 한계)',
        (tester) async {
      const onlyGap = Recommendations(
        gapConcepts: [
          ConceptRecommendation(conceptId: 'c_a', conceptTag: 'A'),
        ],
      );
      await tester
          .pumpWidget(host(const RecommendationPanel(recommendations: onlyGap)));
      await tester.pumpAndSettle();

      expect(find.textContaining('아직 확장 추천이 없어요'), findsOneWidget);
    });

    testWidgets('개념 추천을 누르면 그래프 선택이 그 노드로 옮겨간다', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: RecommendationPanel(recommendations: recs)),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('실질금리'));
      await tester.pumpAndSettle();

      expect(container.read(selectedNodeIdProvider), 'c_실질금리');
    });

    testWidgets('확장 추천을 누르면 그래프 선택이 그 노드로 옮겨간다', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: RecommendationPanel(recommendations: recs)),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('기준금리'));
      await tester.pumpAndSettle();

      expect(container.read(selectedNodeIdProvider), 'c_기준금리');
    });

    testWidgets('추천이 없으면 안내 문구를 보여준다', (tester) async {
      await tester.pumpWidget(
          host(const RecommendationPanel(recommendations: Recommendations.empty)));
      await tester.pumpAndSettle();

      expect(find.textContaining('동기화하면 여기에'), findsOneWidget);
    });
  });
}
