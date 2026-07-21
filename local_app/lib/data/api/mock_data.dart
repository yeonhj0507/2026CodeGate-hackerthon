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
        retryConcepts: [
          RetryRecommendation(
            conceptId: 'c_재고순환',
            conceptTag: '재고순환',
            reason: RetryReason.sibling,
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
        ],
      ),
    ),
    // 웨이브 1에서 추천했던 보충 기사를 실제로 읽고 온 회차.
    // **미이해가 이해로 뒤집히는 유일한 웨이브**라, 경험치 규칙(`xp_rules.dart`)의
    // 이해 전환·재도전 성공을 시연하려면 여기까지 동기화해야 한다.
    MockWave(
      articleTitle: '물가는 어떻게 측정할까 — CPI 읽는 법',
      nodes: [
        GraphNode(
          id: 'c_명목금리',
          concept: '명목금리',
          state: NodeState.understood,
          isPrereq: true,
          sourceArticles: [
            SourceArticle(
              url: 'https://example.com/prober/cpi-explained',
              title: '물가는 어떻게 측정할까 — CPI 읽는 법',
            ),
          ],
          summaryMeta: '물가를 감안하지 않은, 겉으로 보이는 이자율입니다.',
        ),
        // 선행이 먼저 풀린다.
        GraphNode(
          id: 'c_물가상승률',
          concept: '물가상승률',
          state: NodeState.understood,
          isPrereq: true,
          sourceArticles: [
            SourceArticle(
              url: 'https://example.com/prober/fed-hold',
              title: '미 연준, 기준금리 5.5% 동결… "인플레 둔화 확인 필요"',
            ),
            SourceArticle(
              url: 'https://example.com/prober/cpi-explained',
              title: '물가는 어떻게 측정할까 — CPI 읽는 법',
            ),
          ],
          summaryMeta: 'CPI로 측정합니다. 장바구니 품목의 가격을 기준 시점과 견줘 계산해요.',
        ),
        // 그 위에서 원래 막혔던 개념이 뚫린다 → 재도전 성공.
        GraphNode(
          id: 'c_실질금리',
          concept: '실질금리',
          state: NodeState.understood,
          isPrereq: false,
          sourceArticles: [
            SourceArticle(
              url: 'https://example.com/prober/fed-hold',
              title: '미 연준, 기준금리 5.5% 동결… "인플레 둔화 확인 필요"',
            ),
            SourceArticle(
              url: 'https://example.com/prober/cpi-explained',
              title: '물가는 어떻게 측정할까 — CPI 읽는 법',
            ),
          ],
          summaryMeta: '명목금리 − 물가상승률. 두 선행을 모두 잡고 나서야 "금리를 동결했는데 '
              '긴축 효과가 커졌다"가 읽힙니다.',
        ),
      ],
      edges: [
        GraphEdge(from: 'c_명목금리', to: 'c_실질금리'),
      ],
      recommendations: Recommendations(
        gapConcepts: [
          ConceptRecommendation(
            conceptId: 'c_탄소배출권',
            conceptTag: '탄소배출권',
            reason: '‘CBAM’을 이해하려면 먼저 짚어야 하는 선행 개념입니다.',
          ),
        ],
        expansionConcepts: [],
        articles: [
          ArticleRecommendation(
            title: '금리가 오르면 왜 주가가 흔들리나',
            url: 'https://example.com/prober/rates-and-stocks',
            publisher: '한국경제',
            reason: '‘실질금리’를 잡았으니 다음 갈래로',
          ),
        ],
      ),
    ),
  ];
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

