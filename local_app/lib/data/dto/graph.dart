/// 지식그래프(생각 지도) 교환 스키마.
///
/// 계약 출처: `구현계획_3_로컬앱_서버기능.md` §4
///   nodes: [{id, concept, state, isPrereq, sourceArticles[], summaryMeta}]
///   edges: [{from, to, type}]
///
/// 서버 담당자와의 계약이므로 필드명을 바꾸지 않는다.
library;

/// 노드 이해상태. 서버가 아직 확정 전이므로 **문자열 원본을 보존**하고
/// 표시할 때만 매핑한다. 미지의 값이 와도 유실되지 않게 하기 위함.
abstract final class NodeState {
  static const understood = 'understood';
  static const notUnderstood = 'not_understood';

  /// 아직 진단되지 않은 개념(추천으로만 등장한 노드 등).
  static const unknown = 'unknown';
}

/// 엣지 종류. 선행→후행이 기본(명세 §5.1 "말단 노드 = 선행 개념어").
abstract final class EdgeType {
  static const prereq = 'prereq';
  static const related = 'related';
}

class GraphNode {
  const GraphNode({
    required this.id,
    required this.concept,
    required this.state,
    required this.isPrereq,
    this.sourceArticles = const [],
    this.summaryMeta,
  });

  final String id;
  final String concept;

  /// [NodeState] 참고. 알 수 없는 값도 그대로 보존한다.
  final String state;

  /// 선행개념 노드 여부. 그래프 말단에 위치한다.
  final bool isPrereq;

  /// 이 개념이 등장한 기사 제목들. 크로스기사 병합 결과로 복수가 될 수 있다.
  final List<String> sourceArticles;

  /// 개인화 요약이 흡수된 자리(명세 §4.4). 미이해 개념의 재요약·보충설명.
  final String? summaryMeta;

  bool get isUnderstood => state == NodeState.understood;
  bool get isNotUnderstood => state == NodeState.notUnderstood;

  GraphNode copyWith({
    String? state,
    List<String>? sourceArticles,
    String? summaryMeta,
  }) {
    return GraphNode(
      id: id,
      concept: concept,
      state: state ?? this.state,
      isPrereq: isPrereq,
      sourceArticles: sourceArticles ?? this.sourceArticles,
      summaryMeta: summaryMeta ?? this.summaryMeta,
    );
  }

  factory GraphNode.fromJson(Map<String, dynamic> json) {
    return GraphNode(
      id: json['id'] as String,
      concept: json['concept'] as String? ?? json['id'] as String,
      state: json['state'] as String? ?? NodeState.unknown,
      isPrereq: json['isPrereq'] as bool? ?? false,
      sourceArticles: (json['sourceArticles'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      summaryMeta: json['summaryMeta'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'concept': concept,
        'state': state,
        'isPrereq': isPrereq,
        'sourceArticles': sourceArticles,
        'summaryMeta': summaryMeta,
      };
}

class GraphEdge {
  const GraphEdge({
    required this.from,
    required this.to,
    this.type = EdgeType.prereq,
  });

  /// 선행 개념 노드 id.
  final String from;

  /// 후행 개념 노드 id.
  final String to;

  final String type;

  factory GraphEdge.fromJson(Map<String, dynamic> json) {
    return GraphEdge(
      from: json['from'] as String,
      to: json['to'] as String,
      type: json['type'] as String? ?? EdgeType.prereq,
    );
  }

  Map<String, dynamic> toJson() => {'from': from, 'to': to, 'type': type};
}

class Graph {
  const Graph({this.nodes = const [], this.edges = const []});

  final List<GraphNode> nodes;
  final List<GraphEdge> edges;

  static const empty = Graph();

  bool get isEmpty => nodes.isEmpty;

  GraphNode? nodeById(String id) {
    for (final n in nodes) {
      if (n.id == id) return n;
    }
    return null;
  }

  factory Graph.fromJson(Map<String, dynamic> json) {
    return Graph(
      nodes: (json['nodes'] as List<dynamic>? ?? const [])
          .map((e) => GraphNode.fromJson(e as Map<String, dynamic>))
          .toList(),
      edges: (json['edges'] as List<dynamic>? ?? const [])
          .map((e) => GraphEdge.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'nodes': nodes.map((e) => e.toJson()).toList(),
        'edges': edges.map((e) => e.toJson()).toList(),
      };
}
