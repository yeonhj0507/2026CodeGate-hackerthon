import 'package:drift/native.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prober_local/data/api/api_client.dart';
import 'package:prober_local/data/db/database.dart';
import 'package:prober_local/data/dto/auth.dart';
import 'package:prober_local/data/dto/explore.dart';
import 'package:prober_local/data/dto/graph.dart';
import 'package:prober_local/data/dto/recommendation.dart';
import 'package:prober_local/data/dto/user_context.dart';
import 'package:prober_local/providers/providers.dart';
import 'package:prober_local/ui/graph_view.dart';
import 'package:prober_local/ui/home_page.dart';

/// **특성화 테스트** — 지금의 화면 배선을 있는 그대로 못 박는다.
///
/// `home_page` · `side_tabs` · `explore_panel` · `library_panel` 에는 지금까지
/// 테스트가 하나도 없었다. 이 파일들은 위젯 배선이라, 잘못 이어도 컴파일과
/// 다른 테스트는 전부 통과하고 **앱에서만 조용히 안 되는** 상태가 된다.
/// 디자인 이식처럼 화면을 크게 갈아엎을 때 그 침묵이 제일 위험하다.
///
/// 그래서 "무엇이 예쁜가"가 아니라 **무엇이 어디에 연결돼 있는가**만 검사한다.
/// 색·여백·문구 배치는 일부러 건드리지 않는다 — 디자인이 바뀌어도 이 테스트는
/// 살아 있어야 의미가 있다.
void main() {
  late AppDatabase db;
  late _RecordingApi api;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    api = _RecordingApi();
  });

  tearDown(() => db.close());

  /// 홈 화면을 띄운다. 그래프는 서버·DB 를 거치지 않고 곧바로 주입해
  /// 검사 대상을 "배선"으로 좁힌다.
  ///
  /// `graphProvider` 를 **항상** 갈아끼우는 게 중요하다. 진짜 drift 스트림을 쓰면
  /// 위젯 트리가 사라질 때 `StreamQueryStore.markAsClosed` 가 타이머를 하나 남기고,
  /// 테스트는 "A Timer is still pending" 으로 죽는다. drift 스트림 자체는
  /// sync_test 가 이미 검증하므로 여기서 또 태울 이유도 없다.
  Future<void> pumpHome(WidgetTester tester, {Graph graph = Graph.empty}) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          apiClientProvider.overrideWithValue(api),
          graphProvider.overrideWith((ref) => Stream.value(graph)),
        ],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pumpAndSettle();

    // 최초 동기화가 끝나면 홈이 SnackBar 를 띄운다(home_page 의 _listenForSyncFeedback).
    // 자동 소멸 타이머는 프레임에 매이지 않아 pumpAndSettle 로는 배출되지 않고,
    // 남은 채로 테스트가 끝나면 "A Timer is still pending" 으로 죽는다.
    // 시계를 지속시간 너머로 밀어 확실히 정리한다.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  }

  const article = SourceArticle(url: 'https://n.example/a', title: '환율 기사');

  final graph = Graph(
    nodes: const [
      GraphNode(
        id: 'c_환헤지',
        concept: '환헤지',
        state: NodeState.understood,
        isPrereq: true,
        sourceArticles: [article],
      ),
      GraphNode(
        id: 'c_전가',
        concept: 'NDF의 환율 전가 경로',
        state: NodeState.notUnderstood,
        isPrereq: false,
        sourceArticles: [article],
      ),
    ],
    edges: const [GraphEdge(from: 'c_환헤지', to: 'c_전가', type: EdgeType.prereq)],
  );

  // ─── 셸: 세 탭이 존재하고 서로 오간다 ───────────────────────────────────

  /// 우측 패널은 접힌 채로 시작한다. 세 갈래는 상단 아이콘으로 연다.
  Future<void> openPanel(WidgetTester tester, String tooltip) async {
    await tester.tap(find.byTooltip(tooltip));
    await tester.pumpAndSettle();
  }

  group('홈 셸', () {
    testWidgets('추천·탐색·보관함 세 갈래를 여는 버튼이 있다', (tester) async {
      await pumpHome(tester, graph: graph);

      expect(find.byTooltip('추천'), findsOneWidget);
      expect(find.byTooltip('탐색'), findsOneWidget);
      expect(find.byTooltip('보관함'), findsOneWidget);
    });

    testWidgets('패널은 접힌 채로 시작하고, 눌러야 열린다', (tester) async {
      await pumpHome(tester, graph: graph);

      // 처음엔 지도만 보인다. 패널 제목(PanelHeader)이 곧 열림 여부다.
      expect(find.text('추천'), findsNothing);

      await openPanel(tester, '추천');
      expect(find.text('추천'), findsOneWidget);
    });

    testWidgets('세 갈래를 서로 오갈 수 있다', (tester) async {
      await pumpHome(tester, graph: graph);

      await openPanel(tester, '탐색');
      expect(find.text('탐색'), findsOneWidget);

      await openPanel(tester, '보관함');
      expect(find.text('보관함'), findsOneWidget);
      expect(find.text('탐색'), findsNothing, reason: '한 번에 한 갈래만 열린다');
    });

    testWidgets('추천을 열면 확장 후보가 지도에 임시로 뜨고, 닫으면 사라진다', (tester) async {
      // 카드에 낱말만 뜨면 그 개념이 내가 아는 것 중 무엇에서 나왔는지 안 보인다.
      api.updateResult = const ThoughtmapUpdateOut(
        graph: Graph.empty,
        recommendations: Recommendations(
          expansionConcepts: [
            ExpansionRecommendation(
              conceptId: 'c_레버리지',
              conceptTag: '레버리지',
              viaConcepts: ['c_환헤지'],
            ),
          ],
        ),
      );

      await pumpHome(tester, graph: graph);
      expect(find.text('레버리지'), findsNothing, reason: '패널이 닫혀 있으면 지도에 없다');

      await openPanel(tester, '추천');
      // 카드에 한 번, 지도에 한 번.
      expect(find.text('레버리지'), findsNWidgets(2));

      await tester.tap(find.byTooltip('패널 닫기'));
      await tester.pumpAndSettle();
      expect(find.text('레버리지'), findsNothing);
    });

    testWidgets('임시 노드는 개념 집계에 잡히지 않는다', (tester) async {
      api.updateResult = const ThoughtmapUpdateOut(
        graph: Graph.empty,
        recommendations: Recommendations(
          expansionConcepts: [
            ExpansionRecommendation(conceptId: 'c_레버리지', conceptTag: '레버리지'),
          ],
        ),
      );

      await pumpHome(tester, graph: graph);
      await openPanel(tester, '추천');

      // 지도에 넘어간 그래프에서 임시 노드는 state=unknown 으로만 존재한다.
      // 내가 쌓은(진단된) 개념은 2개 그대로다 — 추천이 숫자를 부풀리면 안 된다.
      final view = tester.widget<ThoughtMapView>(find.byType(ThoughtMapView));
      expect(
        view.graph.nodes.where((n) => n.state != NodeState.unknown),
        hasLength(2),
      );
      expect(
        view.graph.nodes.where((n) => n.state == NodeState.unknown),
        hasLength(1),
      );
    });

    testWidgets('패널을 닫으면 지도만 남는다', (tester) async {
      await pumpHome(tester, graph: graph);
      await openPanel(tester, '추천');

      await tester.tap(find.byTooltip('패널 닫기'));
      await tester.pumpAndSettle();

      expect(find.text('추천'), findsNothing);
      expect(find.text('환헤지'), findsWidgets, reason: '지도는 그대로 남아야 한다');
    });

    testWidgets('생각 지도가 우측 패널과 함께 뜬다', (tester) async {
      await pumpHome(tester, graph: graph);

      // 좌측 지도에 개념이 실제로 그려져야 한다(패널만 뜨고 지도가 비면 안 된다).
      expect(find.text('환헤지'), findsWidgets);
    });

    testWidgets('앱을 열면 자동 동기화가 한 번 돈다(명세 §5.2)', (tester) async {
      await pumpHome(tester);

      expect(api.updateCalls, 1, reason: '실행 시 최초 1회 동기화가 사라지면 안 된다');
    });
  });

  // ─── 탐색 탭: 서버를 실제로 부르는가 ────────────────────────────────────

  group('탐색 탭', () {
    /// 키워드는 지도에서 노드를 **길게 눌러 끌어다** 드롭 영역에 놓아야 담긴다.
    /// 탭으로는 담기지 않는다 — 지도를 둘러보다 키워드가 쌓이지 않게 한 것이라
    /// 조작 방식 자체가 요구사항이다.
    Future<void> dragConceptToDropZone(WidgetTester tester, String concept) async {
      final node = find.text(concept).first;
      final target = find.text('뇌지도에서 개념을 길게 눌러 여기로 끌어다 놓으세요');

      final gesture = await tester.startGesture(tester.getCenter(node));
      // 길게 누르기가 인식될 때까지 기다린 뒤 끈다.
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      await gesture.moveTo(tester.getCenter(target));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
    }

    Future<void> openExploreTab(WidgetTester tester) async =>
        openPanel(tester, '탐색');

    testWidgets('키워드를 담고 버튼을 눌러야 /explore 가 나간다', (tester) async {
      await pumpHome(tester, graph: graph);
      await openExploreTab(tester);

      expect(api.exploreCalls, isEmpty, reason: '아무것도 안 담았는데 호출되면 안 된다');

      await dragConceptToDropZone(tester, '환헤지');
      expect(api.exploreCalls, isEmpty, reason: '담기만 해서는 호출되지 않는다');

      await tester.tap(find.text('더 탐색하기'));
      await tester.pumpAndSettle();

      expect(api.exploreCalls, hasLength(1));
    });

    testWidgets('키워드를 담아도 지도의 나머지 개념은 그대로 남는다', (tester) async {
      // 드래그 한 번에 지도에서 다른 노드가 사라지면 지도를 못 쓰게 된다.
      await pumpHome(tester, graph: graph);
      await openExploreTab(tester);
      await dragConceptToDropZone(tester, '환헤지');

      for (final node in graph.nodes) {
        expect(find.text(node.concept), findsWidgets,
            reason: '${node.concept} 이 지도에서 사라졌다');
      }
    });

    testWidgets('탭만으로는 키워드가 담기지 않는다', (tester) async {
      await pumpHome(tester, graph: graph);
      await openExploreTab(tester);

      await tester.tap(find.text('환헤지').first);
      await tester.pumpAndSettle();

      // 드롭 영역이 여전히 비어 있어야 한다.
      expect(find.text('뇌지도에서 개념을 길게 눌러 여기로 끌어다 놓으세요'), findsOneWidget);
    });

    testWidgets('담은 개념의 id 와 이름을 함께 보낸다', (tester) async {
      // 서버는 그래프를 보관하지 않아 id 만으로는 개념명을 모른다(explore.dart 주석).
      await pumpHome(tester, graph: graph);
      await openExploreTab(tester);
      await dragConceptToDropZone(tester, '환헤지');
      await tester.tap(find.text('더 탐색하기'));
      await tester.pumpAndSettle();

      final req = api.exploreCalls.single;
      expect(req.conceptIds, ['c_환헤지']);
      expect(req.conceptTags, ['환헤지']);
    });

    testWidgets('응답은 개념별로 쪼개지 않고 한 덩어리로 보여준다', (tester) async {
      // /explore 는 고른 개념 전체를 묶어 설명 하나를 돌려준다. 키워드마다
      // 카드를 나누면 "묶었을 때 무엇이 보이는가"라는 기능 자체가 사라진다.
      api.exploreResult = const ExploreResult(
        explanation: '환헤지는 환율 변동 손실을 미리 막는 장치다.',
        articles: [
          ArticleRecommendation(title: '환헤지 입문', url: 'https://n.example/hedge'),
        ],
      );

      await pumpHome(tester, graph: graph);
      await openExploreTab(tester);
      await dragConceptToDropZone(tester, '환헤지');
      await tester.tap(find.text('더 탐색하기'));
      await tester.pumpAndSettle();

      expect(find.text('이 개념들을 함께 보면'), findsOneWidget);
      expect(find.text('환헤지는 환율 변동 손실을 미리 막는 장치다.'), findsOneWidget);
      expect(find.text('환헤지 입문'), findsOneWidget);
    });
  });

  // ─── 보관함: 서버 왕복 없이 그래프에서 나온다 ───────────────────────────

  group('보관함 탭', () {
    testWidgets('열람한 기사가 카드로 뜨고, 서버를 부르지 않는다', (tester) async {
      await pumpHome(tester, graph: graph);
      final before = api.updateCalls;

      await openPanel(tester, '보관함');

      // 보관함 카드에 한 번, 지도의 기사 노드에 한 번(article_nodes.dart).
      expect(find.text('환율 기사'), findsNWidgets(2));
      // 학습 데이터 원본은 로컬이다(명세 §4.5) — 보관함은 그래프에서 역산한다.
      expect(api.updateCalls, before);
      expect(api.exploreCalls, isEmpty);
    });
  });
}

/// 호출을 기록하는 ApiClient. 어떤 화면 조작이 **어떤 서버 호출로 이어지는지**를
/// 단언하기 위한 것이라, 응답은 테스트가 지정한 값을 그대로 돌려준다.
class _RecordingApi implements ApiClient {
  final List<ExploreRequest> exploreCalls = [];
  int updateCalls = 0;

  ExploreResult exploreResult = ExploreResult.empty;
  ThoughtmapUpdateOut updateResult = const ThoughtmapUpdateOut(
    graph: Graph.empty,
    recommendations: Recommendations(),
  );

  /// 반영 확인을 받은 스크랩 id — "언제 지우라고 했는지"를 단언하기 위한 기록.
  final List<String> ackedScrapIds = [];

  @override
  Future<void> ackScraps(List<String> scrapIds) async {
    ackedScrapIds.addAll(scrapIds);
  }

  @override
  Future<ExploreResult> explore(ExploreRequest req) async {
    exploreCalls.add(req);
    return exploreResult;
  }

  @override
  Future<ThoughtmapUpdateOut> updateThoughtmap(Graph graph, UserContext ctx) async {
    updateCalls++;
    return updateResult;
  }

  @override
  Future<TokenOut> login(String email, String password) async =>
      const TokenOut(accessToken: 't', userId: 'u');

  @override
  Future<String> signup(String email, String password) async => 'u';

  @override
  Future<MeOut> me() async => const MeOut(userId: 'u', email: 'u@example.com');
}
