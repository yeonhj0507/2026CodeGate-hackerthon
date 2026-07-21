import '../dto/graph.dart';
import '../dto/recommendation.dart';

/// 서버 미완성 구간을 메우는 시연용 픽스처.
///
/// 각 "웨이브"는 **한 번의 동기화로 반영되는 스크랩 묶음**에 해당한다.
/// 동기화를 반복하면 웨이브가 차례로 얹히며 그래프가 자라고, 이미 있던
/// 개념이 다른 기사에서 재등장하면 노드가 병합된다(명세 §5.1 크로스기사 연결).
abstract final class MockData {
  /// 동기화 n회차에 서버가 "새로 반영했다"고 응답할 노드/엣지.
  static final List<MockWave> waves = [
    MockWave(
      articleTitle: '미 연준, 기준금리 5.5% 동결… "인플레 둔화 확인 필요"',
      nodes: [
        GraphNode(
          id: 'c_기준금리',
          concept: '기준금리',
          state: NodeState.understood,
          isPrereq: false,
          sourceArticles: [
          SourceArticle(
            url: 'https://example.com/prober/fed-hold',
            title: '미 연준, 기준금리 5.5% 동결… "인플레 둔화 확인 필요"',
          ),
        ],
        ),
        GraphNode(
          id: 'c_실질금리',
          concept: '실질금리',
          state: NodeState.notUnderstood,
          isPrereq: false,
          sourceArticles: [
          SourceArticle(
            url: 'https://example.com/prober/fed-hold',
            title: '미 연준, 기준금리 5.5% 동결… "인플레 둔화 확인 필요"',
          ),
        ],
          summaryMeta: '명목금리에서 물가상승률을 뺀 값입니다. 기사에서 "금리를 동결했는데도 '
              '긴축 효과가 커졌다"고 한 이유가 여기에 있습니다 — 명목금리가 그대로여도 '
              '물가가 떨어지면 실질금리는 올라갑니다.',
        ),
        GraphNode(
          id: 'c_물가상승률',
          concept: '물가상승률',
          state: NodeState.notUnderstood,
          isPrereq: true,
          sourceArticles: [
          SourceArticle(
            url: 'https://example.com/prober/fed-hold',
            title: '미 연준, 기준금리 5.5% 동결… "인플레 둔화 확인 필요"',
          ),
        ],
          summaryMeta: '일정 기간 물가가 오른 비율. 실질금리를 계산하려면 반드시 먼저 '
              '이해해야 하는 값입니다.',
        ),
      ],
      edges: [
        GraphEdge(from: 'c_물가상승률', to: 'c_실질금리'),
        GraphEdge(from: 'c_실질금리', to: 'c_기준금리', type: EdgeType.related),
      ],
      recommendations: Recommendations(
        gapConcepts: [
          ConceptRecommendation(
            conceptId: 'c_실질금리',
            conceptTag: '실질금리',
            reason: '진단에서 놓친 개념입니다. 명목금리와의 차이부터 잡아보세요.',
          ),
          ConceptRecommendation(
            conceptId: 'c_물가상승률',
            conceptTag: '물가상승률',
            reason: '‘실질금리’를 이해하려면 먼저 짚어야 하는 선행 개념입니다.',
          ),
        ],
        // 아직 이해완료를 발판 삼을 곳이 없다 — 콜드스타트(명세 §4.4 한계) 시연.
        expansionConcepts: [
        ],
        articles: [
          ArticleRecommendation(
            title: '30초 만에 이해하는 실질금리',
            url: 'https://example.com/prober/real-interest-rate',
            publisher: '한겨레',
            reason: '미이해 개념 ‘실질금리’ 보충',
          ),
          ArticleRecommendation(
            title: '물가는 어떻게 측정할까 — CPI 읽는 법',
            url: 'https://example.com/prober/cpi-explained',
            publisher: '경향신문',
            reason: '선행개념 ‘물가상승률’ 보충',
          ),
        ],
      ),
    ),
    MockWave(
      articleTitle: '반도체 수출 3개월째 증가… 무역수지 흑자 전환',
      nodes: [
        GraphNode(
          id: 'c_무역수지',
          concept: '무역수지',
          state: NodeState.understood,
          isPrereq: false,
          sourceArticles: [
          SourceArticle(
            url: 'https://example.com/prober/chip-exports',
            title: '반도체 수출 3개월째 증가… 무역수지 흑자 전환',
          ),
        ],
        ),
        GraphNode(
          id: 'c_재고순환',
          concept: '재고순환',
          state: NodeState.notUnderstood,
          isPrereq: true,
          sourceArticles: [
          SourceArticle(
            url: 'https://example.com/prober/chip-exports',
            title: '반도체 수출 3개월째 증가… 무역수지 흑자 전환',
          ),
        ],
          summaryMeta: '기업이 쌓아둔 재고가 줄었다 늘었다 하는 주기. 기사에서 "감산 효과가 '
              '이제 나타난다"고 한 대목이 재고순환의 회복 국면을 말합니다.',
        ),
        // 크로스기사 병합: 기존 노드가 다른 기사에서 재등장 → sourceArticles 누적
        GraphNode(
          id: 'c_기준금리',
          concept: '기준금리',
          state: NodeState.understood,
          isPrereq: false,
          sourceArticles: [
          SourceArticle(
            url: 'https://example.com/prober/fed-hold',
            title: '미 연준, 기준금리 5.5% 동결… "인플레 둔화 확인 필요"',
          ),
          SourceArticle(
            url: 'https://example.com/prober/chip-exports',
            title: '반도체 수출 3개월째 증가… 무역수지 흑자 전환',
          ),
        ],
        ),
      ],
      edges: [
        GraphEdge(from: 'c_재고순환', to: 'c_무역수지'),
        GraphEdge(from: 'c_기준금리', to: 'c_무역수지', type: EdgeType.related),
      ],
      recommendations: Recommendations(
        // 재고순환이 확장(형제)으로 올라갔으므로 결핍에서는 빠진다 — 서버와 같은 규칙
        // (같은 개념이 두 섹션에 동시에 뜨지 않는다).
        gapConcepts: [],
        // 형제 신호: 같은 ‘무역수지’로 이어지는 선행 중 기준금리는 이미 이해완료다.
        // 그 옆 갈래인 재고순환을 심화 후보로 권한다.
        expansionConcepts: [
          ExpansionRecommendation(
            conceptId: 'c_재고순환',
            conceptTag: '재고순환',
            reason: ExpansionReason.sibling,
          ),
        ],
        articles: [
          ArticleRecommendation(
            title: '반도체는 왜 4년마다 오르내리나',
            url: 'https://example.com/prober/semiconductor-cycle',
            publisher: '중앙일보',
            reason: '미이해 개념 ‘재고순환’ 보충',
          ),
        ],
      ),
    ),
    MockWave(
      articleTitle: 'EU 탄소국경조정제도 본격 시행… 철강업계 비상',
      nodes: [
        GraphNode(
          id: 'c_탄소배출권',
          concept: '탄소배출권',
          state: NodeState.notUnderstood,
          isPrereq: true,
          sourceArticles: [
          SourceArticle(
            url: 'https://example.com/prober/cbam',
            title: 'EU 탄소국경조정제도 본격 시행… 철강업계 비상',
          ),
        ],
          summaryMeta: '온실가스를 배출할 수 있는 권리를 사고파는 제도. CBAM이 '
              '"수입품에도 같은 값을 매긴다"는 뜻을 이해하려면 이 가격 개념이 먼저입니다.',
        ),
        GraphNode(
          id: 'c_CBAM',
          concept: '탄소국경조정제도(CBAM)',
          state: NodeState.notUnderstood,
          isPrereq: false,
          sourceArticles: [
          SourceArticle(
            url: 'https://example.com/prober/cbam',
            title: 'EU 탄소국경조정제도 본격 시행… 철강업계 비상',
          ),
        ],
          summaryMeta: 'EU로 수입되는 제품에 그 제품이 배출한 탄소만큼 비용을 물리는 제도입니다.',
        ),
        GraphNode(
          id: 'c_무역수지',
          concept: '무역수지',
          state: NodeState.understood,
          isPrereq: false,
          sourceArticles: [
          SourceArticle(
            url: 'https://example.com/prober/chip-exports',
            title: '반도체 수출 3개월째 증가… 무역수지 흑자 전환',
          ),
          SourceArticle(
            url: 'https://example.com/prober/cbam',
            title: 'EU 탄소국경조정제도 본격 시행… 철강업계 비상',
          ),
        ],
        ),
      ],
      edges: [
        GraphEdge(from: 'c_탄소배출권', to: 'c_CBAM'),
        GraphEdge(from: 'c_CBAM', to: 'c_무역수지', type: EdgeType.related),
      ],
      recommendations: Recommendations(
        gapConcepts: [
          ConceptRecommendation(
            conceptId: 'c_탄소배출권',
            conceptTag: '탄소배출권',
            reason: '‘CBAM’을 이해하려면 먼저 짚어야 하는 선행 개념입니다.',
          ),
          ConceptRecommendation(
            conceptId: 'c_CBAM',
            conceptTag: 'CBAM',
            reason: '진단에서 놓친 개념입니다. 수출기업에 실제로 청구되는 비용이 핵심이에요.',
          ),
        ],
        // 이 웨이브에는 이해완료를 발판 삼을 갈래가 없다(둘 다 미이해).
        expansionConcepts: [],
        articles: [
          ArticleRecommendation(
            title: '탄소에 값을 매긴다는 것',
            url: 'https://example.com/prober/carbon-pricing',
            publisher: '한국경제',
            reason: '미이해 개념 ‘탄소배출권’ 보충',
          ),
          ArticleRecommendation(
            title: 'CBAM, 우리 수출에 무엇이 달라지나',
            url: 'https://example.com/prober/cbam-korea',
            publisher: '매일경제',
            reason: '미이해 개념 ‘CBAM’ 보충',
          ),
          // 추천 탭은 "읽을 만한 기사" 5개를 보여주는 게 확정 명세라, 데모의
          // 마지막 웨이브에서 5개가 채워지도록 3건을 더 둔다.
          ArticleRecommendation(
            title: '무역수지 흑자, 이번엔 진짜일까',
            url: 'https://example.com/prober/trade-balance-explainer',
            publisher: '한국경제',
            reason: '이해완료 개념 ‘무역수지’ 복습',
          ),
          ArticleRecommendation(
            title: '재고순환으로 보는 반도체 다음 사이클',
            url: 'https://example.com/prober/inventory-cycle-semis',
            publisher: '조선비즈',
            reason: '확장 개념 ‘재고순환’ 심화',
          ),
          ArticleRecommendation(
            title: '기준금리 동결, 시장은 왜 안도했나',
            url: 'https://example.com/prober/rate-hold-market-reaction',
            publisher: '서울경제',
            reason: '이해완료 개념 ‘기준금리’ 복습',
          ),
        ],
      ),
    ),
  ];

  /// 추천 탭에서 "모를 것 같은 개념"을 눌렀을 때 인라인으로 보여줄 OX 퀴즈.
  /// 그래프 노드 id로 찾는다 — 없는 개념은 화면에서 "준비 중"으로 처리한다.
  static const Map<String, ConceptQuiz> conceptQuizzes = {
    'c_실질금리': ConceptQuiz(
      question: '명목금리가 그대로여도 물가상승률이 떨어지면 실질금리는 오른다.',
      answer: true,
      explanation: '실질금리 = 명목금리 − 물가상승률이라, 물가상승률이 떨어지면 실질금리는 오릅니다.',
    ),
    'c_물가상승률': ConceptQuiz(
      question: '물가상승률이 높을수록 실질금리도 함께 높아진다.',
      answer: false,
      explanation: '물가상승률이 오르면 오히려 실질금리는 낮아집니다(명목금리에서 빼는 값이라서).',
    ),
    'c_탄소배출권': ConceptQuiz(
      question: '탄소배출권은 온실가스를 배출할 수 있는 권리를 사고파는 제도다.',
      answer: true,
      explanation: '맞습니다 — 배출량에 값을 매겨 시장에서 거래하게 한 제도입니다.',
    ),
    'c_CBAM': ConceptQuiz(
      question: 'CBAM은 EU 역내 기업에만 적용되고 수입품에는 적용되지 않는다.',
      answer: false,
      explanation: '반대입니다 — CBAM은 EU로 수입되는 제품에 탄소 비용을 물리는 제도입니다.',
    ),
  };

  /// "탐색" 탭에서 키워드(그래프 노드 id)를 고르고 "더 탐색하기"를 눌렀을 때
  /// 보여줄 설명·추천 기사. 없는 키워드는 화면에서 기본 안내로 대체한다.
  static const Map<String, ExploreContent> exploreContent = {
    'c_기준금리': ExploreContent(
      summary: '기준금리는 중앙은행이 시중 자금 사정을 조절하려 정하는 정책금리입니다. '
          '이 금리가 오르내리면 예금·대출 금리 전반이 따라 움직입니다. '
          '그래서 뉴스에서 "동결" 여부를 늘 주목합니다.',
      articles: [
        ArticleRecommendation(
          title: '기준금리 동결, 시장은 왜 안도했나',
          url: 'https://example.com/prober/rate-hold-market-reaction',
          publisher: '서울경제',
        ),
        ArticleRecommendation(
          title: '30초 만에 이해하는 실질금리',
          url: 'https://example.com/prober/real-interest-rate',
          publisher: '한겨레',
        ),
      ],
    ),
    'c_실질금리': ExploreContent(
      summary: '실질금리는 명목금리에서 물가상승률을 뺀 값입니다. '
          '명목금리가 그대로여도 물가가 떨어지면 체감하는 긴축 강도는 커집니다. '
          '그래서 "금리를 안 올렸는데도 더 조여졌다"는 말이 나옵니다.',
      articles: [
        ArticleRecommendation(
          title: '30초 만에 이해하는 실질금리',
          url: 'https://example.com/prober/real-interest-rate',
          publisher: '한겨레',
        ),
        ArticleRecommendation(
          title: '물가는 어떻게 측정할까 — CPI 읽는 법',
          url: 'https://example.com/prober/cpi-explained',
          publisher: '경향신문',
        ),
      ],
    ),
    'c_물가상승률': ExploreContent(
      summary: '물가상승률은 일정 기간 물가가 오른 비율을 말합니다. '
          '소비자물가지수(CPI) 같은 지표로 측정하며, 실질금리를 구하는 기준값이 됩니다.',
      articles: [
        ArticleRecommendation(
          title: '물가는 어떻게 측정할까 — CPI 읽는 법',
          url: 'https://example.com/prober/cpi-explained',
          publisher: '경향신문',
        ),
        ArticleRecommendation(
          title: '30초 만에 이해하는 실질금리',
          url: 'https://example.com/prober/real-interest-rate',
          publisher: '한겨레',
        ),
      ],
    ),
    'c_무역수지': ExploreContent(
      summary: '무역수지는 수출액에서 수입액을 뺀 값으로, 양수면 흑자입니다. '
          '반도체 같은 주력 수출품의 실적에 크게 좌우됩니다.',
      articles: [
        ArticleRecommendation(
          title: '무역수지 흑자, 이번엔 진짜일까',
          url: 'https://example.com/prober/trade-balance-explainer',
          publisher: '한국경제',
        ),
        ArticleRecommendation(
          title: '반도체는 왜 4년마다 오르내리나',
          url: 'https://example.com/prober/semiconductor-cycle',
          publisher: '중앙일보',
        ),
      ],
    ),
    'c_재고순환': ExploreContent(
      summary: '재고순환은 기업이 쌓아둔 재고가 늘었다 줄었다 하는 주기입니다. '
          '재고가 줄어드는 국면은 보통 생산·수출 회복의 신호로 읽힙니다.',
      articles: [
        ArticleRecommendation(
          title: '반도체는 왜 4년마다 오르내리나',
          url: 'https://example.com/prober/semiconductor-cycle',
          publisher: '중앙일보',
        ),
        ArticleRecommendation(
          title: '재고순환으로 보는 반도체 다음 사이클',
          url: 'https://example.com/prober/inventory-cycle-semis',
          publisher: '조선비즈',
        ),
      ],
    ),
    'c_탄소배출권': ExploreContent(
      summary: '탄소배출권은 온실가스를 배출할 권리를 사고파는 제도입니다. '
          'CBAM이 "수입품에도 같은 값을 매긴다"는 개념을 이해하려면 이 가격 개념이 먼저입니다.',
      articles: [
        ArticleRecommendation(
          title: '탄소에 값을 매긴다는 것',
          url: 'https://example.com/prober/carbon-pricing',
          publisher: '한국경제',
        ),
        ArticleRecommendation(
          title: 'CBAM, 우리 수출에 무엇이 달라지나',
          url: 'https://example.com/prober/cbam-korea',
          publisher: '매일경제',
        ),
      ],
    ),
    'c_CBAM': ExploreContent(
      summary: 'CBAM(탄소국경조정제도)은 EU로 수입되는 제품에 그 제품이 배출한 탄소만큼 '
          '비용을 물리는 제도입니다. 철강처럼 탄소 배출이 많은 업종의 수출 비용이 커집니다.',
      articles: [
        ArticleRecommendation(
          title: 'CBAM, 우리 수출에 무엇이 달라지나',
          url: 'https://example.com/prober/cbam-korea',
          publisher: '매일경제',
        ),
        ArticleRecommendation(
          title: '탄소에 값을 매긴다는 것',
          url: 'https://example.com/prober/carbon-pricing',
          publisher: '한국경제',
        ),
      ],
    ),
  };
}

/// 추천 탭 인라인 개념 상세에 쓰는 OX 퀴즈 하나.
class ConceptQuiz {
  const ConceptQuiz({
    required this.question,
    required this.answer,
    required this.explanation,
  });

  final String question;
  final bool answer;
  final String explanation;
}

/// 탐색 탭에서 키워드 하나를 "더 탐색하기"했을 때 보여줄 결과.
class ExploreContent {
  const ExploreContent({required this.summary, required this.articles});

  final String summary;
  final List<ArticleRecommendation> articles;
}

class MockWave {
  const MockWave({
    required this.articleTitle,
    required this.nodes,
    required this.edges,
    required this.recommendations,
  });

  final String articleTitle;
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
  final Recommendations recommendations;
}

