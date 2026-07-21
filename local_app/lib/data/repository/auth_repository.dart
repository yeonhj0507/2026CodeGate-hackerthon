import '../api/api_client.dart';
import '../api/token_store.dart';
import '../dto/auth.dart';

/// 인증 흐름(명세 §3.5 / 구현계획② §4).
///
/// 로컬 앱은 익스텐션과 **토큰을 공유하지 않고 독립 로그인**한다. 동일 계정이면
/// 서버가 `sub`(userId)로 같은 사용자로 묶는다(명세 §4.1).
class AuthRepository {
  AuthRepository({required ApiClient api, required TokenStore tokenStore})
      : _api = api,
        _tokenStore = tokenStore;

  final ApiClient _api;
  final TokenStore _tokenStore;

  Future<bool> hasSession() async => (await _tokenStore.read()) != null;

  Future<void> signup(String email, String password) async {
    await _api.signup(email, password);
  }

  Future<TokenOut> login(String email, String password) async {
    final token = await _api.login(email, password);
    await _tokenStore.save(token.accessToken, token.userId);
    return token;
  }

  Future<MeOut> me() => _api.me();

  Future<void> logout() => _tokenStore.clear();
}
