import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prober_local/data/db/database.dart';
import 'package:prober_local/data/dto/graph.dart';
import 'package:prober_local/providers/providers.dart';
import 'package:prober_local/ui/graph_view.dart';

/// 생각 지도는 **가진 개념을 전부 보여줘야 한다.**
///
/// Sugiyama 는 서로 연결되지 않은 노드를 같은 층에 가로로 늘어놓는다. 진단 초기에는
/// 개념 대부분이 고립돼 있어 그래프 폭이 뷰포트를 쉽게 넘고, 화면 맞춤이 없으면
/// 연결된 몇 개만 보이고 나머지는 캔버스 밖에 남는다. 헤더는 "개념 6"인데 지도에는
/// 2개만 뜨던 실제 버그가 그것이었다.
void main() {
  /// 실제로 터졌던 데이터: 6개 중 1쌍만 연결돼 있고 4개는 고립.
  final graph = Graph(
    nodes: const [
      GraphNode(
          id: 'n1',
          concept: '레버리지 ETF',
          state: NodeState.understood,
          isPrereq: false),
      GraphNode(
          id: 'n2',
          concept: '차액결제선물환(NDF)',
          state: NodeState.understood,
          isPrereq: false),
      GraphNode(
          id: 'n3',
          concept: 'NDF의 환율 전가 경로',
          state: NodeState.notUnderstood,
          isPrereq: false),
      GraphNode(
          id: 'n4', concept: '환헤지', state: NodeState.understood, isPrereq: true),
      GraphNode(
          id: 'n5', concept: '환투기', state: NodeState.understood, isPrereq: false),
      GraphNode(
          id: 'n6',
          concept: '원화 국제화',
          state: NodeState.understood,
          isPrereq: false),
    ],
    edges: const [GraphEdge(from: 'n4', to: 'n3', type: EdgeType.prereq)],
  );

  Future<void> pumpMap(WidgetTester tester, Size viewport) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // 좌하단 동기화 버튼이 syncControllerProvider 를 거쳐 실 DB 까지 물고
    // 있어서, 테스트끼리 같은 DB 인스턴스를 공유하지 않게 매번 새로 띄운다.
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Scaffold(body: ThoughtMapView(graph: graph)),
        ),
      ),
    );
    // 레이아웃 → postFrame 의 zoomToFit → 애니메이션까지 흘려보낸다.
    await tester.pumpAndSettle();
  }

  testWidgets('고립 노드를 포함해 모든 개념이 화면 안에 들어온다', (tester) async {
    // 그래프가 가로로 퍼지는 것보다 좁은 뷰포트 — 맞춤이 없으면 잘려나간다.
    await pumpMap(tester, const Size(900, 700));

    final screen = Offset.zero & tester.view.physicalSize;

    for (final node in graph.nodes) {
      final finder = find.text(node.concept);
      expect(finder, findsOneWidget, reason: '${node.concept} 이 트리에 없다');

      final rect = tester.getRect(finder);
      expect(
        screen.contains(rect.center),
        isTrue,
        reason: '${node.concept} 의 중심이 화면 밖이다 ($rect, 화면 $screen)',
      );
    }
  });

  testWidgets('전체 보기 버튼이 있다', (tester) async {
    await pumpMap(tester, const Size(900, 700));
    expect(find.byIcon(Icons.fit_screen_outlined), findsOneWidget);
  });

  testWidgets('노드는 길게 눌러 끌 수 있다(탐색 키워드로 담기)', (tester) async {
    await pumpMap(tester, const Size(900, 700));

    // 끌어다 놓을 대상은 탐색 탭이 갖는다. 여기서는 지도 쪽 손잡이만 확인한다.
    final draggables =
        find.byType(LongPressDraggable<String>).evaluate().toList();
    expect(draggables, hasLength(graph.nodes.length));

    final data = draggables
        .map((e) => (e.widget as LongPressDraggable<String>).data)
        .toSet();
    expect(data, graph.nodes.map((n) => n.id).toSet(),
        reason: '끌었을 때 넘어가는 값은 노드 id 여야 한다');
  });

  testWidgets('탭은 선택만 하고 드래그와 섞이지 않는다', (tester) async {
    // 지도를 둘러보다 의도치 않게 탐색 키워드가 쌓이면 안 되므로,
    // 탭과 드래그는 서로 다른 제스처로 남아 있어야 한다.
    final container = ProviderContainer();
    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Scaffold(body: ThoughtMapView(graph: graph))),
      ),
    );
    await tester.pumpAndSettle();

    expect(container.read(selectedNodeIdProvider), isNull);

    await tester.tap(find.text('환헤지'));
    await tester.pumpAndSettle();

    expect(container.read(selectedNodeIdProvider), 'n4');
  });

  testWidgets('개념이 하나뿐이어도(엣지 0) 렌더가 살아 있다', (tester) async {
    // bounds 계산이 0 나눗셈으로 깨지지 않는지 — 첫 동기화 직후 상태.
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ThoughtMapView(
              graph: Graph(nodes: [
                GraphNode(
                    id: 'only',
                    concept: '기준금리',
                    state: NodeState.notUnderstood,
                    isPrereq: false),
              ]),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('기준금리'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
