import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'providers/providers.dart';
import 'ui/app_colors.dart';
import 'ui/home_page.dart';
import 'ui/login_page.dart';
import 'ui/widgets/window_frame.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(1440, 900),
      // 좌측 생각 지도 + 우측 도킹 패널 2단 구성이라 너무 좁아지면 무너진다.
      minimumSize: Size(1100, 700),
      center: true,
      title: '프로버',
      backgroundColor: AppColors.canvasBg,
      // 네이티브 타이틀바를 숨기고 [WindowFrame]이 대신 그린다.
      titleBarStyle: TitleBarStyle.hidden,
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );

  runApp(const ProviderScope(child: ProberApp()));
}

class ProberApp extends StatelessWidget {
  const ProberApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.pink,
      brightness: Brightness.light,
      surface: AppColors.canvasBg,
      outline: AppColors.textMuted,
      outlineVariant: AppColors.border,
      errorContainer: AppColors.pinkBg,
      onErrorContainer: AppColors.pink,
    );
    return MaterialApp(
      title: '프로버 — 생각 지도',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.canvasBg,
        textTheme: ThemeData.light().textTheme.apply(
              bodyColor: AppColors.textPrimary,
              displayColor: AppColors.textPrimary,
            ),
      ),
      // 모든 화면 위에 커스텀 타이틀바를 얹는다. 화면마다 따로 붙이지 않아도
      // 로그인·홈이 같은 창 프레임을 쓴다.
      builder: (context, child) => WindowFrame(child: child ?? const SizedBox()),
      home: const _AuthGate(),
    );
  }
}

/// 저장된 토큰 유무로 로그인/홈을 가른다(명세 §3.5).
class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);

    return auth.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      // 로그인 실패도 로그인 화면에 머무르며 에러만 보여준다.
      error: (_, _) => const LoginPage(),
      data: (state) => state.signedIn ? const HomePage() : const LoginPage(),
    );
  }
}
