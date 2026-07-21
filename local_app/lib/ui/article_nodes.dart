/// 기사 노드 파생 — 개념 노드를 그 개념이 나온 기사와 줄로 잇는다.
///
/// **서버도 DB도 건드리지 않는다.** 필요한 정보가 이미 `GraphNode.sourceArticles`
/// 안에 다 있어서, 기사 노드는 기존 그래프의 순수 함수로 만들어진다. 보관함
/// 목록을 로컬 그래프에서 역산하는 것과 같은 방식이다(providers.dart libraryProvider).
///
/// 저장하지 않는 이유는 성능이 아니라 **오염 방지**다. 그래프는 동기화 때 서버로
/// 그대로 올라가는데(명세 §4.5 로컬이 원본), 거기에 기사 노드가 섞이면 서버가
/// 그걸 개념으로 알고 병합·추천·재요약을 돌린다. 화면에만 있어야 하는 것이다.
library;

import '../data/dto/graph.dart';

/// 기사 노드 id 접두사. 개념 노드 id(`c_…`)와 절대 겹치지 않게 둔다.
const String articleNodeIdPrefix = 'article::';

/// 기사 ↔ 개념을 잇는 엣지 타입. 서버 계약(prereq/related)에는 없는 값이고,
/// 이 엣지는 서버로 올라가지 않으므로 로컬에서만 의미를 갖는다.
const String articleEdgeType = 'source';

bool isArticleNodeId(String id) => id.startsWith(articleNodeIdPrefix);

/// 기사 식별자. URL 이 있으면 URL 이 기준이다(같은 기사의 제목이 바뀌어도 한 노드).
String articleKeyOf(SourceArticle article) =>
    article.url.isNotEmpty ? article.url : article.title;

String articleNodeId(SourceArticle article) =>
    '$articleNodeIdPrefix${articleKeyOf(article)}';

/// 화면에 그릴 그래프 = 원본 + 기사 노드 + 기사→개념 엣지.
///
/// 기사 노드의 `concept` 에 기사 제목이 들어간다. 제목이 비어 있으면 URL 을 쓴다
/// (`SourceArticle.label` 과 같은 규칙).
///
/// 개념이 하나뿐인 기사도 그대로 만든다. "이 개념은 이 기사에서 왔다"는 사실
/// 자체가 지도에서 읽히는 정보이고, 기사가 늘면 자연히 여러 갈래로 자란다.
Graph withArticleNodes(Graph graph) {
  if (graph.nodes.isEmpty) return graph;

  // 이미 들어 있는 것을 다시 만들지 않는다. 파생본을 다시 넣어도 결과가 같아야
  // 한다(멱등) — 빌드마다 도는 함수라 중복이 쌓이면 지도가 조용히 망가진다.
  final existingNodeIds = {for (final n in graph.nodes) n.id};
  final seenEdges = {for (final e in graph.edges) '${e.from}>${e.to}'};

  final articles = <String, SourceArticle>{};
  final edges = <GraphEdge>[];

  for (final node in graph.nodes) {
    if (isArticleNodeId(node.id)) continue;

    for (final article in node.sourceArticles) {
      final key = articleKeyOf(article);
      if (key.isEmpty) continue;

      final id = articleNodeId(article);
      // 제목이 있는 쪽을 대표로 채택한다 — 구형 데이터에는 URL 만 있는 항목이 있다.
      if (!existingNodeIds.contains(id)) {
        final known = articles[key];
        if (known == null || (known.title.isEmpty && article.title.isNotEmpty)) {
          articles[key] = article;
        }
      }

      if (seenEdges.add('$id>${node.id}')) {
        edges.add(GraphEdge(from: id, to: node.id, type: articleEdgeType));
      }
    }
  }

  if (articles.isEmpty && edges.isEmpty) return graph;

  return Graph(
    nodes: [
      ...graph.nodes,
      for (final entry in articles.entries)
        GraphNode(
          id: articleNodeId(entry.value),
          concept: entry.value.label,
          // 기사는 이해 대상이 아니다. unknown 으로 두면 개념 노드의 색 규칙
          // (이해완료/미이해)에 얹히지 않아 시각적으로도 구분된다.
          state: NodeState.unknown,
          isPrereq: false,
          sourceArticles: [entry.value],
        ),
    ],
    edges: [...graph.edges, ...edges],
  );
}
