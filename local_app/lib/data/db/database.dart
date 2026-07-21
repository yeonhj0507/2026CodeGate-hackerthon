import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../dto/graph.dart';
import '../dto/user_context.dart';
import '../xp/xp_rules.dart';
import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [
  GraphNodes,
  GraphEdges,
  LearningHistories,
  ArticlePreferences,
  AppliedScraps,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? driftDatabase(name: 'prober_local'));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          // v2: 추천 탭 개념 상세의 O/X 문항 보관 컬럼 추가.
          // 기존 사용자 기기의 그래프·학습이력은 그대로 두고 컬럼만 붙인다.
          if (from < 2) await m.addColumn(graphNodes, graphNodes.oxQuizJson);
        },
        beforeOpen: (_) async {
          // XP 테이블은 drift 스키마가 아니라 **raw SQL**로 둔다.
          //
          // drift 테이블로 선언하면 `database.g.dart`를 다시 생성해야 하는데,
          // 코드 생성은 이 프로젝트에서 그래프 스키마 하나로 묶어 둔 의존성이다
          // (pubspec 주석 참고). XP는 그래프 계약과 무관한 로컬 부가 데이터라
          // 같은 SQLite 파일에 얹되 생성 코드는 건드리지 않는다.
          // `IF NOT EXISTS`라서 신규 설치·기존 기기 모두 이 한 줄로 끝난다.
          await customStatement('''
            CREATE TABLE IF NOT EXISTS xp_events (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              kind TEXT NOT NULL,
              amount INTEGER NOT NULL,
              detail TEXT NOT NULL DEFAULT '',
              dedupe_key TEXT NOT NULL UNIQUE,
              occurred_at INTEGER NOT NULL
            )
          ''');
          await customStatement(
            'CREATE TABLE IF NOT EXISTS xp_visits (day TEXT NOT NULL PRIMARY KEY)',
          );
        },
      );

  // ── 그래프 읽기 ─────────────────────────────────────────────

  /// 로컬에 보관된 그래프 원본을 통째로 읽는다.
  Future<Graph> loadGraph() async {
    final nodeRows = await select(graphNodes).get();
    final edgeRows = await select(graphEdges).get();
    return Graph(
      nodes: nodeRows.map(_toNode).toList(),
      edges: edgeRows
          .map((r) => GraphEdge(from: r.fromId, to: r.toId, type: r.type))
          .toList(),
    );
  }

  /// 그래프 변경을 구독한다. 동기화 후 UI가 자동 갱신되도록.
  Stream<Graph> watchGraph() {
    return select(graphNodes).watch().asyncMap((_) => loadGraph());
  }

  static GraphNode _toNode(GraphNodeRow row) => GraphNode(
        id: row.id,
        concept: row.concept,
        state: row.state,
        isPrereq: row.isPrereq,
        // 구형 로컬 DB에는 제목 문자열만 들어 있다. fromDynamic 이 둘 다 흡수하고,
        // mergeAll 이 구형(URL 없음)과 신형(URL 있음)의 같은 기사를 한 건으로 접는다.
        sourceArticles: SourceArticle.mergeAll(
          (jsonDecode(row.sourceArticlesJson) as List<dynamic>)
              .map(SourceArticle.fromDynamic),
        ),
        summaryMeta: row.summaryMeta,
        oxQuiz: row.oxQuizJson == null
            ? null
            : OxQuiz.fromJson(jsonDecode(row.oxQuizJson!) as Map<String, dynamic>),
      );

  // ── 그래프 쓰기 ─────────────────────────────────────────────

  /// 서버가 돌려준 그래프를 로컬 원본으로 채택한다.
  ///
  /// 병합 정책(구현계획③ §3.2 확정): 서버는 기존 graph를 **입력받아** 갱신하므로
  /// 응답본이 곧 최신이다. 따라서 부분 병합이 아니라 트랜잭션 내 전량 교체한다.
  /// 충돌 해소는 서버 책임.
  Future<void> replaceGraph(Graph graph) async {
    final now = DateTime.now().toUtc();
    await transaction(() async {
      await delete(graphEdges).go();
      await delete(graphNodes).go();

      await batch((b) {
        b.insertAll(
          graphNodes,
          graph.nodes.map((n) => GraphNodesCompanion.insert(
                id: n.id,
                concept: n.concept,
                state: n.state,
                isPrereq: Value(n.isPrereq),
                sourceArticlesJson:
                    Value(jsonEncode(n.sourceArticles.map((a) => a.toJson()).toList())),
                summaryMeta: Value(n.summaryMeta),
                oxQuizJson: Value(
                  n.oxQuiz == null ? null : jsonEncode(n.oxQuiz!.toJson()),
                ),
                updatedAt: now,
              )),
        );
        b.insertAll(
          graphEdges,
          graph.edges.map((e) => GraphEdgesCompanion.insert(
                fromId: e.from,
                toId: e.to,
                type: e.type,
              )),
          mode: InsertMode.insertOrReplace,
        );
      });
    });
  }

  /// 노드 하나의 이해상태만 바꾼다.
  ///
  /// 로컬에서 상태를 바꿔도 다음 동기화에서 되돌아가지 않는다. 서버 `merge.py` 는
  /// 클라이언트가 올린 그래프로 노드를 채운 뒤 **이번 스크랩에 등장한 개념만**
  /// 상태를 덮기 때문이다. 같은 기사를 다시 읽고 또 틀리지 않는 한 유지된다.
  Future<void> setNodeState(String nodeId, String state) async {
    await (update(graphNodes)..where((t) => t.id.equals(nodeId))).write(
      GraphNodesCompanion(
        state: Value(state),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  // ── 사용자 컨텍스트 ─────────────────────────────────────────

  /// 서버로 보낼 사용자 컨텍스트를 조립한다(명세 §4.4 입력 ③).
  Future<UserContext> loadUserContext({int historyLimit = 200}) async {
    final history = await (select(learningHistories)
          ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)])
          ..limit(historyLimit))
        .get();
    final prefs = await (select(articlePreferences)
          ..orderBy([(t) => OrderingTerm.desc(t.weight)]))
        .get();

    return UserContext(
      learningHistory: history
          .map((r) => LearningHistoryItem(
                conceptTag: r.conceptTag,
                parentConcept: r.parentConcept,
                level: r.level,
                correct: r.correct,
                articleTitle: r.articleTitle,
                occurredAt: r.occurredAt,
              ))
          .toList(),
      articlePreferences: prefs
          .map((r) => ArticlePreferenceItem(
                keyword: r.keyword,
                category: r.category,
                weight: r.weight,
              ))
          .toList(),
    );
  }

  /// 동기화로 새로 알게 된 사실을 로컬 학습이력에 남긴다.
  ///
  /// 익스텐션의 스크랩은 서버 버퍼를 거쳐 그래프로만 돌아오므로, 로컬은
  /// 갱신 그래프의 노드 상태에서 이력을 역산해 축적한다.
  Future<void> recordSyncOutcome(Graph graph) async {
    final now = DateTime.now().toUtc();
    // 엣지는 `from`=후행 → `to`=선행. parentConcept 는 "먼저 알아야 했던 개념"
    // 이라 후행 노드에 선행을 달아 준다.
    final parentOf = <String, String>{
      for (final e in graph.edges)
        if (e.type == EdgeType.prereq) e.from: e.to,
    };

    await batch((b) {
      b.insertAll(
        learningHistories,
        graph.nodes
            .where((n) => n.state != NodeState.unknown)
            .map((n) => LearningHistoriesCompanion.insert(
                  conceptTag: n.concept,
                  parentConcept: Value(parentOf[n.id]),
                  level: Value(n.isPrereq ? 1 : 0),
                  correct: n.isUnderstood,
                  articleTitle: Value(n.sourceArticles.isEmpty
                      ? null
                      : n.sourceArticles.last.label),
                  occurredAt: now,
                )),
      );
    });

    // 출처 기사 제목을 선호 패턴 가중치로 환산(간이 랭킹 근거).
    final titles = <String>{
      for (final n in graph.nodes)
        for (final a in n.sourceArticles) a.label,
    };
    for (final title in titles) {
      await into(articlePreferences).insertOnConflictUpdate(
        ArticlePreferencesCompanion.insert(
          keyword: title,
          weight: const Value(1),
          updatedAt: now,
        ),
      );
    }
  }

  /// 이번 동기화로 반영된 기사들을 "영구 반영본"으로 기록(명세 §5.1).
  ///
  /// 이번에 **처음** 기록된 기사 제목을 돌려준다 — 기사 완독 XP의 근거다.
  Future<List<String>> recordAppliedScraps(Graph graph) async {
    final now = DateTime.now().toUtc();
    final counts = <String, int>{};
    for (final n in graph.nodes) {
      for (final a in n.sourceArticles) {
        counts[a.label] = (counts[a.label] ?? 0) + 1;
      }
    }
    final known = (await select(appliedScraps).get())
        .map((r) => r.articleTitle)
        .toSet();
    final fresh =
        counts.entries.where((e) => !known.contains(e.key)).toList();

    await batch((b) {
      b.insertAll(
        appliedScraps,
        fresh.map(
          (e) => AppliedScrapsCompanion.insert(
            articleTitle: e.key,
            nodeCount: Value(e.value),
            appliedAt: now,
          ),
        ),
      );
    });

    return fresh.map((e) => e.key).toList();
  }

  Future<List<AppliedScrapRow>> loadAppliedScraps() {
    return (select(appliedScraps)
          ..orderBy([(t) => OrderingTerm.desc(t.appliedAt)]))
        .get();
  }

  // ── 경험치 ──────────────────────────────────────────────────
  //
  // 테이블이 drift 스키마 밖(raw SQL)이라 여기서는 customSelect/customInsert로
  // 다룬다. 대신 `xp_events.dedupe_key`가 UNIQUE라 같은 사건은 몇 번 판정해도
  // 한 번만 쌓인다 — 동기화 버튼을 연타해도 XP가 부풀지 않는다.

  /// 아직 지급되지 않은 사건만 골라 적립하고, **실제로 지급된 것**을 돌려준다.
  Future<List<XpEvent>> awardXp(List<XpEvent> events) async {
    if (events.isEmpty) return const [];

    final granted = <XpEvent>[];
    await transaction(() async {
      final keys = events.map((e) => e.dedupeKey).toList();
      final placeholders = List.filled(keys.length, '?').join(',');
      final existing = (await customSelect(
        'SELECT dedupe_key FROM xp_events WHERE dedupe_key IN ($placeholders)',
        variables: keys.map(Variable<String>.new).toList(),
      ).get())
          .map((r) => r.read<String>('dedupe_key'))
          .toSet();

      for (final e in events) {
        if (!existing.add(e.dedupeKey)) continue; // 이미 받았거나 같은 배치 내 중복
        await customInsert(
          'INSERT OR IGNORE INTO xp_events '
          '(kind, amount, detail, dedupe_key, occurred_at) VALUES (?, ?, ?, ?, ?)',
          variables: [
            Variable<String>(e.kindName),
            Variable<int>(e.amount),
            Variable<String>(e.detail),
            Variable<String>(e.dedupeKey),
            Variable<int>(e.occurredAt.toUtc().millisecondsSinceEpoch),
          ],
        );
        granted.add(e);
      }
    });
    return granted;
  }

  /// 총 XP·스트릭·최근 내역을 한 번에 읽는다.
  Future<XpSnapshot> loadXpSummary({int recentLimit = 20}) async {
    final totalRow = await customSelect(
      'SELECT COALESCE(SUM(amount), 0) AS total FROM xp_events',
    ).getSingle();

    final rows = await customSelect(
      'SELECT kind, amount, detail, dedupe_key, occurred_at FROM xp_events '
      'ORDER BY id DESC LIMIT ?',
      variables: [Variable<int>(recentLimit)],
    ).get();

    return XpSnapshot(
      total: totalRow.read<int>('total'),
      streak: await currentStreak(DateTime.now()),
      recent: rows
          .map((r) => XpEvent(
                kindName: r.read<String>('kind'),
                amount: r.read<int>('amount'),
                detail: r.read<String>('detail'),
                dedupeKey: r.read<String>('dedupe_key'),
                occurredAt: DateTime.fromMillisecondsSinceEpoch(
                  r.read<int>('occurred_at'),
                  isUtc: true,
                ).toLocal(),
              ))
          .toList(),
    );
  }

  /// 오늘 접속을 남기고 현재 스트릭을 돌려준다. 하루에 한 줄만 쌓인다.
  Future<VisitOutcome> recordVisit(DateTime now) async {
    final today = _dayKey(now);
    final seen = await customSelect(
      'SELECT day FROM xp_visits WHERE day = ?',
      variables: [Variable<String>(today)],
    ).get();

    if (seen.isEmpty) {
      await customInsert(
        'INSERT OR IGNORE INTO xp_visits (day) VALUES (?)',
        variables: [Variable<String>(today)],
      );
    }

    return VisitOutcome(
      dayKey: today,
      isFirstToday: seen.isEmpty,
      streak: await currentStreak(now),
    );
  }

  /// 오늘부터 거꾸로 이어지는 연속 접속 일수. 어제까지 끊겼으면 0이다.
  Future<int> currentStreak(DateTime now) async {
    final days = (await customSelect(
      'SELECT day FROM xp_visits ORDER BY day DESC LIMIT 400',
    ).get())
        .map((r) => r.read<String>('day'))
        .toSet();

    var streak = 0;
    var cursor = DateTime(now.year, now.month, now.day);
    while (days.contains(_dayKey(cursor))) {
      streak++;
      // `subtract(Duration(days: 1))`이 아니라 날짜 성분으로 물러난다.
      // 서머타임이 있는 지역에서 자정 - 24시간은 전날 23시가 될 수 있다.
      cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
    }
    return streak;
  }

  static String _dayKey(DateTime t) {
    final m = t.month.toString().padLeft(2, '0');
    final d = t.day.toString().padLeft(2, '0');
    return '${t.year}-$m-$d';
  }

  /// 로그아웃 시 로컬 학습 데이터를 비운다.
  Future<void> wipe() async {
    await transaction(() async {
      await delete(graphEdges).go();
      await delete(graphNodes).go();
      await delete(learningHistories).go();
      await delete(articlePreferences).go();
      await delete(appliedScraps).go();
      // XP도 학습 데이터다 — 계정이 바뀌면 함께 비운다.
      await customStatement('DELETE FROM xp_events');
      await customStatement('DELETE FROM xp_visits');
    });
  }
}
