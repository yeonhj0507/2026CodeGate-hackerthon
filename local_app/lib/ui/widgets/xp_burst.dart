import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_colors.dart';

/// 짧게 터졌다 사라지는 축하 효과. 배점이 크고 드문 이벤트(재도전 성공·기사
/// 잇기)에만 쓴다 — [XpKind.isCelebration] 참고.
///
/// 패키지를 새로 받지 않는다. 점 몇 개를 방사형으로 흩트리는 정도는
/// `AnimationController` 하나로 충분하고, confetti 패키지 하나를 받자고
/// pub 의존성·버전 충돌 리스크를 늘릴 이유가 없다.
class XpBurst extends StatefulWidget {
  const XpBurst({super.key, required this.trigger});

  /// 값이 바뀔 때마다 애니메이션을 처음부터 다시 재생한다.
  /// 같은 값이 두 번 와도 재생되지 않으므로, 매 축하 이벤트마다 다른
  /// 값(예: 증가하는 카운터)을 넘겨야 한다.
  final Object trigger;

  @override
  State<XpBurst> createState() => _XpBurstState();
}

class _XpBurstState extends State<XpBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 750),
  );

  static const _dotColors = [
    AppColors.pink,
    AppColors.pinkStrong,
    Color(0xFFFFC65A), // 앰버 — 팔레트에 없는 축하용 포인트 색. 배지 밖으로
    Color(0xFF6FCF97), // 민트 — 위와 같은 이유. 둘 다 이 위젯 안에서만 쓴다.
  ];

  @override
  void didUpdateWidget(covariant XpBurst old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          if (t == 0 || t == 1) return const SizedBox.shrink();
          return Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [for (var i = 0; i < 8; i++) _dot(i, t)],
          );
        },
      ),
    );
  }

  Widget _dot(int i, double t) {
    final angle = (i / 8) * 2 * math.pi;
    final eased = Curves.easeOutCubic.transform(t);
    final distance = 22 * eased;
    final offset =
        Offset(math.cos(angle), math.sin(angle)) * distance;

    return Transform.translate(
      offset: offset,
      child: Opacity(
        opacity: (1 - t).clamp(0.0, 1.0),
        child: Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            color: _dotColors[i % _dotColors.length],
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
