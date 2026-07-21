import '../dto/auth.dart';
import '../dto/explore.dart';
import '../dto/graph.dart';
import '../dto/recommendation.dart';
import '../dto/user_context.dart';

/// `POST /thoughtmap/update` 응답: `{ graph, recommendations }`
/// (구현계획③ §4)
class ThoughtmapUpdateOut {
  const ThoughtmapUpdateOut({
    required this.graph,
    required this.recommendations,
    this.consumedScrapIds = const [],
  });

  final Graph graph;
  final Recommendations recommendations;

  /// 이 응답에 반영된 서버 버퍼 스크랩의 id.
  ///
  /// **아직 서버에 남아 있다.** 로컬 반영을 마친 뒤 [ApiClient.ackScraps] 로
  /// 돌려줘야 지워진다. 이 왕복이 없으면, 응답을 받지 못한 클라이언트가 있을 때
  /// 서버는 이미 지운 뒤라 진단 결과가 양쪽에서 사라진다.
  final List<String> consumedScrapIds;

  factory ThoughtmapUpdateOut.fromJson(Map<String, dynamic> json) {
    return ThoughtmapUpdateOut(
      graph: Graph.fromJson(
          (json['graph'] as Map?)?.cast<String, dynamic>() ?? const {}),
      recommendations: Recommendations.fromJson(
          (json['recommendations'] as Map?)?.cast<String, dynamic>() ??
              const {}),
      consumedScrapIds: (json['consumedScrapIds'] as List<dynamic>? ?? const [])
          .map((e) => e as String)
          .toList(),
    );
  }
}

/// 서버와의 유일한 접점. 로컬 앱이 쓰는 엔드포인트는 `/auth/*`와
/// `/thoughtmap/update` 뿐이다 — 퀴즈·채점에는 관여하지 않는다(명세 §5.4).
///
/// 서버 미완성 구간에는 [MockApiClient]가, 완성 후에는 [DioApiClient]가
/// 주입된다. 전환은 `AppConfig.useMock` 하나로 결정된다.
abstract class ApiClient {
  Future<String> signup(String email, String password);

  Future<TokenOut> login(String email, String password);

  Future<MeOut> me();

  Future<ThoughtmapUpdateOut> updateThoughtmap(Graph graph, UserContext ctx);

  /// 탐색 탭 — 고른 키워드를 묶어 설명 + 관련 기사 2건.
  Future<ExploreResult> explore(ExploreRequest req);

  /// 로컬 반영을 마쳤으니 서버 버퍼에서 지워도 된다고 알린다.
  ///
  /// 실패해도 사용자는 잃는 게 없다 — 다음 동기화가 같은 스크랩을 다시 반영하고
  /// (병합은 두 번 먹어도 결과가 같다) 그때 다시 지울 기회가 온다.
  Future<void> ackScraps(List<String> scrapIds);
}
