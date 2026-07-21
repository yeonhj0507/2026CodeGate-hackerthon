/// 방사형 레이아웃을 눈으로 튜닝하기 위한 더미 그래프 생성기(개발용).
///
/// 실제 스크랩·퀴즈 흐름 없이 **기사–level0–level1–level2** 구조를 그대로 흉내 낸다.
/// 기사 노드는 [withArticleNodes] 가 개념의 sourceArticles 로부터 파생하므로, 여기서는
/// 개념 노드와 선행(prereq) 엣지만 만든다. level0 은 비선행(isPrereq=false)이라 기사 선이
/// 붙고, level1·level2 는 선행이라 바깥 고리로 이어진다(article_nodes.dart 규칙).
///
/// 프로덕션 코드가 아니다 — `radial_preview.dart` 진입점에서만 쓴다.
library;

import '../data/dto/graph.dart';

/// [articles]개의 기사 클러스터를 만든다. 각 기사는 [level0PerArticle]개의 핵심 개념을,
/// 그 각각은 [level1PerLevel0]개의 선행을, 다시 그 각각은 [level2PerLevel1]개의
/// 선행선행을 가진다.
Graph buildDummyGraph({
  int articles = 4,
  int level0PerArticle = 3,
  int level1PerLevel0 = 2,
  int level2PerLevel1 = 1,
}) {
  final nodes = <GraphNode>[];
  final edges = <GraphEdge>[];

  // 색이 단조롭지 않게 상태를 돌려 준다.
  const states = [
    NodeState.understood,
    NodeState.notUnderstood,
    NodeState.unknown,
  ];

  for (var a = 0; a < articles; a++) {
    final src = SourceArticle(
      url: 'https://dummy.example/article-$a',
      title: '더미 기사 ${a + 1}',
    );

    for (var i = 0; i < level0PerArticle; i++) {
      final l0 = 'c_a${a}_l0_$i';
      nodes.add(GraphNode(
        id: l0,
        concept: '기사${a + 1}·핵심${i + 1}',
        state: states[(a + i) % states.length],
        isPrereq: false,
        sourceArticles: [src],
      ));

      for (var j = 0; j < level1PerLevel0; j++) {
        final l1 = 'c_a${a}_l0_${i}_l1_$j';
        nodes.add(GraphNode(
          id: l1,
          concept: '선행 ${i + 1}-${j + 1}',
          state: states[(i + j + 1) % states.length],
          isPrereq: true,
          sourceArticles: [src],
        ));
        edges.add(GraphEdge(from: l1, to: l0, type: EdgeType.prereq));

        for (var k = 0; k < level2PerLevel1; k++) {
          final l2 = 'c_a${a}_l0_${i}_l1_${j}_l2_$k';
          nodes.add(GraphNode(
            id: l2,
            concept: '선행² ${i + 1}-${j + 1}-${k + 1}',
            state: NodeState.unknown,
            isPrereq: true,
            sourceArticles: [src],
          ));
          edges.add(GraphEdge(from: l2, to: l1, type: EdgeType.prereq));
        }
      }
    }
  }

  return Graph(nodes: nodes, edges: edges);
}
