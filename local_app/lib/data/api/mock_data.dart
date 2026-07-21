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
          sourceArticles: ['미 연준, 기준금리 5.5% 동결… "인플레 둔화 확인 필요"'],
        ),
        GraphNode(
          id: 'c_실질금리',
          concept: '실질금리',
          state: NodeState.notUnderstood,
          isPrereq: false,
          sourceArticles: ['미 연준, 기준금리 5.5% 동결… "인플레 둔화 확인 필요"'],
          summaryMeta: '명목금리에서 물가상승률을 뺀 값입니다. 기사에서 "금리를 동결했는데도 '
              '긴축 효과가 커졌다"고 한 이유가 여기에 있습니다 — 명목금리가 그대로여도 '
              '물가가 떨어지면 실질금리는 올라갑니다.',
        ),
        GraphNode(
          id: 'c_물가상승률',
          concept: '물가상승률',
          state: NodeState.notUnderstood,
          isPrereq: true,
          sourceArticles: ['미 연준, 기준금리 5.5% 동결… "인플레 둔화 확인 필요"'],
          summaryMeta: '일정 기간 물가가 오른 비율. 실질금리를 계산하려면 반드시 먼저 '
              '이해해야 하는 값입니다.',
        ),
      ],
      edges: [
        GraphEdge(from: 'c_물가상승률', to: 'c_실질금리'),
        GraphEdge(from: 'c_실질금리', to: 'c_기준금리', type: EdgeType.related),
      ],
      recommendations: Recommendations(
        concepts: [
          ConceptRecommendation(
            concept: '명목금리',
            reason: '‘실질금리’ 오답의 짝 개념입니다. 둘의 차이를 알면 기사 문장이 풀립니다.',
            relatedNodeId: 'c_실질금리',
          ),
          ConceptRecommendation(
            concept: '소비자물가지수(CPI)',
            reason: '‘물가상승률’을 실제로 어떻게 재는지에 해당합니다.',
            relatedNodeId: 'c_물가상승률',
          ),
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
          sourceArticles: ['반도체 수출 3개월째 증가… 무역수지 흑자 전환'],
        ),
        GraphNode(
          id: 'c_재고순환',
          concept: '재고순환',
          state: NodeState.notUnderstood,
          isPrereq: true,
          sourceArticles: ['반도체 수출 3개월째 증가… 무역수지 흑자 전환'],
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
            '미 연준, 기준금리 5.5% 동결… "인플레 둔화 확인 필요"',
            '반도체 수출 3개월째 증가… 무역수지 흑자 전환',
          ],
        ),
      ],
      edges: [
        GraphEdge(from: 'c_재고순환', to: 'c_무역수지'),
        GraphEdge(from: 'c_기준금리', to: 'c_무역수지', type: EdgeType.related),
      ],
      recommendations: Recommendations(
        concepts: [
          ConceptRecommendation(
            concept: '반도체 사이클',
            reason: '‘재고순환’을 반도체 산업에 적용한 개념입니다.',
            relatedNodeId: 'c_재고순환',
          ),
          ConceptRecommendation(
            concept: '경상수지',
            reason: '‘무역수지’를 포함하는 더 넓은 지표입니다.',
            relatedNodeId: 'c_무역수지',
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
          sourceArticles: ['EU 탄소국경조정제도 본격 시행… 철강업계 비상'],
          summaryMeta: '온실가스를 배출할 수 있는 권리를 사고파는 제도. CBAM이 '
              '"수입품에도 같은 값을 매긴다"는 뜻을 이해하려면 이 가격 개념이 먼저입니다.',
        ),
        GraphNode(
          id: 'c_CBAM',
          concept: '탄소국경조정제도(CBAM)',
          state: NodeState.notUnderstood,
          isPrereq: false,
          sourceArticles: ['EU 탄소국경조정제도 본격 시행… 철강업계 비상'],
          summaryMeta: 'EU로 수입되는 제품에 그 제품이 배출한 탄소만큼 비용을 물리는 제도입니다.',
        ),
        GraphNode(
          id: 'c_무역수지',
          concept: '무역수지',
          state: NodeState.understood,
          isPrereq: false,
          sourceArticles: [
            '반도체 수출 3개월째 증가… 무역수지 흑자 전환',
            'EU 탄소국경조정제도 본격 시행… 철강업계 비상',
          ],
        ),
      ],
      edges: [
        GraphEdge(from: 'c_탄소배출권', to: 'c_CBAM'),
        GraphEdge(from: 'c_CBAM', to: 'c_무역수지', type: EdgeType.related),
      ],
      recommendations: Recommendations(
        concepts: [
          ConceptRecommendation(
            concept: '배출권거래제(ETS)',
            reason: '‘탄소배출권’이 실제로 거래되는 시장 제도입니다.',
            relatedNodeId: 'c_탄소배출권',
          ),
        ],
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

