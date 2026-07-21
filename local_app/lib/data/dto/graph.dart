/// 지식그래프(생각 지도) 교환 스키마.
///
/// 계약 출처: `구현계획_3_로컬앱_서버기능.md` §4
///   nodes: [{id, concept, state, isPrereq, sourceArticles:[{url,title}], summaryMeta, promoted}]
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

/// 노드의 출처 기사(명세 §7). **URL이 식별자**이고 원문은 담기지 않는다.
///
/// 같은 기사를 여러 번 읽어도 서버가 URL 기준으로 1건으로 유지하고,
/// 다른 URL에서 같은 개념이 나오면 누적된다(크로스기사 노드).
class SourceArticle {
  const SourceArticle({required this.url, this.title = ''});

  final String url;
  final String title;

  /// 표시용. 제목이 비면 URL이라도 보여 준다.
  String get label => title.isNotEmpty ? title : url;

  bool get hasUrl => url.isNotEmpty;

  factory SourceArticle.fromJson(Map<String, dynamic> json) {
    return SourceArticle(
      url: json['url'] as String? ?? '',
      title: json['title'] as String? ?? '',
    );
  }

  /// 구형 데이터 흡수용. 예전 로컬 DB에는 제목 문자열만 저장돼 있다.
  ///
  /// 서버 계약은 객체만 허용하지만(문자열을 보내면 422), 이미 사용자 기기에
  /// 저장된 문자열까지 버릴 이유는 없으므로 여기서만 관용적으로 받는다.
  factory SourceArticle.fromDynamic(dynamic value) {
    if (value is Map<String, dynamic>) return SourceArticle.fromJson(value);
    return SourceArticle(url: '', title: value.toString());
  }

  Map<String, dynamic> toJson() => {'url': url, 'title': title};

  /// 같은 기사끼리 합친다. **URL 이 식별자**이되, 한쪽에 URL 이 없으면 제목으로 맞춘다.
  ///
  /// 앱을 업데이트한 기기에서는 로컬 DB 에 URL 없는 구형 항목(`url: ''`)이 남아 있고,
  /// 서버는 같은 기사를 URL 과 함께 내려준다. 단순 합집합으로 두면 한 기사가 두 줄로
  /// 보이므로(실행 중 발견), 여기서 한 건으로 접고 URL 이 있는 쪽을 채택한다.
  static List<SourceArticle> mergeAll(Iterable<SourceArticle> items) {
    final byUrl = <String, SourceArticle>{};
    final byTitle = <String, SourceArticle>{};
    final order = <SourceArticle>[];

    void replace(SourceArticle old, SourceArticle fresh) {
      order[order.indexOf(old)] = fresh;
      if (fresh.url.isNotEmpty) byUrl[fresh.url] = fresh;
      if (fresh.title.isNotEmpty) byTitle[fresh.title] = fresh;
    }

    for (final item in items) {
      if (item.url.isEmpty && item.title.isEmpty) continue;

      final sameUrl = item.url.isEmpty ? null : byUrl[item.url];
      if (sameUrl != null) {
        // 제목이 나중에 채워진 경우를 보완.
        if (sameUrl.title.isEmpty && item.title.isNotEmpty) replace(sameUrl, item);
        continue;
      }

      final sameTitle = item.title.isEmpty ? null : byTitle[item.title];
      if (sameTitle != null) {
        // 구형(URL 없음) 항목이 먼저 들어와 있으면 URL 있는 쪽으로 승격.
        if (sameTitle.url.isEmpty && item.url.isNotEmpty) replace(sameTitle, item);
        continue;
      }

      order.add(item);
      if (item.url.isNotEmpty) byUrl[item.url] = item;
      if (item.title.isNotEmpty) byTitle[item.title] = item;
    }
    return order;
  }

  @override
  bool operator ==(Object other) =>
      other is SourceArticle && other.url == url && other.title == title;

  @override
  int get hashCode => Object.hash(url, title);
}

class GraphNode {
  const GraphNode({
    required this.id,
    required this.concept,
    required this.state,
    required this.isPrereq,
    this.sourceArticles = const [],
    this.summaryMeta,
    this.promoted = true,
  });

  final String id;
  final String concept;

  /// [NodeState] 참고. 알 수 없는 값도 그대로 보존한다.
  final String state;

  /// 선행개념 노드 여부. 그래프 말단에 위치한다.
  final bool isPrereq;

  /// 이 개념이 등장한 기사들. 크로스기사 병합 결과로 복수가 될 수 있다.
  final List<SourceArticle> sourceArticles;

  /// 개인화 요약이 흡수된 자리(명세 §4.4). 미이해 개념의 재요약·보충설명.
  final String? summaryMeta;

  /// 그래프 시각화 노출 여부(명세 §4.4). 확장 후보를 "수락 전 비노출"로 두기 위한 필드.
  ///
  /// 현재 서버의 확장 신호(재도전·형제)는 사용자가 이미 퀴즈로 만난 노드만 고르므로
  /// 강등이 일어나지 않아 사실상 항상 true 다. 그래서 SQLite 에는 저장하지 않고
  /// 전송 계약으로만 다룬다(저장하려면 drift 컬럼 추가 → 코드 생성 재실행이 필요하다).
  final bool promoted;

  bool get isUnderstood => state == NodeState.understood;
  bool get isNotUnderstood => state == NodeState.notUnderstood;

  GraphNode copyWith({
    String? state,
    List<SourceArticle>? sourceArticles,
    String? summaryMeta,
    bool? promoted,
  }) {
    return GraphNode(
      id: id,
      concept: concept,
      state: state ?? this.state,
      isPrereq: isPrereq,
      sourceArticles: sourceArticles ?? this.sourceArticles,
      summaryMeta: summaryMeta ?? this.summaryMeta,
      promoted: promoted ?? this.promoted,
    );
  }

  factory GraphNode.fromJson(Map<String, dynamic> json) {
    return GraphNode(
      id: json['id'] as String,
      concept: json['concept'] as String? ?? json['id'] as String,
      state: json['state'] as String? ?? NodeState.unknown,
      isPrereq: json['isPrereq'] as bool? ?? false,
      sourceArticles: (json['sourceArticles'] as List<dynamic>?)
              ?.map(SourceArticle.fromDynamic)
              .toList() ??
          const [],
      summaryMeta: json['summaryMeta'] as String?,
      promoted: json['promoted'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'concept': concept,
        'state': state,
        'isPrereq': isPrereq,
        'sourceArticles': sourceArticles.map((e) => e.toJson()).toList(),
        'summaryMeta': summaryMeta,
        'promoted': promoted,
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
