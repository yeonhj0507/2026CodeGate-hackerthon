import 'package:flutter/material.dart';

/// Figma 라이트 테마 팔레트(파일 hFf59XvZspVROmCoEVE783). 화면 전반에서
/// 반복 사용되는 색이라 한 곳에 모은다 — 값이 바뀌면 여기만 고치면 된다.
abstract final class AppColors {
  static const canvasBg = Colors.white;
  static const panelBg = Color(0xFFFBFAF9);
  static const border = Color(0xFFECE7E0);
  static const textPrimary = Color(0xFF1F1E1D);
  static const textMuted = Color(0xFF8A8175);

  static const pink = Color(0xFFE63B5C);
  static const pinkStrong = Color(0xFFFF4D6D);
  static const pinkBg = Color(0xFFFFE3E9);
  static const pinkBgSoft = Color(0xFFFFE8EE);
  static const pinkBgFaint = Color(0xFFFFFBFC);
  static const pinkMuted = Color(0xFFC2808F);
  static const gray = Color(0xFF9CA0A8);

  /// 추천 개념(unknown) 노드의 채움색 — 알약 자체가 회색으로 읽히게 한다.
  /// 이해완료(흰색)·미이해(분홍)와 한눈에 구분되는 옅은 회색.
  static const grayBg = Color(0xFFE6E7EA);

  static const chipSelectedBg = Color(0xFF1F1E1D);
}
