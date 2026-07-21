/// 로컬이 서버로 보내는 사용자 컨텍스트(명세 §4.4 입력 ③).
///
/// 서버는 이 데이터를 **보관하지 않고** 그래프 갱신·추천 랭킹에만 참조한다
/// (명세 §4.5). 원본은 항상 로컬 SQLite에 있다.
library;

/// 개념별 진단 이력 한 건. 익스텐션 스크랩이 서버를 경유해 반영된 결과의
/// 로컬 사본이며, 재동기화 시 사용자 컨텍스트로 서버에 되돌려 보낸다.
class LearningHistoryItem {
  const LearningHistoryItem({
    required this.conceptTag,
    required this.correct,
    required this.occurredAt,
    this.parentConcept,
    this.level = 0,
    this.articleTitle,
  });

  final String conceptTag;

  /// null이면 main 문항(구현계획① §3.5).
  final String? parentConcept;

  /// 0 = main, 1~2 = 선행개념 재질문 단계.
  final int level;

  final bool correct;
  final String? articleTitle;
  final DateTime occurredAt;

  factory LearningHistoryItem.fromJson(Map<String, dynamic> json) {
    return LearningHistoryItem(
      conceptTag: json['conceptTag'] as String,
      parentConcept: json['parentConcept'] as String?,
      level: json['level'] as int? ?? 0,
      correct: json['correct'] as bool? ?? false,
      articleTitle: json['articleTitle'] as String?,
      occurredAt:
          DateTime.tryParse(json['occurredAt'] as String? ?? '')?.toUtc() ??
              DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toJson() => {
        'conceptTag': conceptTag,
        'parentConcept': parentConcept,
        'level': level,
        'correct': correct,
        'articleTitle': articleTitle,
        'occurredAt': occurredAt.toUtc().toIso8601String(),
      };
}

/// 기사 선호 패턴 한 건. 어떤 주제/키워드의 기사를 얼마나 읽었는지.
/// 서버의 "읽을 만한 기사 추천" 랭킹 입력(명세 §4.4).
class ArticlePreferenceItem {
  const ArticlePreferenceItem({
    required this.keyword,
    required this.weight,
    this.category,
  });

  final String keyword;
  final String? category;

  /// 노출/열람 횟수 기반 가중치.
  final double weight;

  factory ArticlePreferenceItem.fromJson(Map<String, dynamic> json) {
    return ArticlePreferenceItem(
      keyword: json['keyword'] as String,
      category: json['category'] as String?,
      weight: (json['weight'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'keyword': keyword,
        'category': category,
        'weight': weight,
      };
}

class UserContext {
  const UserContext({
    this.learningHistory = const [],
    this.articlePreferences = const [],
  });

  final List<LearningHistoryItem> learningHistory;
  final List<ArticlePreferenceItem> articlePreferences;

  Map<String, dynamic> toJson() => {
        'learningHistory': learningHistory.map((e) => e.toJson()).toList(),
        'articlePreferences':
            articlePreferences.map((e) => e.toJson()).toList(),
      };
}
