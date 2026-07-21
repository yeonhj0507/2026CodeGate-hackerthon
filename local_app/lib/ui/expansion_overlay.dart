import '../data/dto/graph.dart';
import '../data/dto/recommendation.dart';

/// 확장 후보를 지도에 **임시 노드**로 얹은 그래프를 만든다.
///
/// 추천 패널이 열려 있는 동안만 쓰는 표시용 그래프다. 로컬 DB 에는 쓰지 않으므로
/// 패널을 닫으면 사라지고, 다음 동기화에도 남지 않는다.
///
/// 명세 §4.4 는 확장 후보를 "수락 전까지 그래프 비노출"로 뒀는데, 그러면 카드에
/// 낱말만 뜰 뿐 그 개념이 **내가 아는 것 중 무엇에서 나왔는지**가 보이지 않는다.
/// 회색 노드로 띄우고 근거 개념과 선으로 이어 주면 그 관계가 그대로 드러난다.
///
/// 노드 상태는 `unknown` 이라 회색("추천 개념")으로 그려지고, 이해완료/미이해
/// 집계에도 잡히지 않는다. 엣지는 `related` 라 선행 관계보다 옅게 나온다.
Graph withExpansionCandidates(Graph graph, List<ExpansionRecommendation> expansions) {
  if (expansions.isEmpty) return graph;

  final existing = {for (final n in graph.nodes) n.id};

  final nodes = <GraphNode>[];
  final edges = <GraphEdge>[];

  for (final e in expansions) {
    // 서버는 그래프에 없는 개념만 보내지만, 그 사이 동기화로 들어왔을 수 있다.
    if (e.conceptId.isEmpty || existing.contains(e.conceptId)) continue;
    existing.add(e.conceptId);

    nodes.add(GraphNode(
      id: e.conceptId,
      concept: e.conceptTag,
      state: NodeState.unknown,
      isPrereq: false,
    ));

    // 근거가 된 내 개념마다 선을 잇는다 — "무엇에서 뻗어 나왔는지"가 곧 이유다.
    for (final via in e.viaConcepts) {
      if (!graph.nodes.any((n) => n.id == via)) continue;
      edges.add(GraphEdge(from: via, to: e.conceptId, type: EdgeType.related));
    }
  }

  if (nodes.isEmpty) return graph;

  return Graph(
    nodes: [...graph.nodes, ...nodes],
    edges: [...graph.edges, ...edges],
  );
}
