import 'package:dio/dio.dart';

import '../../core/app_exception.dart';
import '../../core/config.dart';
import '../dto/auth.dart';
import '../dto/graph.dart';
import '../dto/user_context.dart';
import 'api_client.dart';
import 'token_store.dart';

/// 실서버(FastAPI) 연동 구현.
///
/// - 모든 요청에 `Authorization: Bearer` 자동 첨부
/// - 서버 에러 포맷 `{error:{code,message}}`를 [AppException]으로 변환
/// - 401이면 토큰을 폐기한다. 화면 전환은 상위(authProvider)가 처리.
class DioApiClient implements ApiClient {
  DioApiClient({required TokenStore tokenStore, Dio? dio})
      : _tokenStore = tokenStore,
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: AppConfig.apiBaseUrl,
              connectTimeout: AppConfig.connectTimeout,
              receiveTimeout: AppConfig.receiveTimeout,
              contentType: Headers.jsonContentType,
              // 에러 바디를 직접 읽어 AppException으로 바꾸기 위해
              // dio가 상태코드로 던지지 않게 한다.
              validateStatus: (_) => true,
            )) {
    _dio.interceptors.add(
      InterceptorsWrapper(onRequest: (options, handler) async {
        final token = await _tokenStore.read();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      }),
    );
  }

  final Dio _dio;
  final TokenStore _tokenStore;

  /// 상태코드를 검사해 2xx면 바디를, 아니면 [AppException]을 던진다.
  Future<Map<String, dynamic>> _unwrap(Future<Response<dynamic>> call) async {
    final Response<dynamic> res;
    try {
      res = await call;
    } on DioException catch (e) {
      throw AppException.network(
          '서버에 연결하지 못했습니다. (${e.type.name}) 서버 주소: ${AppConfig.apiBaseUrl}');
    }

    final status = res.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      if (status == 401) {
        await _tokenStore.clear();
      }
      throw AppException.fromResponse(res.data, status);
    }
    if (res.data is Map) {
      return (res.data as Map).cast<String, dynamic>();
    }
    return const {};
  }

  @override
  Future<String> signup(String email, String password) async {
    final body = await _unwrap(_dio.post('/auth/signup', data: {
      'email': email,
      'password': password,
    }));
    return body['userId'] as String? ?? '';
  }

  @override
  Future<TokenOut> login(String email, String password) async {
    final body = await _unwrap(_dio.post('/auth/login', data: {
      'email': email,
      'password': password,
      'client': AppConfig.clientName, // 서버 감사용(구현계획② §3.2)
    }));
    return TokenOut.fromJson(body);
  }

  @override
  Future<MeOut> me() async {
    return MeOut.fromJson(await _unwrap(_dio.get('/auth/me')));
  }

  @override
  Future<ThoughtmapUpdateOut> updateThoughtmap(
    Graph graph,
    UserContext ctx,
  ) async {
    final body = await _unwrap(_dio.post('/thoughtmap/update', data: {
      'graph': graph.toJson(),
      'userContext': ctx.toJson(),
    }));
    return ThoughtmapUpdateOut.fromJson(body);
  }
}
