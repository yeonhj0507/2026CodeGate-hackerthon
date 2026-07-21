import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../app_colors.dart';

/// 네이티브 타이틀바를 숨긴 자리를 대신 채우는 커스텀 창 프레임.
///
/// Windows 기본 타이틀바는 OS 테마색(흰 회색)을 쓰기 때문에 앱 캔버스와
/// 경계가 생긴다. 타이틀바를 없애고 여기서 직접 그리면 배경색이 창 맨 위까지
/// 그대로 이어진다. 대신 OS가 주던 것들(드래그 이동, 더블클릭 최대화,
/// 최소화·최대화·닫기)을 우리가 도로 제공해야 한다 — 그게 이 위젯의 일이다.
///
/// [MaterialApp.builder]에 물려서 로그인·홈 어느 화면이든 똑같이 적용된다.
class WindowFrame extends StatelessWidget {
  const WindowFrame({super.key, required this.child});

  final Widget child;

  /// 타이틀바 높이. Windows 기본(약 32px)보다 살짝 높여 버튼 여백을 준다.
  static const double barHeight = 38;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _TitleBar(),
        Expanded(child: child),
      ],
    );
  }
}

class _TitleBar extends StatelessWidget {
  const _TitleBar();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: WindowFrame.barHeight,
      child: ColoredBox(
        color: AppColors.canvasBg,
        child: Row(
          children: [
            // 빈 공간 전체가 창 이동 손잡이다. 더블클릭 최대화도 여기서 받는다.
            const Expanded(child: _DragArea()),
            const _WindowButtons(),
          ],
        ),
      ),
    );
  }
}

class _DragArea extends StatelessWidget {
  const _DragArea();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => windowManager.startDragging(),
      onDoubleTap: () async {
        // OS 타이틀바의 "더블클릭으로 최대화/복원"을 그대로 흉내낸다.
        if (await windowManager.isMaximized()) {
          await windowManager.unmaximize();
        } else {
          await windowManager.maximize();
        }
      },
      child: const SizedBox.expand(),
    );
  }
}

/// 최소화 · 최대화/복원 · 닫기. Windows 관례대로 우측 상단에 이 순서로 둔다.
class _WindowButtons extends StatefulWidget {
  const _WindowButtons();

  @override
  State<_WindowButtons> createState() => _WindowButtonsState();
}

class _WindowButtonsState extends State<_WindowButtons> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _syncMaximized();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  // 창 버튼 말고 OS 스냅(Win+↑, 화면 위로 끌기)으로 상태가 바뀔 수도 있어서
  // 아이콘을 리스너로 맞춰준다.
  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  Future<void> _syncMaximized() async {
    final v = await windowManager.isMaximized();
    if (mounted) setState(() => _maximized = v);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _WindowButton(
          label: '최소화',
          icon: Icons.remove,
          onPressed: windowManager.minimize,
        ),
        _WindowButton(
          label: _maximized ? '이전 크기로 복원' : '최대화',
          icon: _maximized ? Icons.filter_none : Icons.crop_square,
          // filter_none은 겹친 사각형이라 살짝 커 보인다. 시각 크기를 맞춘다.
          iconSize: _maximized ? 12 : 14,
          onPressed: () =>
              _maximized ? windowManager.unmaximize() : windowManager.maximize(),
        ),
        _WindowButton(
          label: '닫기',
          icon: Icons.close,
          // 닫기만 위험한 동작이라 호버 시 빨갛게 — Windows·디스코드 공통 관례.
          hoverColor: AppColors.pink,
          hoverIconColor: Colors.white,
          onPressed: windowManager.close,
        ),
      ],
    );
  }
}

class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.iconSize = 14,
    this.hoverColor = AppColors.border,
    this.hoverIconColor = AppColors.textPrimary,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final double iconSize;
  final Color hoverColor;
  final Color hoverIconColor;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    // Tooltip은 쓸 수 없다 — 이 위젯은 MaterialApp.builder에 얹혀 Navigator보다
    // 위에 있어서 Overlay 조상이 없다. 접근성 이름만 Semantics로 남긴다.
    return Semantics(
      label: widget.label,
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            width: 46,
            height: WindowFrame.barHeight,
            color: _hovered ? widget.hoverColor : Colors.transparent,
            alignment: Alignment.center,
            child: Icon(
              widget.icon,
              size: widget.iconSize,
              color: _hovered ? widget.hoverIconColor : AppColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
