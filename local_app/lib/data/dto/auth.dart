/// 인증 스키마. 계약 출처: `구현계획_2_서버_계정인증.md` §4
library;

class TokenOut {
  const TokenOut({
    required this.accessToken,
    required this.userId,
    this.expiresIn,
  });

  final String accessToken;
  final String userId;

  /// 초 단위 만료. 데모 스코프에선 refresh 토큰을 쓰지 않는다(구현계획② §3.3).
  final int? expiresIn;

  factory TokenOut.fromJson(Map<String, dynamic> json) {
    return TokenOut(
      accessToken: json['accessToken'] as String,
      userId: json['userId'] as String? ?? '',
      expiresIn: json['expiresIn'] as int?,
    );
  }
}

class MeOut {
  const MeOut({required this.userId, required this.email, this.displayName});

  final String userId;
  final String email;
  final String? displayName;

  factory MeOut.fromJson(Map<String, dynamic> json) {
    return MeOut(
      userId: json['userId'] as String? ?? '',
      email: json['email'] as String? ?? '',
      displayName: json['displayName'] as String?,
    );
  }
}
