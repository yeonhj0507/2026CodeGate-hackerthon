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

  /// 그래프 갱신은 서버측 LLM 호출을 포함하므로 여유를 크게 둔다.
  ///
  /// **여기서 끊기면 단순히 실패로 끝나지 않는다.** 서버는 응답을 다 만든 뒤
  /// 스크랩 버퍼를 지우고 커밋하므로(`thoughtmap/service.py` 5단계), 클라이언트가
  /// 먼저 포기하면 진단 결과가 서버에서도 로컬에서도 사라진다. 실제로 60초일 때
  /// 기사 검색이 59초를 먹으면서 그 일이 벌어졌다.
  ///
  /// 서버에서 재요약과 추천을 동시에 돌리도록 고쳤지만(둘 중 느린 쪽이 곧 응답
  /// 시간), 검색 한 번이 60초에 육박할 때가 있어 상한을 넉넉히 잡는다.
  static const Duration receiveTimeout = Duration(seconds: 180);
}
