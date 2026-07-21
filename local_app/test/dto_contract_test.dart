import 'package:flutter_test/flutter_test.dart';
import 'package:prober_local/data/dto/graph.dart';
import 'package:prober_local/data/dto/recommendation.dart';
import 'package:prober_local/data/dto/user_context.dart';

/// DTO는 서버와의 계약 문서를 겸한다. 필드가 실수로 빠지거나 이름이 바뀌면
/// 여기서 먼저 깨져야 한다.
void main() {
  group('Graph JSON 라운드트립', () {
    test('노드·엣지의 모든 필드가 보존된다', () {
      const original = Graph(
        nodes: [
          GraphNode(
            id: 'c_실질금리',
            concept: '실질금리',
            state: NodeState.notUnderstood,
            isPrereq: true,
            sourceArticles: ['기사 A', '기사 B'],
            summaryMeta: '명목금리에서 물가상승률을 뺀 값',
          ),
        ],
        edges: [
          GraphEdge(from: 'c_물가상승률', to: 'c_실질금리'),
        ],
      );

      final restored = Graph.fromJson(original.toJson());

      final node = restored.nodes.single;
      expect(node.id, 'c_실질금리');
      expect(node.concept, '실질금리');
      expect(node.state, NodeState.notUnderstood);
      expect(node.isPrereq, isTrue);
      expect(node.sourceArticles, ['기사 A', '기사 B']);
      expect(node.summaryMeta, '명목금리에서 물가상승률을 뺀 값');

      expect(restored.edges.single.from, 'c_물가상승률');
      expect(restored.edges.single.to, 'c_실질금리');
      expect(restored.edges.single.type, EdgeType.prereq);
    });

    test('서버가 모르는 state 값을 보내와도 그대로 보존한다', () {
      final restored = Graph.fromJson({
        'nodes': [
          {'id': 'x', 'concept': 'X', 'state': 'partially_understood'},
        ],
        'edges': <dynamic>[],
      });

      expect(restored.nodes.single.state, 'partially_understood');
      expect(restored.nodes.single.isUnderstood, isFalse);
      expect(restored.nodes.single.isNotUnderstood, isFalse);
    });

    test('필수 필드만 온 응답도 파싱된다', () {
      final restored = Graph.fromJson({
        'nodes': [
          {'id': 'y'},
        ],
      });

      expect(restored.nodes.single.concept, 'y');
      expect(restored.nodes.single.state, NodeState.unknown);
      expect(restored.nodes.single.sourceArticles, isEmpty);
      expect(restored.edges, isEmpty);
    });
  });

  test('Recommendations 라운드트립', () {
    const original = Recommendations(
      concepts: [
        ConceptRecommendation(
          concept: '명목금리',
          reason: '실질금리의 짝 개념',
          relatedNodeId: 'c_실질금리',
        ),
      ],
      articles: [
        ArticleRecommendation(
          title: '30초 만에 이해하는 실질금리',
          url: 'https://example.com/a',
          publisher: '한겨레',
        ),
      ],
    );

    final restored = Recommendations.fromJson(original.toJson());

    expect(restored.concepts.single.concept, '명목금리');
    expect(restored.concepts.single.relatedNodeId, 'c_실질금리');
    expect(restored.articles.single.url, 'https://example.com/a');
    expect(restored.articles.single.publisher, '한겨레');
  });

  test('UserContext는 서버가 기대하는 키로 직렬화된다', () {
    final ctx = UserContext(
      learningHistory: [
        LearningHistoryItem(
          conceptTag: '실질금리',
          parentConcept: '기준금리',
          level: 1,
          correct: false,
          articleTitle: '기사 A',
          occurredAt: DateTime.utc(2026, 7, 21, 3, 30),
        ),
      ],
      articlePreferences: const [
        ArticlePreferenceItem(keyword: '경제', weight: 2.5, category: '분야'),
      ],
    );

    final json = ctx.toJson();

    expect(json.keys, containsAll(['learningHistory', 'articlePreferences']));
    final history = (json['learningHistory'] as List).single as Map;
    expect(history['conceptTag'], '실질금리');
    expect(history['parentConcept'], '기준금리');
    expect(history['level'], 1);
    expect(history['correct'], isFalse);
    expect(history['occurredAt'], '2026-07-21T03:30:00.000Z');

    final pref = (json['articlePreferences'] as List).single as Map;
    expect(pref['keyword'], '경제');
    expect(pref['weight'], 2.5);
  });
}
