import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../app_colors.dart';

/// "prober" 로고 락업(아이콘 + 워드마크). Figma 전 화면에서 재사용된다.
class LogoLockup extends StatelessWidget {
  const LogoLockup({super.key, this.iconSize = 33, this.textSize = 22});

  final double iconSize;
  final double textSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SvgPicture.asset(
          'assets/branding/logo_mark.svg',
          height: iconSize,
          width: iconSize * (50.9226 / 33),
        ),
        const SizedBox(width: 10),
        Text(
          'prober',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: textSize,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
