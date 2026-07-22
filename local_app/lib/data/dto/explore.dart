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
  const ExploreResult({
    this.explanation = '',
    this.articles = const [],
    this.searchFailed = false,
  });

  /// 고른 개념들을 **묶어서** 설명한 2~3문장. 개별 정의의 나열이 아니다.
  final String explanation;

  final List<ArticleRecommendation> articles;

  /// 웹 뉴스 검색이 실패했는지. 제휴 기사는 그대로 실리되, 참이면 기사 영역에
  /// "뉴스 검색에 실패했어요"를 알린다.
  final bool searchFailed;

  static const empty = ExploreResult();

  // 검색 실패는 "보여줄 게 있는" 상태로 친다 — 실패 안내를 띄워야 하므로
  // 빈 상태로 빠지지 않게 한다.
  bool get isEmpty => explanation.isEmpty && articles.isEmpty && !searchFailed;

  factory ExploreResult.fromJson(Map<String, dynamic> json) => ExploreResult(
        explanation: json['explanation'] as String? ?? '',
        articles: (json['articles'] as List<dynamic>? ?? const [])
            .map((e) => ArticleRecommendation.fromJson(e as Map<String, dynamic>))
            .toList(),
        searchFailed: json['searchFailed'] as bool? ?? false,
      );
}
