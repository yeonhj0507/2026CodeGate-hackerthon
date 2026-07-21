import '../api/api_client.dart';
import '../db/database.dart';
import '../dto/graph.dart';
import '../dto/recommendation.dart';

/// 한 번의 동기화 결과.
class SyncResult {
  const SyncResult({
    required this.graph,
    required this.recommendations,
    required this.syncedAt,
    required this.addedNodeCount,
  });

  final Graph graph;
  final Recommendations recommendations;
  final DateTime syncedAt;

  /// 이번 동기화로 새로 생긴 노드 수. "스크랩이 반영됐다"를 UI로 보여주는 근거.
  final int addedNodeCount;
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
    await _db.recordAppliedScraps(res.graph);

    final before = localGraph.nodes.map((n) => n.id).toSet();
    final added = res.graph.nodes.where((n) => !before.contains(n.id)).length;

    return SyncResult(
      graph: res.graph,
      recommendations: res.recommendations,
      syncedAt: DateTime.now(),
      addedNodeCount: added,
    );
  }

  Future<List<AppliedScrapRow>> appliedScraps() => _db.loadAppliedScraps();
}
