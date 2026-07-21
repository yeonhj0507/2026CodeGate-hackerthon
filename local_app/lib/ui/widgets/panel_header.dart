import 'package:flutter/material.dart';

import '../app_colors.dart';

/// 도킹 패널 공용 타이틀 — 제목과 닫기(X) 버튼을 한 줄에 나란히 정렬한다.
class PanelHeader extends StatelessWidget {
  const PanelHeader({super.key, required this.title, required this.onClose});

  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        IconButton(
          tooltip: '패널 닫기',
          icon: const Icon(Icons.close, size: 18, color: AppColors.textMuted),
          onPressed: onClose,
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}
