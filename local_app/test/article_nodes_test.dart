import 'package:flutter_test/flutter_test.dart';
import 'package:prober_local/data/dto/graph.dart';
import 'package:prober_local/ui/article_nodes.dart';

/// 기사 노드 파생 규칙.
///
/// 가장 중요한 건 마지막 그룹이다 — 이 파생본이 저장·동기화 경로로 새어 나가면
/// 서버가 기사 제목을 개념으로 알고 병합·추천·재요약을 돌린다.
void main() {
  GraphNode concept(String id, {List<SourceArticle> from = const []}) => GraphNode(
        id: id,
        concept: id,
        state: NodeState.understood,
        isPrereq: false,
        sourceArticles: from,
      );

  const fedHold = SourceArticle(url: 'https://n.example/fed', title: '연준 동결');
  const chips = SourceArticle(url: 'https://n.example/chips', title: '반도체 수출');

  group('기사 노드 생성', () {
    test('개념이 나온 기사마다 노드와 줄이 생긴다', () {
      final out = withArticleNodes(Graph(nodes: [
        concept('c_기준금리', from: [fedHold]),
      ]));

      final article = out.nodes.firstWhere((n) => isArticleNodeId(n.id));
      expect(article.concept, '연준 동결');
      expect(out.edges, hasLength(1));
      expect(out.edges.single.from, article.id);
      expect(out.edges.single.to, 'c_기준금리');
      expect(out.edges.single.type, articleEdgeType);
    });

    test('같은 기사에 나온 개념들이 한 노드로 모인다', () {
      final out = withArticleNodes(Graph(nodes: [
        concept('c_기준금리', from: [fedHold]),
        concept('c_실질금리', from: [fedHold]),
      ]));

      expect(out.nodes.where((n) => isArticleNodeId(n.id)), hasLength(1));
      expect(out.edges, hasLength(2)); // 기사 → 개념 둘
    });

    test('여러 기사에 나온 개념은 기사마다 줄을 갖는다 — 크로스기사가 눈에 보인다', () {
      final out = withArticleNodes(Graph(nodes: [
        concept('c_기준금리', from: [fedHold, chips]),
      ]));

      expect(out.nodes.where((n) => isArticleNodeId(n.id)), hasLength(2));
      expect(out.edges.where((e) => e.to == 'c_기준금리'), hasLength(2));
    });

    test('URL 이 같으면 제목이 달라도 한 기사다', () {
      const renamed = SourceArticle(url: 'https://n.example/fed', title: '연준 동결(수정)');
      final out = withArticleNodes(Graph(nodes: [
        concept('c_a', from: [fedHold]),
        concept('c_b', from: [renamed]),
      ]));

      expect(out.nodes.where((n) => isArticleNodeId(n.id)), hasLength(1));
    });

    test('URL 이 없는 구형 항목은 제목으로 묶인다', () {
      const legacy = SourceArticle(url: '', title: '옛 기사');
      final out = withArticleNodes(Graph(nodes: [
        concept('c_a', from: [legacy]),
        concept('c_b', from: [legacy]),
      ]));

      final articles = out.nodes.where((n) => isArticleNodeId(n.id));
      expect(articles, hasLength(1));
      expect(articles.single.concept, '옛 기사');
    });

    test('출처가 없으면 아무것도 만들지 않는다', () {
      final graph = Graph(nodes: [concept('c_고아')]);
      expect(withArticleNodes(graph).nodes, hasLength(1));
      expect(withArticleNodes(graph).edges, isEmpty);
    });

    test('빈 그래프는 그대로다', () {
      expect(withArticleNodes(Graph.empty).nodes, isEmpty);
    });

    test('두 번 적용해도 늘어나지 않는다(멱등)', () {
      final once = withArticleNodes(Graph(nodes: [
        concept('c_기준금리', from: [fedHold]),
      ]));
      final twice = withArticleNodes(once);

      expect(twice.nodes.length, once.nodes.length);
      expect(twice.edges.length, once.edges.length);
    });

    test('기사 노드는 이해상태를 갖지 않는다', () {
      final out = withArticleNodes(Graph(nodes: [
        concept('c_기준금리', from: [fedHold]),
      ]));
      final article = out.nodes.firstWhere((n) => isArticleNodeId(n.id));

      expect(article.state, NodeState.unknown);
      expect(article.isUnderstood, isFalse);
      expect(article.isNotUnderstood, isFalse);
    });
  });

  group('원본 오염 금지', () {
    test('입력 그래프를 건드리지 않는다 — 이게 서버로 올라가는 원본이다', () {
      final original = Graph(
        nodes: [concept('c_기준금리', from: [fedHold])],
        edges: const [GraphEdge(from: 'c_a', to: 'c_기준금리')],
      );

      withArticleNodes(original);

      expect(original.nodes, hasLength(1));
      expect(original.edges, hasLength(1));
      expect(original.nodes.every((n) => !isArticleNodeId(n.id)), isTrue);
    });

    test('기사 노드 id 는 개념 id 와 겹치지 않는다', () {
      final out = withArticleNodes(Graph(nodes: [
        concept('c_기준금리', from: [fedHold]),
      ]));
      final ids = out.nodes.map((n) => n.id).toSet();

      expect(ids, hasLength(out.nodes.length)); // 중복 없음
      expect(isArticleNodeId('c_기준금리'), isFalse);
    });

    test('기사 엣지 타입은 서버 계약(prereq/related)이 아니다', () {
      final out = withArticleNodes(Graph(nodes: [
        concept('c_기준금리', from: [fedHold]),
      ]));

      expect(articleEdgeType, isNot(EdgeType.prereq));
      expect(articleEdgeType, isNot(EdgeType.related));
      expect(out.edges.single.type, articleEdgeType);
    });
  });
}
