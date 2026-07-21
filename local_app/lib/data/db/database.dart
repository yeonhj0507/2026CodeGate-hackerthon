import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../dto/graph.dart';
import '../dto/user_context.dart';
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
      : super(
          executor ??
              driftDatabase(
                name: 'prober_local',
                // 웹(Chrome) 미리보기 전용 — 배포 타깃은 Windows 데스크톱이라
                // 네이티브 경로는 이 옵션을 쓰지 않는다.
                web: DriftWebOptions(
                  sqlite3Wasm: Uri.parse('sqlite3.wasm'),
                  driftWorker: Uri.parse('drift_worker.js'),
                ),
              ),
        );

  @override
  int get schemaVersion => 1;

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
    final parentOf = <String, String>{
      for (final e in graph.edges)
        if (e.type == EdgeType.prereq) e.to: e.from,
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
  Future<void> recordAppliedScraps(Graph graph) async {
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

    await batch((b) {
      b.insertAll(
        appliedScraps,
        counts.entries.where((e) => !known.contains(e.key)).map(
              (e) => AppliedScrapsCompanion.insert(
                articleTitle: e.key,
                nodeCount: Value(e.value),
                appliedAt: now,
              ),
            ),
      );
    });
  }

  Future<List<AppliedScrapRow>> loadAppliedScraps() {
    return (select(appliedScraps)
          ..orderBy([(t) => OrderingTerm.desc(t.appliedAt)]))
        .get();
  }

  /// 로그아웃 시 로컬 학습 데이터를 비운다.
  Future<void> wipe() async {
    await transaction(() async {
      await delete(graphEdges).go();
      await delete(graphNodes).go();
      await delete(learningHistories).go();
      await delete(articlePreferences).go();
      await delete(appliedScraps).go();
    });
  }
}
