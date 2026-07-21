/// 서버 공통 에러 포맷 `{ "error": { "code": "...", "message": "..." } }`
/// (구현계획② §4)을 앱 내부 예외로 변환한 타입.
class AppException implements Exception {
  const AppException({
    required this.code,
    required this.message,
    this.statusCode,
  });

  final String code;
  final String message;
  final int? statusCode;

  /// 토큰 만료·무효. 이 예외를 만나면 토큰을 폐기하고 로그인 화면으로 되돌린다.
  bool get isUnauthorized => statusCode == 401;

  /// 서버 응답 바디에서 에러를 복원한다. 포맷이 어긋나면 [fallback]을 쓴다.
  factory AppException.fromResponse(
    Object? body,
    int? statusCode, {
    String fallback = '요청을 처리하지 못했습니다.',
  }) {
    if (body is Map) {
      final error = body['error'];
      if (error is Map) {
        return AppException(
          code: error['code']?.toString() ?? 'unknown',
          message: error['message']?.toString() ?? fallback,
          statusCode: statusCode,
        );
      }
    }
    return AppException(
      code: 'unknown',
      message: fallback,
      statusCode: statusCode,
    );
  }

  const AppException.network(this.message)
      : code = 'network_error',
        statusCode = null;

  @override
  String toString() => 'AppException($code, $statusCode): $message';
}
