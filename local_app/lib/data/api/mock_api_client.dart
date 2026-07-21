import 'dart:math';

import '../../core/app_exception.dart';
import '../dto/auth.dart';
import '../dto/explore.dart';
import '../dto/graph.dart';
import '../dto/recommendation.dart';
import '../dto/user_context.dart';
import 'api_client.dart';
import 'mock_data.dart';

/// 서버가 준비되기 전까지 쓰는 대역(代役).
///
/// 실서버의 `/thoughtmap/update` 계약을 그대로 흉내낸다:
/// 로컬이 보낸 graph에 버퍼링된 스크랩(여기서는 [MockData.waves])을 병합해
/// **갱신된 graph 전체**와 추천을 돌려준다. 소비한 웨이브는 다시 내보내지
/// 않는다 — 서버가 반영 후 TempScrap을 삭제하는 것과 같은 동작(명세 §4.3).
class MockApiClient implements ApiClient {
  MockApiClient({Random? random}) : _random = random ?? Random();

  final Random _random;

  /// 다음에 반영할 웨이브 인덱스. 서버 버퍼의 미소비 스크랩에 대응한다.
  int _nextWave = 0;

  String? _email;

  Future<void> _delay() async {
    await Future<void>.delayed(
      Duration(milliseconds: 300 + _random.nextInt(500)),
    );
  }

  @override
  Future<String> signup(String email, String password) async {
    await _delay();
    if (!email.contains('@')) {
      throw const AppException(
        code: 'invalid_email',
        message: '이메일 형식이 올바르지 않습니다.',
        statusCode: 400,
      );
    }
    if (password.length < 8) {
      throw const AppException(
        code: 'weak_password',
        message: '비밀번호는 8자 이상이어야 합니다.',
        statusCode: 400,
      );
    }
    _email = email;
    return 'mock-user-1';
  }

  @override
  Future<TokenOut> login(String email, String password) async {
    await _delay();
    if (password.length < 8) {
      throw const AppException(
        code: 'invalid_credentials',
        message: '이메일 또는 비밀번호가 올바르지 않습니다. (Mock: 8자 이상이면 통과)',
        statusCode: 401,
      );
    }
    _email = email;
    return const TokenOut(
      accessToken: 'mock-access-token',
      userId: 'mock-user-1',
      expiresIn: 86400,
    );
  }

  @override
  Future<MeOut> me() async {
    await _delay();
    return MeOut(
      userId: 'mock-user-1',
      email: _email ?? 'demo@prober.dev',
      displayName: 'Mock 사용자',
    );
  }

  @override
  Future<ThoughtmapUpdateOut> updateThoughtmap(
    Graph graph,
    UserContext ctx,
  ) async {
    await _delay();

    if (_nextWave >= MockData.waves.length) {
      // 서버 버퍼가 비어 있는 경우: 그래프는 그대로, 추천만 재계산해 돌려준다.
      return ThoughtmapUpdateOut(
        graph: graph,
        recommendations: _fallbackRecommendations(graph),
      );
    }

    final wave = MockData.waves[_nextWave++];

    // 서버측 병합과 동일한 규칙:
    //   같은 id의 노드는 갱신(크로스기사 sourceArticles 누적), 없으면 추가.
    final nodes = <String, GraphNode>{
      for (final n in graph.nodes) n.id: n,
    };
    for (final incoming in wave.nodes) {
      final existing = nodes[incoming.id];
      nodes[incoming.id] = existing == null
          ? incoming
          : existing.copyWith(
              state: incoming.state,
              sourceArticles: SourceArticle.mergeAll(
                [...existing.sourceArticles, ...incoming.sourceArticles],
              ),
              summaryMeta: incoming.summaryMeta ?? existing.summaryMeta,
            );
    }

    String edgeKey(GraphEdge e) => '${e.from}->${e.to}:${e.type}';
    final edges = <String, GraphEdge>{
      for (final e in graph.edges) edgeKey(e): e,
      for (final e in wave.edges) edgeKey(e): e,
    };

    return ThoughtmapUpdateOut(
      graph: Graph(
        nodes: nodes.values.toList(),
        edges: edges.values.toList(),
      ),
      recommendations: wave.recommendations,
    );
  }

  /// 반영할 새 스크랩이 없을 때: 남아 있는 그래프만으로 추천을 만든다.
  ///
  /// 서버 `recommend.py` 와 같은 규칙 — 미이해는 결핍(gap)으로, 선행이 이해완료인데
  /// 상위가 미이해로 남은 경우는 확장(retry)으로 뽑는다.
  Recommendations _fallbackRecommendations(Graph graph) {
    final unresolved = graph.nodes.where((n) => n.isNotUnderstood).toList();
    if (unresolved.isEmpty) return Recommendations.empty;

    // 재도전 신호: 선행(from)이 이해완료인데 후행(to)이 미이해로 남은 경우.
    final retryIds = <String>{
      for (final e in graph.edges)
        if (graph.nodeById(e.from)?.isUnderstood == true &&
            graph.nodeById(e.to)?.isNotUnderstood == true)
          e.to,
    };

    return Recommendations(
      gapConcepts: unresolved
          .where((n) => !retryIds.contains(n.id))
          .take(3)
          .map((n) => ConceptRecommendation(
                conceptId: n.id,
                conceptTag: n.concept,
                reason: '아직 ‘미이해’로 남아 있는 개념입니다.',
              ))
          .toList(),
      retryConcepts: retryIds
          .map(graph.nodeById)
          .whereType<GraphNode>()
          .map((n) => RetryRecommendation(
                conceptId: n.id,
                conceptTag: n.concept,
                reason: RetryReason.retry,
              ))
          .toList(),
      articles: const [],
    );
  }

  @override
  Future<ExploreResult> explore(ExploreRequest req) async {
    await _delay();
    final tags = req.conceptTags;
    if (tags.isEmpty) return ExploreResult.empty;

    // 서버 mock 과 같은 모양 — 개별 정의가 아니라 "묶음" 설명임을 보여준다.
    final joined = tags.length > 1
        ? '${tags.take(tags.length - 1).join(', ')}과(와) ${tags.last}'
        : tags.first;
    return ExploreResult(
      explanation: '$joined은(는) 한 갈래로 이어지는 개념들입니다. '
          '${tags.first}에서 조건이 바뀌면 무엇이 따라 움직이는지를 보면 '
          '${tags.last}까지 자연스럽게 연결됩니다.',
      articles: [
        for (final t in tags.take(2))
          ArticleRecommendation(
            title: '$t 쉽게 읽기',
            url: 'https://example.com/prober/${Uri.encodeComponent(t)}',
            publisher: '검색결과',
            reason: '탐색: $t',
          ),
      ],
    );
  }
}
