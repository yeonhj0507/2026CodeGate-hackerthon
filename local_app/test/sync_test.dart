import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prober_local/core/app_exception.dart';
import 'package:prober_local/data/api/api_client.dart';
import 'package:prober_local/data/api/mock_api_client.dart';
import 'package:prober_local/data/api/mock_data.dart';
import 'package:prober_local/data/db/database.dart';
import 'package:prober_local/data/dto/explore.dart';
import 'package:prober_local/data/dto/auth.dart';
import 'package:prober_local/data/dto/graph.dart';
import 'package:prober_local/data/dto/recommendation.dart';
import 'package:prober_local/data/dto/user_context.dart';
import 'package:prober_local/data/repository/thoughtmap_repository.dart';

/// 흐름 B(명세 §6)의 로컬 측 검증.
///
/// 핵심은 "로컬이 학습 데이터의 원본을 쥔다"(명세 §2)는 것이므로,
/// 동기화 결과가 SQLite에 실제로 남아 재시작 후에도 복원되는지를 본다.
void main() {
  late AppDatabase db;
  late ThoughtmapRepository repo;

  setUp(() {
    // 인메모리 DB. 실제 파일 대신 쓰지만 스키마·쿼리는 동일하다.
    db = AppDatabase(NativeDatabase.memory());
    repo = ThoughtmapRepository(
      api: MockApiClient(random: Random(0)),
      db: db,
    );
  });

  tearDown(() => db.close());

  test('첫 동기화가 그래프를 로컬에 반영한다', () async {
    expect((await db.loadGraph()).nodes, isEmpty);

    final result = await repo.sync();

    expect(result.graph.nodes, isNotEmpty);
    expect(result.addedNodeCount, result.graph.nodes.length);

    // 응답만이 아니라 DB에 실제로 남아야 한다.
    final persisted = await db.loadGraph();
    expect(persisted.nodes.map((n) => n.id),
        containsAll(result.graph.nodes.map((n) => n.id)));
    expect(persisted.edges, isNotEmpty);
  });

  test('동기화를 반복하면 그래프가 누적된다', () async {
    final first = await repo.sync();
    final second = await repo.sync();

    expect(second.graph.nodes.length, greaterThan(first.graph.nodes.length));
    expect(second.addedNodeCount, greaterThan(0));

    // 1회차 노드가 사라지지 않아야 한다(세션·기사를 넘나드는 누적, 명세 §5.1).
    final ids = second.graph.nodes.map((n) => n.id).toSet();
    expect(ids, containsAll(first.graph.nodes.map((n) => n.id)));
  });

  test('같은 개념이 다른 기사에서 재등장하면 노드가 병합된다', () async {
    await repo.sync(); // 기준금리가 기사 1에서 등장
    final afterSecond = await repo.sync(); // 기준금리가 기사 2에서 재등장

    final merged = afterSecond.graph.nodeById('c_기준금리');
    expect(merged, isNotNull);
    // 노드가 새로 생기는 게 아니라 출처 기사가 누적된다.
    expect(merged!.sourceArticles.length, 2);
    expect(afterSecond.graph.nodes.where((n) => n.id == 'c_기준금리'), hasLength(1));
  });

  test('summaryMeta(개인화 요약)가 로컬에 보존된다', () async {
    await repo.sync();

    final node = (await db.loadGraph()).nodeById('c_실질금리');
    expect(node, isNotNull);
    expect(node!.summaryMeta, isNotNull);
    expect(node.summaryMeta, contains('명목금리'));
  });

  test('앱을 재시작해도 같은 DB에서 그래프가 복원된다', () async {
    await repo.sync();
    final before = await db.loadGraph();

    // 같은 executor를 공유하지 않는 새 repository = 새 앱 세션.
    final reopened = ThoughtmapRepository(
      api: MockApiClient(random: Random(0)),
      db: db,
    );
    final restored = await reopened.loadLocalGraph();

    expect(restored.nodes.length, before.nodes.length);
    expect(restored.edges.length, before.edges.length);
  });

  test('반영된 기사가 영구 반영본으로 기록된다', () async {
    await repo.sync();

    final scraps = await repo.appliedScraps();
    expect(scraps, isNotEmpty);
    expect(scraps.first.articleTitle, contains('기준금리'));
  });

  test('서버 버퍼가 비면 그래프는 그대로고 새 노드는 0이다', () async {
    // 준비된 웨이브를 모두 소진한다.
    for (var i = 0; i < MockData.waves.length; i++) {
      await repo.sync();
    }
    final drained = await db.loadGraph();

    final extra = await repo.sync();

    expect(extra.addedNodeCount, 0);
    expect(extra.graph.nodes.length, drained.nodes.length);
  });

  test('사용자 컨텍스트가 동기화 결과로부터 축적된다', () async {
    expect((await db.loadUserContext()).learningHistory, isEmpty);

    await repo.sync();

    final ctx = await db.loadUserContext();
    expect(ctx.learningHistory, isNotEmpty);
    expect(ctx.articlePreferences, isNotEmpty);
    // 오답으로 남은 개념이 이력에 미이해로 잡혀야 한다.
    expect(
      ctx.learningHistory.where((h) => !h.correct).map((h) => h.conceptTag),
      contains('실질금리'),
    );
  });

  test('replaceGraph는 서버 응답본을 원본으로 채택한다', () async {
    await db.replaceGraph(const Graph(
      nodes: [
        GraphNode(
            id: 'old', concept: '옛 개념', state: NodeState.understood,
            isPrereq: false),
      ],
      edges: [],
    ));

    await db.replaceGraph(const Graph(
      nodes: [
        GraphNode(
            id: 'new', concept: '새 개념', state: NodeState.notUnderstood,
            isPrereq: true),
      ],
      edges: [],
    ));

    final graph = await db.loadGraph();
    expect(graph.nodes.map((n) => n.id), ['new']);
  });

  test('로컬 반영을 마친 뒤에야 서버 버퍼를 비우라고 알린다', () async {
    // 서버가 응답 직후 스스로 지우면, 응답을 못 받은 클라이언트의 진단이
    // 서버에서도 로컬에서도 사라진다(QA 중 실제로 한 세션이 날아갔다).
    // 그래서 삭제 시점을 "로컬에 다 썼다"는 확인 뒤로 미뤘다.
    final api = _AckSpyApi()..bind(db);
    final spyRepo = ThoughtmapRepository(api: api, db: db);

    await spyRepo.sync();

    expect(api.ackedScrapIds, ['s1', 's2']);
    expect(api.graphWhenAcked, isNotNull,
        reason: 'ack 시점에는 이미 로컬 그래프가 갱신돼 있어야 한다');
    expect(api.graphWhenAcked!.nodes, isNotEmpty);
  });

  test('ack 이 실패해도 동기화는 성공으로 끝난다', () async {
    // 다음 동기화가 같은 스크랩을 다시 반영하므로 잃는 게 없다.
    final api = _AckSpyApi(failAck: true);
    final spyRepo = ThoughtmapRepository(api: api, db: db);

    final result = await spyRepo.sync();

    expect(result.graph.nodes, isNotEmpty);
    expect((await db.loadGraph()).nodes, isNotEmpty);
  });
}

/// ack 시점을 관찰하는 가짜 서버.
class _AckSpyApi implements ApiClient {
  _AckSpyApi({this.failAck = false});

  final bool failAck;
  final List<String> ackedScrapIds = [];

  /// ack 을 받은 순간의 로컬 그래프. 순서를 단언하기 위해 스파이가 직접 읽는다.
  Graph? graphWhenAcked;
  AppDatabase? _db;

  void bind(AppDatabase db) => _db = db;

  @override
  Future<ThoughtmapUpdateOut> updateThoughtmap(Graph graph, UserContext ctx) async {
    return const ThoughtmapUpdateOut(
      graph: Graph(nodes: [
        GraphNode(
          id: 'c_환율',
          concept: '환율',
          state: NodeState.understood,
          isPrereq: false,
        ),
      ]),
      recommendations: Recommendations(),
      consumedScrapIds: ['s1', 's2'],
    );
  }

  @override
  Future<void> ackScraps(List<String> scrapIds) async {
    if (failAck) {
      throw const AppException(code: 'x', message: 'ack 실패');
    }
    ackedScrapIds.addAll(scrapIds);
    graphWhenAcked = await _db?.loadGraph();
  }

  @override
  Future<ExploreResult> explore(ExploreRequest req) async => ExploreResult.empty;
  @override
  Future<TokenOut> login(String e, String p) async =>
      const TokenOut(accessToken: 't', userId: 'u');
  @override
  Future<String> signup(String e, String p) async => 'u';
  @override
  Future<MeOut> me() async => const MeOut(userId: 'u', email: 'u@e.com');
}
