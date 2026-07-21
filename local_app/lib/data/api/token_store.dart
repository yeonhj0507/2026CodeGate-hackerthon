import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// accessToken 보관소. 명세 §3.5에 따라 `flutter_secure_storage`를 쓴다.
///
/// 익스텐션과 토큰을 공유하지 않는다 — 각자 독립 로그인, 동일 계정(명세 §4.1).
class TokenStore {
  TokenStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              mOptions: MacOsOptions(usesDataProtectionKeychain: false),
            );

  final FlutterSecureStorage _storage;

  static const _keyToken = 'prober.accessToken';
  static const _keyUserId = 'prober.userId';

  /// dio 인터셉터가 매 요청마다 읽지 않도록 메모리에 캐시한다.
  String? _cached;

  Future<String?> read() async {
    return _cached ??= await _storage.read(key: _keyToken);
  }

  Future<void> save(String token, String userId) async {
    _cached = token;
    await _storage.write(key: _keyToken, value: token);
    await _storage.write(key: _keyUserId, value: userId);
  }

  Future<String?> readUserId() => _storage.read(key: _keyUserId);

  /// 로그아웃 및 401 응답 시 호출.
  Future<void> clear() async {
    _cached = null;
    await _storage.delete(key: _keyToken);
    await _storage.delete(key: _keyUserId);
  }
}
