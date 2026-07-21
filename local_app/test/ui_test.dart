import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prober_local/data/dto/graph.dart';
import 'package:prober_local/data/dto/recommendation.dart';
import 'package:prober_local/providers/providers.dart';
import 'package:prober_local/ui/archive_panel.dart';
import 'package:prober_local/ui/explore_panel.dart';
import 'package:prober_local/ui/graph_view.dart';
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

    testWidgets('모를 것 같은 개념·읽을 만한 기사 섹션을 보여준다(명세 §5.3)', (tester) async {
      await tester.pumpWidget(host(
        RecommendationPanel(recommendations: recs, graph: graph, onClose: () {}),
      ));
      await tester.pumpAndSettle();

      expect(find.text('모를 것 같은 개념'), findsOneWidget);
      expect(find.text('읽을 만한 기사'), findsOneWidget);
      expect(find.text('실질금리'), findsOneWidget);
      // 확장 개념은 "모를 것 같은 개념"과 중복 개념이라 화면에 별도 섹션으로 두지 않는다
      // — 데이터에 있어도 렌더링하지 않는다.
      expect(find.text('확장 개념'), findsNothing);
      expect(find.text('30초 만에 이해하는 실질금리'), findsOneWidget);
      expect(find.textContaining('한겨레'), findsOneWidget);
    });

    testWidgets('모를 것 같은 개념을 누르면 탭을 벗어나지 않고 인라인으로 상세가 펼쳐진다', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body:
                RecommendationPanel(recommendations: recs, graph: graph, onClose: () {}),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('실질금리'));
      await tester.pumpAndSettle();

      // 개념 상세로 펼쳐졌지만, 그래프 선택 상태는 건드리지 않는다 —
      // 그래야 도킹 패널이 "탐색" 탭으로 넘어가지 않는다.
      expect(container.read(inlineConceptDetailProvider), 'c_실질금리');
      expect(container.read(selectedNodeIdProvider), isNull);
      expect(find.textContaining('명목금리에서 물가상승률을'), findsOneWidget);
      expect(find.text('연관 개념'), findsOneWidget);

      // 뒤로가기를 누르면 다시 목록이 보인다.
      await tester.tap(find.text('추천으로 돌아가기'));
      await tester.pumpAndSettle();
      expect(container.read(inlineConceptDetailProvider), isNull);
      expect(find.text('모를 것 같은 개념'), findsOneWidget);
    });

    testWidgets('추천이 없으면 안내 문구를 보여준다', (tester) async {
      await tester.pumpWidget(host(
        RecommendationPanel(
            recommendations: Recommendations.empty, graph: graph, onClose: () {}),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('동기화하면 여기에'), findsOneWidget);
    });
  });

  group('ExplorePanel', () {
    testWidgets('키워드가 없으면 드롭 영역에 안내 문구를 보여준다', (tester) async {
      await tester.pumpWidget(host(ExplorePanel(graph: graph, onClose: () {})));
      await tester.pumpAndSettle();

      expect(find.textContaining('길게 눌러 여기로 끌어다 놓으세요'), findsOneWidget);
      expect(find.text('더 탐색하기'), findsOneWidget);
    });

    testWidgets('허용되는 데이터를 드롭 영역에 놓으면 탐색 키워드로 담긴다', (tester) async {
      // 실제 드래그 소스는 그래프 노드([_ConceptNode], LongPressDraggable)지만,
      // graphview 패키지가 내부에 품은 InteractiveViewer의 제스처 인식기와
      // 테스트 하네스에서 충돌할 수 있어 여기서는 표준 [Draggable]로 같은
      // 데이터(conceptId)를 흘려보내 드롭 영역 자체의 수락 로직만 검증한다.
      await tester.pumpWidget(host(
        Column(
          children: [
            Draggable<String>(
              data: 'c_실질금리',
              feedback: const Material(child: Text('드래그 중')),
              child: const Text('드래그 소스'),
            ),
            SizedBox(
                height: 500, child: ExplorePanel(graph: graph, onClose: () {})),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      final source = tester.getCenter(find.text('드래그 소스'));
      final target =
          tester.getCenter(find.textContaining('길게 눌러 여기로 끌어다 놓으세요'));

      final gesture = await tester.startGesture(source);
      // 드래그 인식기가 이동을 감지하도록 여러 단계로 나눠 옮긴다(한 번에
      // 점프하면 제스처 아레나가 드래그 시작으로 인식하지 못할 수 있다).
      const steps = 10;
      for (var i = 1; i <= steps; i++) {
        await gesture.moveTo(Offset.lerp(source, target, i / steps)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('실질금리'), findsOneWidget);
    });

    testWidgets('선택된 키워드 칩의 ×를 누르면 빠진다', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(exploreKeywordProvider.notifier).state = [
        'c_실질금리',
        'c_물가상승률',
      ];

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: ExplorePanel(graph: graph, onClose: () {})),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('실질금리'), findsOneWidget);
      expect(find.text('물가상승률'), findsOneWidget);

      // 첫 번째 Icons.close는 [PanelHeader]의 패널 닫기 버튼이라, 칩의 ×는
      // 그다음(실질금리 칩)이다.
      await tester.tap(find.byIcon(Icons.close).at(1));
      await tester.pumpAndSettle();

      expect(container.read(exploreKeywordProvider), ['c_물가상승률']);
    });

    testWidgets('더 탐색하기를 누르면 고른 키워드 각각의 결과가 모두 펼쳐진다', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(exploreKeywordProvider.notifier).state = [
        'c_실질금리',
        'c_물가상승률',
      ];

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: ExplorePanel(graph: graph, onClose: () {})),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('더 탐색하기'));
      await tester.pumpAndSettle();

      expect(find.text('관련 기사'), findsNWidgets(2));
    });
  });

  group('ArchivePanel', () {
    testWidgets('출처 기사별로 학습한 개념을 카드로 보여준다', (tester) async {
      await tester.pumpWidget(host(ArchivePanel(graph: graph, onClose: () {})));
      await tester.pumpAndSettle();

      expect(find.text('기사 A'), findsOneWidget);
      expect(find.text('기사 B'), findsOneWidget);
      // 기사 A에서 학습한 개념 세 개가 칩으로 모두 보인다.
      expect(find.text('기준금리'), findsOneWidget);
      expect(find.text('물가상승률'), findsOneWidget);
      // 실질금리는 기사 A·B 양쪽에 걸쳐 있어 카드 두 곳에 칩으로 뜬다.
      expect(find.text('실질금리'), findsNWidgets(2));
    });

    testWidgets('출처 기사가 없으면 안내 문구를 보여준다', (tester) async {
      await tester.pumpWidget(host(ArchivePanel(graph: Graph.empty, onClose: () {})));
      await tester.pumpAndSettle();

      expect(find.textContaining('아직 진단한 기사가 없어요'), findsOneWidget);
    });
  });
}
