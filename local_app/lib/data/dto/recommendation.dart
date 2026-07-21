/// 서버가 그래프와 함께 돌려주는 추천(명세 §4.4 산출 / §5.3 열람).
library;

/// "모를 것 같은 개념" 추천.
class ConceptRecommendation {
  const ConceptRecommendation({
    required this.concept,
    this.reason,
    this.relatedNodeId,
  });

  final String concept;

  /// 왜 이 개념을 권하는지(예: "‘기준금리’ 오답의 선행 개념").
  final String? reason;

  /// 이 추천을 유발한 그래프 노드. 그래프에서 위치를 짚어줄 때 쓴다.
  final String? relatedNodeId;

  factory ConceptRecommendation.fromJson(Map<String, dynamic> json) {
    return ConceptRecommendation(
      concept: json['concept'] as String,
      reason: json['reason'] as String?,
      relatedNodeId: json['relatedNodeId'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'concept': concept,
        'reason': reason,
        'relatedNodeId': relatedNodeId,
      };
}

/// "읽을 만한 기사" 추천. 소스는 신문사 제휴 자체 데이터셋(명세 §4.4 확정).
class ArticleRecommendation {
  const ArticleRecommendation({
    required this.title,
    required this.url,
    this.publisher,
    this.reason,
  });

  final String title;
  final String url;
  final String? publisher;
  final String? reason;

  factory ArticleRecommendation.fromJson(Map<String, dynamic> json) {
    return ArticleRecommendation(
      title: json['title'] as String,
      url: json['url'] as String? ?? '',
      publisher: json['publisher'] as String?,
      reason: json['reason'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'url': url,
        'publisher': publisher,
        'reason': reason,
      };
}

class Recommendations {
  const Recommendations({
    this.concepts = const [],
    this.articles = const [],
  });

  final List<ConceptRecommendation> concepts;
  final List<ArticleRecommendation> articles;

  static const empty = Recommendations();

  bool get isEmpty => concepts.isEmpty && articles.isEmpty;

  factory Recommendations.fromJson(Map<String, dynamic> json) {
    return Recommendations(
      concepts: (json['concepts'] as List<dynamic>? ?? const [])
          .map((e) => ConceptRecommendation.fromJson(e as Map<String, dynamic>))
          .toList(),
      articles: (json['articles'] as List<dynamic>? ?? const [])
          .map((e) => ArticleRecommendation.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'concepts': concepts.map((e) => e.toJson()).toList(),
        'articles': articles.map((e) => e.toJson()).toList(),
      };
}
