/// 서버가 그래프와 함께 돌려주는 추천(명세 §4.4 산출 / §5.3 열람).
///
/// 세 갈래다: 결핍 보완(gapConcepts) · 심화(expansionConcepts) · 기사(articles).
library;

/// "모를 것 같은 개념" 추천 — 결핍 보완.
class ConceptRecommendation {
  const ConceptRecommendation({
    required this.conceptId,
    required this.conceptTag,
    this.reason,
  });

  /// 그래프 노드 id. 그래프에서 위치를 짚어줄 때 쓴다.
  final String conceptId;

  final String conceptTag;

  /// 왜 이 개념을 권하는지(자연어). 예: "'기준금리'를 이해하려면 먼저 짚어야 하는 선행 개념이다."
  final String? reason;

  factory ConceptRecommendation.fromJson(Map<String, dynamic> json) {
    return ConceptRecommendation(
      conceptId: json['conceptId'] as String? ?? '',
      conceptTag: json['conceptTag'] as String,
      reason: json['reason'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'conceptId': conceptId,
        'conceptTag': conceptTag,
        'reason': reason,
      };
}

/// 확장 개념 추천을 유발한 신호(명세 §4.4).
///
/// 서버는 신호 종류만 내려주고, 사용자에게 보일 문구는 로컬앱이 만든다.
enum ExpansionReason {
  /// 선행을 이해했으니 원래 막혔던 주장에 다시 도전할 때.
  retry,

  /// 같은 상위 개념을 공유하는 옆 갈래.
  sibling,

  /// 서버가 새 신호를 추가했는데 앱이 아직 모르는 경우.
  unknown;

  static ExpansionReason parse(String? raw) => switch (raw) {
        'retry' => ExpansionReason.retry,
        'sibling' => ExpansionReason.sibling,
        _ => ExpansionReason.unknown,
      };

  /// 추천 카드에 붙일 한 줄 설명.
  String get label => switch (this) {
        ExpansionReason.retry => '선행 개념을 익혔어요. 이제 다시 도전해 볼까요?',
        ExpansionReason.sibling => '같은 갈래의 옆 개념이에요.',
        ExpansionReason.unknown => '이어서 넓혀갈 개념이에요.',
      };
}

/// "확장 개념" 추천 — 이해완료를 발판 삼은 심화.
class ExpansionRecommendation {
  const ExpansionRecommendation({
    required this.conceptId,
    required this.conceptTag,
    this.reason = ExpansionReason.unknown,
  });

  final String conceptId;
  final String conceptTag;
  final ExpansionReason reason;

  factory ExpansionRecommendation.fromJson(Map<String, dynamic> json) {
    return ExpansionRecommendation(
      conceptId: json['conceptId'] as String? ?? '',
      conceptTag: json['conceptTag'] as String,
      reason: ExpansionReason.parse(json['reason'] as String?),
    );
  }

  Map<String, dynamic> toJson() => {
        'conceptId': conceptId,
        'conceptTag': conceptTag,
        'reason': reason.name,
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
    this.gapConcepts = const [],
    this.expansionConcepts = const [],
    this.articles = const [],
  });

  /// 모를 것 같은 개념(결핍 보완).
  final List<ConceptRecommendation> gapConcepts;

  /// 확장 개념(심화). 콜드스타트에는 비어 있는 게 정상이다(명세 §4.4 한계).
  final List<ExpansionRecommendation> expansionConcepts;

  final List<ArticleRecommendation> articles;

  static const empty = Recommendations();

  bool get isEmpty =>
      gapConcepts.isEmpty && expansionConcepts.isEmpty && articles.isEmpty;

  factory Recommendations.fromJson(Map<String, dynamic> json) {
    return Recommendations(
      gapConcepts: (json['gapConcepts'] as List<dynamic>? ?? const [])
          .map((e) => ConceptRecommendation.fromJson(e as Map<String, dynamic>))
          .toList(),
      expansionConcepts:
          (json['expansionConcepts'] as List<dynamic>? ?? const [])
              .map((e) =>
                  ExpansionRecommendation.fromJson(e as Map<String, dynamic>))
              .toList(),
      articles: (json['articles'] as List<dynamic>? ?? const [])
          .map((e) => ArticleRecommendation.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'gapConcepts': gapConcepts.map((e) => e.toJson()).toList(),
        'expansionConcepts': expansionConcepts.map((e) => e.toJson()).toList(),
        'articles': articles.map((e) => e.toJson()).toList(),
      };
}
