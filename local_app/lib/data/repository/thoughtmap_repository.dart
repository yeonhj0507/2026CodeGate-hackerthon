import '../api/api_client.dart';
import '../db/database.dart';
import '../dto/graph.dart';
import '../dto/recommendation.dart';
import '../xp/xp_rules.dart';

/// 한 번의 동기화 결과.
class SyncResult {
  const SyncResult({
    required this.graph,
    required this.recommendations,
    required this.syncedAt,
    required this.addedNodeCount,
    this.xpEvents = const [],
  });

  final Graph graph;
  final Recommendations recommendations;
  final DateTime syncedAt;

  /// 이번 동기화로 새로 생긴 노드 수. "스크랩이 반영됐다"를 UI로 보여주는 근거.
  final int addedNodeCount;

  /// 이번 동기화로 **실제 지급된** XP 사건들(이미 받은 건 빠져 있다).
  final List<XpEvent> xpEvents;

  int get xpGained =>
      xpEvents.fold(0, (sum, e) => sum + e.amount);
}

/// 흐름 B — 생각 지도 업데이트(명세 §6).
///
/// 로컬이 원본을 쥐고 있으므로 순서가 중요하다:
///   ① 로컬 graph + userContext를 조립해 서버로 보내고
///   ② 돌아온 graph를 로컬에 반영한다.
/// 이 시점에 서버 버퍼의 임시 스크랩이 소비·삭제된다(명세 §4.3).
class ThoughtmapRepository {
  ThoughtmapRepository({required ApiClient api, required AppDatabase db})
      : _api = api,
        _db = db;

  final ApiClient _api;
  final AppDatabase _db;

  Future<Graph> loadLocalGraph() => _db.loadGraph();

  Stream<Graph> watchLocalGraph() => _db.watchGraph();

  Future<SyncResult> sync() async {
    final localGraph = await _db.loadGraph();
    final ctx = await _db.loadUserContext();

    final res = await _api.updateThoughtmap(localGraph, ctx);

    // 서버 응답을 로컬 원본으로 채택(구현계획③ §3.2).
    await _db.replaceGraph(res.graph);
    await _db.recordSyncOutcome(res.graph);
    final newArticles = await _db.recordAppliedScraps(res.graph);

    // XP는 여기서만 판정한다. 익스텐션도 서버도 XP를 모른다 —
    // 동기화 전후 그래프의 차이가 곧 "사용자가 무엇을 해냈는가"다.
    final granted = await _db.awardXp(evaluateGraphXp(
      before: localGraph,
      after: res.graph,
      newArticles: newArticles,
    ));

    final before = localGraph.nodes.map((n) => n.id).toSet();
    final added = res.graph.nodes.where((n) => !before.contains(n.id)).length;

    return SyncResult(
      graph: res.graph,
      recommendations: res.recommendations,
      syncedAt: DateTime.now(),
      addedNodeCount: added,
      xpEvents: granted,
    );
  }

  Future<List<AppliedScrapRow>> appliedScraps() => _db.loadAppliedScraps();

  /// 추천 탭 O/X 를 맞혔을 때 — 그 개념을 이해완료로 올리고 XP를 준다.
  ///
  /// XP 판정은 [evaluateGraphXp] 를 그대로 태운다. 동기화와 같은 규칙(선행을
  /// 풀었으면 재도전 성공, 아니면 이해 전환)을 쓰고, **dedupeKey 도 같아서**
  /// 나중에 동기화가 같은 전환을 다시 계산해도 중복 지급되지 않는다.
  ///
  /// 미이해였던 노드만 대상이다. 이미 이해완료면 아무 일도 하지 않는다.
  Future<List<XpEvent>> markUnderstoodByOxQuiz(String nodeId) async {
    final before = await _db.loadGraph();
    final node = before.nodeById(nodeId);
    if (node == null || !node.isNotUnderstood) return const [];

    await _db.setNodeState(nodeId, NodeState.understood);
    final after = await _db.loadGraph();

    return _db.awardXp(evaluateGraphXp(before: before, after: after));
  }

  // ── 경험치 ──────────────────────────────────────────────────

  /// 앱을 연 사실을 남기고, 오늘 첫 접속이면 스트릭 XP를 준다.
  Future<VisitOutcome> registerVisit() async {
    final visit = await _db.recordVisit(DateTime.now());
    if (visit.isFirstToday) {
      await _db.awardXp([
        XpEvent.of(
          XpKind.streakDay,
          dedupeKey: 'streak:${visit.dayKey}',
          detail: '${visit.streak}일 연속 접속',
        ),
      ]);
    }
    return visit;
  }

  Future<XpSnapshot> loadXp() => _db.loadXpSummary();
}
