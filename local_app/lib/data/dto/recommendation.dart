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
enum RetryReason {
  /// 선행을 이해했으니 원래 막혔던 주장에 다시 도전할 때.
  retry,

  /// 같은 상위 개념을 공유하는 옆 갈래.
  sibling,

  /// 서버가 새 신호를 추가했는데 앱이 아직 모르는 경우.
  unknown;

  static RetryReason parse(String? raw) => switch (raw) {
        'retry' => RetryReason.retry,
        'sibling' => RetryReason.sibling,
        _ => RetryReason.unknown,
      };

  /// 추천 카드에 붙일 한 줄 설명.
  String get label => switch (this) {
        RetryReason.retry => '선행 개념을 익혔어요. 이제 다시 도전해 볼까요?',
        RetryReason.sibling => '같은 갈래의 옆 개념이에요.',
        RetryReason.unknown => '한 번 더 짚어볼 개념이에요.',
      };
}

/// "다시 도전할 개념" — 이미 그래프에 있고 틀렸던 것.
///
/// 확장 개념([ExpansionRecommendation])과 다르다. 이쪽은 **내 그래프 안의 노드**라
/// 눌러서 그래프 위치를 짚을 수 있다.
class RetryRecommendation {
  const RetryRecommendation({
    required this.conceptId,
    required this.conceptTag,
    this.reason = RetryReason.unknown,
  });

  final String conceptId;
  final String conceptTag;
  final RetryReason reason;

  factory RetryRecommendation.fromJson(Map<String, dynamic> json) {
    return RetryRecommendation(
      conceptId: json['conceptId'] as String? ?? '',
      conceptTag: json['conceptTag'] as String,
      reason: RetryReason.parse(json['reason'] as String?),
    );
  }

  Map<String, dynamic> toJson() => {
        'conceptId': conceptId,
        'conceptTag': conceptTag,
        'reason': reason.name,
      };
}

/// "확장 개념" 추천 — 아는 개념에서 뻗어나가는 **새 키워드**.
///
/// 아직 그래프에 없는 개념이라 눌러도 짚을 노드가 없다. 그래서 카드에는 위치 대신
/// [viaConcepts] — 무엇을 발판으로 데려왔는지 — 를 보여준다.
class ExpansionRecommendation {
  const ExpansionRecommendation({
    required this.conceptId,
    required this.conceptTag,
    this.viaConcepts = const [],
  });

  final String conceptId;
  final String conceptTag;

  /// 이 개념을 데려온 근거 — 같은 기사에서 함께 다뤄진 내 개념들.
  final List<String> viaConcepts;

  /// 카드에 붙일 한 줄 설명. 근거가 있으면 그것으로 말한다.
  String get label => viaConcepts.isEmpty
      ? '이어서 넓혀갈 개념이에요.'
      : "'${viaConcepts.first}' 와 같은 기사에서 함께 다뤄져요.";

  factory ExpansionRecommendation.fromJson(Map<String, dynamic> json) {
    return ExpansionRecommendation(
      conceptId: json['conceptId'] as String? ?? '',
      conceptTag: json['conceptTag'] as String,
      viaConcepts: (json['viaConcepts'] as List<dynamic>? ?? const [])
          .map((e) => e as String)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'conceptId': conceptId,
        'conceptTag': conceptTag,
        'viaConcepts': viaConcepts,
      };
}

/// "읽을 만한 기사" 추천. 소스는 신문사 제휴 자체 데이터셋(명세 §4.4 확정).
class ArticleRecommendation {
  const ArticleRecommendation({
    required this.title,
    required this.url,
    this.publisher,
    this.reason,
    this.source = 'partner',
  });

  final String title;
  final String url;
  final String? publisher;
  final String? reason;

  /// 'partner' = 신문사 제휴 데이터셋(명세 §4.4 확정 소스),
  /// 'search'  = 제휴에서 못 채운 자리를 웹 검색으로 메운 것.
  final String source;

  bool get isFromSearch => source == 'search';

  factory ArticleRecommendation.fromJson(Map<String, dynamic> json) {
    return ArticleRecommendation(
      title: json['title'] as String,
      url: json['url'] as String? ?? '',
      publisher: json['publisher'] as String?,
      reason: json['reason'] as String?,
      source: json['source'] as String? ?? 'partner',
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'url': url,
        'publisher': publisher,
        'reason': reason,
        'source': source,
      };
}

class Recommendations {
  const Recommendations({
    this.gapConcepts = const [],
    this.expansionConcepts = const [],
    this.retryConcepts = const [],
    this.articles = const [],
  });

  /// 모를 것 같은 개념(결핍 보완).
  final List<ConceptRecommendation> gapConcepts;

  /// 확장 개념 — 아는 것에서 뻗어나가는 새 키워드. 제휴 데이터셋이 내 주제를
  /// 못 덮으면 비어 있는 게 정상이다.
  final List<ExpansionRecommendation> expansionConcepts;

  /// 다시 도전할 개념. 오답 이력이 없는 초반에는 비어 있다(명세 §4.4 한계).
  final List<RetryRecommendation> retryConcepts;

  final List<ArticleRecommendation> articles;

  static const empty = Recommendations();

  bool get isEmpty =>
      gapConcepts.isEmpty &&
      expansionConcepts.isEmpty &&
      retryConcepts.isEmpty &&
      articles.isEmpty;

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
      retryConcepts: (json['retryConcepts'] as List<dynamic>? ?? const [])
          .map((e) => RetryRecommendation.fromJson(e as Map<String, dynamic>))
          .toList(),
      articles: (json['articles'] as List<dynamic>? ?? const [])
          .map((e) => ArticleRecommendation.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'gapConcepts': gapConcepts.map((e) => e.toJson()).toList(),
        'expansionConcepts': expansionConcepts.map((e) => e.toJson()).toList(),
        'retryConcepts': retryConcepts.map((e) => e.toJson()).toList(),
        'articles': articles.map((e) => e.toJson()).toList(),
      };
}
