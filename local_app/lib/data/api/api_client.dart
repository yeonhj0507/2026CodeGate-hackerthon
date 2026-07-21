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
  });

  final Graph graph;
  final Recommendations recommendations;

  factory ThoughtmapUpdateOut.fromJson(Map<String, dynamic> json) {
    return ThoughtmapUpdateOut(
      graph: Graph.fromJson(
          (json['graph'] as Map?)?.cast<String, dynamic>() ?? const {}),
      recommendations: Recommendations.fromJson(
          (json['recommendations'] as Map?)?.cast<String, dynamic>() ??
              const {}),
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
}
