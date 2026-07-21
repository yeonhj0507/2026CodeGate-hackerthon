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
            sourceArticles: [
              SourceArticle(url: 'https://news.example.com/a', title: '기사 A'),
              SourceArticle(url: 'https://news.example.com/b', title: '기사 B'),
            ],
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
      expect(node.sourceArticles.map((a) => a.title), ['기사 A', '기사 B']);
      expect(node.sourceArticles.first.url, 'https://news.example.com/a');
      expect(node.summaryMeta, '명목금리에서 물가상승률을 뺀 값');
      expect(node.promoted, isTrue);

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
      expect(restored.nodes.single.promoted, isTrue);
      expect(restored.edges, isEmpty);
    });

    test('구형 로컬 데이터(제목 문자열)도 흡수한다', () {
      // 예전 기기에 저장된 sourceArticles 는 문자열 배열이다. 서버 계약은
      // 객체만 허용하지만, 이미 저장된 데이터를 버릴 이유는 없다.
      final restored = Graph.fromJson({
        'nodes': [
          {'id': 'z', 'sourceArticles': ['옛 기사 제목']},
        ],
      });

      final article = restored.nodes.single.sourceArticles.single;
      expect(article.title, '옛 기사 제목');
      expect(article.url, isEmpty);
      expect(article.hasUrl, isFalse);
      expect(article.label, '옛 기사 제목');
    });

    test('구형(URL 없음)과 신형(URL 있음)이 같은 기사면 한 건으로 접힌다', () {
      // 앱 업데이트 직후 기기에서 실제로 두 줄로 보이던 문제(실행 중 발견).
      final merged = SourceArticle.mergeAll(const [
        SourceArticle(url: '', title: '반도체 수출 3개월째 증가'),
        SourceArticle(url: 'https://n.example/chip', title: '반도체 수출 3개월째 증가'),
      ]);

      expect(merged, hasLength(1));
      // URL 이 있는 쪽으로 승격돼야 링크를 열 수 있다.
      expect(merged.single.url, 'https://n.example/chip');
    });

    test('URL 이 다르면 다른 기사로 남는다(크로스기사 누적)', () {
      final merged = SourceArticle.mergeAll(const [
        SourceArticle(url: 'https://n.example/a', title: '기사 A'),
        SourceArticle(url: 'https://n.example/b', title: '기사 B'),
        SourceArticle(url: 'https://n.example/a', title: '기사 A'),
      ]);

      expect(merged.map((a) => a.title), ['기사 A', '기사 B']);
    });
  });

  group('OxQuiz', () {
    test('노드에 실려 라운드트립된다', () {
      const original = Graph(nodes: [
        GraphNode(
          id: 'c_기준금리',
          concept: '기준금리',
          state: NodeState.notUnderstood,
          isPrereq: false,
          oxQuiz: OxQuiz(
            statement: '금리 인하는 곧바로 임금을 올려 물가를 자극한다',
            answer: false,
            sourceQuestion: '금리를 내리면 물가가 오를 수 있는 이유는?',
          ),
        ),
      ]);

      final node = Graph.fromJson(original.toJson()).nodes.single;
      expect(node.oxQuiz, isNotNull);
      expect(node.oxQuiz!.answer, isFalse);
      expect(node.oxQuiz!.statement, contains('임금'));
      expect(node.oxQuiz!.sourceQuestion, isNotNull);
    });

    test('재료가 없으면 null 이고 파싱은 살아남는다(구버전 서버 호환)', () {
      final restored = Graph.fromJson({
        'nodes': [
          {'id': 'x', 'concept': 'X'},
        ],
      });
      expect(restored.nodes.single.oxQuiz, isNull);
    });
  });

  test('ArticleRecommendation 은 출처(제휴/검색)를 보존한다', () {
    final restored = ArticleRecommendation.fromJson({
      'title': '기준금리 읽기',
      'url': 'https://n.example/a',
      'source': 'search',
    });
    expect(restored.isFromSearch, isTrue);

    // 서버가 source 를 안 보내던 시절 데이터는 제휴로 본다.
    final legacy = ArticleRecommendation.fromJson({'title': 't', 'url': 'u'});
    expect(legacy.source, 'partner');
    expect(legacy.isFromSearch, isFalse);
  });

  test('Recommendations 라운드트립 — 결핍/확장/기사 세 갈래', () {
    const original = Recommendations(
      gapConcepts: [
        ConceptRecommendation(
          conceptId: 'c_실질금리',
          conceptTag: '실질금리',
          reason: '진단에서 놓친 개념',
        ),
      ],
      expansionConcepts: [
        ExpansionRecommendation(
          conceptId: 'c_수입물가',
          conceptTag: '수입물가',
          viaConcepts: ['환율'],
          articleTitle: '환율과 물가',
          articleUrl: 'https://partner.example.com/fx/1',
        ),
      ],
      retryConcepts: [
        RetryRecommendation(
          conceptId: 'c_기준금리',
          conceptTag: '기준금리',
          reason: RetryReason.retry,
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

    expect(restored.gapConcepts.single.conceptId, 'c_실질금리');
    expect(restored.gapConcepts.single.conceptTag, '실질금리');
    // 확장은 아직 그래프에 없는 새 개념이고, 무엇을 발판으로 왔는지를 싣는다.
    expect(restored.expansionConcepts.single.conceptTag, '수입물가');
    expect(restored.expansionConcepts.single.viaConcepts, ['환율']);
    expect(restored.expansionConcepts.single.articleUrl,
        'https://partner.example.com/fx/1');
    expect(restored.expansionConcepts.single.hasArticle, isTrue);
    // 다시 도전은 그래프 안의 노드다.
    expect(restored.retryConcepts.single.conceptTag, '기준금리');
    expect(restored.retryConcepts.single.reason, RetryReason.retry);
    expect(restored.articles.single.url, 'https://example.com/a');
    expect(restored.articles.single.publisher, '한겨레');
  });

  test('서버가 모르는 재도전 신호가 와도 파싱은 살아남는다', () {
    final restored = Recommendations.fromJson({
      'retryConcepts': [
        {'conceptId': 'c_x', 'conceptTag': 'X', 'reason': 'brand_new_signal'},
      ],
    });

    expect(restored.retryConcepts.single.reason, RetryReason.unknown);
    expect(restored.retryConcepts.single.reason.label, isNotEmpty);
  });

  test('확장에 근거 개념이 없어도 안내 문구는 나온다(구버전 서버 호환)', () {
    final restored = Recommendations.fromJson({
      'expansionConcepts': [
        {'conceptId': 'c_x', 'conceptTag': 'X'},
      ],
    });

    expect(restored.expansionConcepts.single.viaConcepts, isEmpty);
    expect(restored.expansionConcepts.single.label, isNotEmpty);
    expect(restored.expansionConcepts.single.hasArticle, isFalse);
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
