/// 앱 전역 설정.
///
/// 서버(FastAPI)가 아직 준비되지 않은 동안에는 [useMock]이 true로 동작해
/// [MockApiClient]가 주입된다. 실서버 연동 시:
///   flutter run -d windows --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=http://localhost:8000
class AppConfig {
  const AppConfig._();

  /// Mock API 사용 여부. 기본 true (서버 미완성).
  static const bool useMock =
      bool.fromEnvironment('USE_MOCK', defaultValue: true);

  /// 실서버 베이스 URL.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  /// 이 클라이언트 식별자. 로그인 시 서버로 전송(구현계획② §3.2, 감사용).
  static const String clientName = 'local';

  static const Duration connectTimeout = Duration(seconds: 10);

  /// 그래프 갱신은 서버측 LLM 호출을 포함하므로 여유를 둔다.
  static const Duration receiveTimeout = Duration(seconds: 60);
}
