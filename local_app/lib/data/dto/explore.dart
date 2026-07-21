/// 탐색 탭 — 키워드 2~3개를 묶어 더 파고들기 (`POST /explore`).
///
/// 서버는 그래프를 보관하지 않으므로(명세 §4.5) 노드 id 만으로는 개념명을 모른다.
/// 그래서 id 와 이름을 함께 보낸다.
library;

import 'recommendation.dart';

class ExploreRequest {
  const ExploreRequest({required this.conceptIds, required this.conceptTags});

  final List<String> conceptIds;
  final List<String> conceptTags;

  Map<String, dynamic> toJson() => {
        'conceptIds': conceptIds,
        'conceptTags': conceptTags,
      };
}

class ExploreResult {
  const ExploreResult({this.explanation = '', this.articles = const []});

  /// 고른 개념들을 **묶어서** 설명한 2~3문장. 개별 정의의 나열이 아니다.
  final String explanation;

  final List<ArticleRecommendation> articles;

  static const empty = ExploreResult();

  bool get isEmpty => explanation.isEmpty && articles.isEmpty;

  factory ExploreResult.fromJson(Map<String, dynamic> json) => ExploreResult(
        explanation: json['explanation'] as String? ?? '',
        articles: (json['articles'] as List<dynamic>? ?? const [])
            .map((e) => ArticleRecommendation.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
