import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prober_local/data/api/mock_api_client.dart';
import 'package:prober_local/data/db/database.dart';
import 'package:prober_local/data/dto/graph.dart';
import 'package:prober_local/data/repository/thoughtmap_repository.dart';
import 'package:prober_local/data/xp/xp_rules.dart';

/// 경험치 규칙 검증.
///
/// XP는 "동기화 전후 그래프의 차이"에서만 나온다(`xp_rules.dart` 주석). 그래서
/// 규칙 테스트는 순수 함수로, 적립 테스트는 실제 SQLite로 나눠 본다.
void main() {
  GraphNode node(
    String id, {
    String state = NodeState.understood,
    bool prereq = false,
    List<String> articles = const ['a'],
  }) {
    return GraphNode(
      id: id,
      concept: id,
      state: state,
      isPrereq: prereq,
      sourceArticles: [
        for (final a in articles) SourceArticle(url: 'https://x/$a', title: a),
      ],
    );
  }

  Set<String> kindsOf(List<XpEvent> events) =>
      events.map((e) => e.kindName).toSet();

  group('규칙 판정', () {
    test('새로 맞힌 개념은 정답 XP', () {
      final events = evaluateGraphXp(
        before: Graph.empty,
        after: Graph(nodes: [node('금리')]),
      );

      expect(kindsOf(events), {XpKind.correctAnswer.name});
    });

    test('오답으로 남은 선행 개념도 재질문 완주로 보상한다', () {
      // 회피를 막는 규칙이므로 state가 미이해여도 XP가 나와야 한다.
      final events = evaluateGraphXp(
        before: Graph.empty,
        after: Graph(nodes: [
          node('물가상승률', state: NodeState.notUnderstood, prereq: true),
        ]),
      );

      expect(kindsOf(events), {XpKind.followupCompleted.name});
    });

    test('아직 진단되지 않은(unknown) 선행 개념에는 주지 않는다', () {
      // 관계는 정오답과 무관하게 올라오므로 unknown 노드가 그냥 생길 수 있다.
      final events = evaluateGraphXp(
        before: Graph.empty,
        after: Graph(nodes: [
          node('탄소배출권', state: NodeState.unknown, prereq: true),
        ]),
      );

      expect(events, isEmpty);
    });

    test('미이해가 이해로 바뀌면 전환 XP', () {
      final events = evaluateGraphXp(
        before: Graph(nodes: [node('실질금리', state: NodeState.notUnderstood)]),
        after: Graph(nodes: [node('실질금리')]),
      );

      expect(kindsOf(events), {XpKind.understoodTransition.name});
    });

    test('선행을 먼저 뚫고 뒤집으면 재도전 성공으로 승격된다', () {
      // `from`=후행 → `to`=선행. 예전 픽스처는 두 노드가 대칭이라 방향을
      // 뒤집어도 통과했다 — 아래 dedupeKey 단언으로 누가 받는지까지 못 박는다.
      const edges = [GraphEdge(from: '실질금리', to: '물가상승률')];
      final events = evaluateGraphXp(
        before: Graph(
          nodes: [
            node('물가상승률', state: NodeState.notUnderstood, prereq: true),
            node('실질금리', state: NodeState.notUnderstood),
          ],
          edges: edges,
        ),
        after: Graph(
          nodes: [node('물가상승률', prereq: true), node('실질금리')],
          edges: edges,
        ),
      );

      // 선행은 그냥 전환, 후행은 재도전 성공. 한 노드가 둘 다 받지는 않는다.
      expect(kindsOf(events), {
        XpKind.understoodTransition.name,
        XpKind.retrySuccess.name,
      });
      expect(events.where((e) => e.dedupeKey == 'understood:실질금리'), hasLength(1));
      // 재도전 성공은 **후행**(실질금리)이 받는다. 선행은 그냥 전환이다.
      expect(
        events.singleWhere((e) => e.kindName == XpKind.retrySuccess.name).dedupeKey,
        'understood:실질금리',
      );
    });

    test('같은 기사 안의 연결에는 기사 잇기 XP가 없다', () {
      final events = evaluateGraphXp(
        before: Graph.empty,
        after: Graph(
          nodes: [node('가', articles: ['a1']), node('나', articles: ['a1'])],
          edges: const [GraphEdge(from: '가', to: '나')],
        ),
      );

      expect(kindsOf(events), isNot(contains(XpKind.crossArticleLink.name)));
    });

    test('다른 기사에서 온 개념이 이어지면 기사 잇기 XP', () {
      final events = evaluateGraphXp(
        before: Graph.empty,
        after: Graph(
          nodes: [
            node('가', articles: ['a1', 'a2']),
            node('나', articles: ['a2']),
          ],
          edges: const [GraphEdge(from: '가', to: '나')],
        ),
      );

      expect(kindsOf(events), contains(XpKind.crossArticleLink.name));
    });

    test('이미 있던 엣지는 다시 세지 않는다', () {
      const edges = [GraphEdge(from: '가', to: '나')];
      final graph = Graph(
        nodes: [
          node('가', articles: ['a1', 'a2']),
          node('나', articles: ['a2']),
        ],
        edges: edges,
      );

      expect(evaluateGraphXp(before: graph, after: graph), isEmpty);
    });

    test('새로 반영된 기사마다 완독 XP', () {
      final events = evaluateGraphXp(
        before: Graph.empty,
        after: Graph.empty,
        newArticles: ['기사 1', '기사 2'],
      );

      expect(events, hasLength(2));
      expect(kindsOf(events), {XpKind.articleCompleted.name});
    });
  });

  group('적립·중복 방지', () {
    late AppDatabase db;
    late ThoughtmapRepository repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = ThoughtmapRepository(api: MockApiClient(random: Random(0)), db: db);
    });

    tearDown(() => db.close());

    test('같은 사건은 두 번 적립되지 않는다', () async {
      final event = XpEvent.of(
        XpKind.correctAnswer,
        dedupeKey: 'correct:c_금리',
        detail: '금리',
      );

      expect(await db.awardXp([event]), hasLength(1));
      expect(await db.awardXp([event]), isEmpty);
      expect((await db.loadXpSummary()).total, XpKind.correctAnswer.amount);
    });

    test('동기화가 XP를 적립한다', () async {
      final first = await repo.sync();

      expect(first.xpGained, greaterThan(0));
      expect((await repo.loadXp()).total, first.xpGained);
      expect((await repo.loadXp()).recent, isNotEmpty);
    });

    test('웨이브를 모두 소진하면 더 이상 XP가 늘지 않는다', () async {
      var total = 0;
      for (var i = 0; i < 10; i++) {
        total += (await repo.sync()).xpGained;
      }

      expect((await repo.loadXp()).total, total);
      // 버퍼가 빈 뒤의 동기화는 그래프를 바꾸지 않으므로 0이어야 한다.
      expect((await repo.sync()).xpGained, 0);
    });

    test('첫 접속에만 스트릭 XP가 붙고 스트릭은 1일이다', () async {
      final first = await repo.registerVisit();
      expect(first.isFirstToday, isTrue);
      expect(first.streak, 1);

      final second = await repo.registerVisit();
      expect(second.isFirstToday, isFalse);

      expect((await repo.loadXp()).total, XpKind.streakDay.amount);
      expect((await repo.loadXp()).streak, 1);
    });

    test('로그아웃하면 XP도 함께 비워진다', () async {
      await repo.registerVisit();
      expect((await repo.loadXp()).total, greaterThan(0));

      await db.wipe();

      expect((await repo.loadXp()).total, 0);
      expect((await repo.loadXp()).streak, 0);
    });
  });

  group('화면 효과 판정', () {
    XpEvent event(XpKind kind, String key) =>
        XpEvent.of(kind, dedupeKey: key, detail: '');

    test('재도전 성공·기사 잇기만 축하 이벤트다', () {
      expect(XpKind.retrySuccess.isCelebration, isTrue);
      expect(XpKind.crossArticleLink.isCelebration, isTrue);
      expect(XpKind.correctAnswer.isCelebration, isFalse);
      expect(XpKind.followupCompleted.isCelebration, isFalse);
      expect(XpKind.understoodTransition.isCelebration, isFalse);
      expect(XpKind.articleCompleted.isCelebration, isFalse);
      expect(XpKind.streakDay.isCelebration, isFalse);
    });

    test('이전 스냅샷에 없던 이벤트만 "새로 도착"으로 본다', () {
      final before = XpSnapshot(
        total: 10,
        recent: [event(XpKind.correctAnswer, 'a')],
      );
      final after = XpSnapshot(
        total: 25,
        recent: [
          event(XpKind.correctAnswer, 'b'), // 새로 옴
          event(XpKind.correctAnswer, 'a'), // 이전에도 있었다
        ],
      );

      final arrived = newlyArrivedEvents(before, after);

      expect(arrived.map((e) => e.dedupeKey), ['b']);
    });

    test('이전 스냅샷이 없으면(첫 로드) 전부 새로 도착한 것으로 본다', () {
      final after = XpSnapshot(
        recent: [event(XpKind.correctAnswer, 'a')],
      );

      // 이 함수 자체는 그대로 전부를 "새로 도착"으로 낸다 — 맞는 동작이다.
      // 문제는 호출부(XpBadge)가 이걸 곧이곧대로 축하 트리거로 쓰면 안 된다는
      // 것: XpController는 XpSnapshot.empty로 시작해 refresh()가 끝나야
      // 실제 값을 받으므로, 그 첫 전환에서 이 함수를 그대로 믿으면 과거 이력
      // 전체가 "방금 얻었다"로 오인된다. 그래서 XpBadge는 prev가
      // XpSnapshot.empty(첫 로드의 시작점)일 때는 이 함수의 결과를 아예
      // 쓰지 않고 건너뛴다 — 그 가드는 여기가 아니라 xp_panel.dart에 있다.
      final arrived = newlyArrivedEvents(null, after);

      expect(arrived.map((e) => e.dedupeKey), ['a']);
    });

    test('아무것도 새로 오지 않으면 빈 목록이다', () {
      final snapshot = XpSnapshot(recent: [event(XpKind.correctAnswer, 'a')]);

      expect(newlyArrivedEvents(snapshot, snapshot), isEmpty);
    });

    test('동기화 한 번에 여러 건이 와도 전부 잡는다', () {
      final before = const XpSnapshot(recent: []);
      final after = XpSnapshot(
        recent: [
          event(XpKind.retrySuccess, 'r1'),
          event(XpKind.crossArticleLink, 'x1'),
          event(XpKind.correctAnswer, 'c1'),
        ],
      );

      final arrived = newlyArrivedEvents(before, after);

      expect(arrived, hasLength(3));
      expect(arrived.any((e) => e.kind?.isCelebration ?? false), isTrue);
    });
  });
}
