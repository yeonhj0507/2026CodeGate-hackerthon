import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/providers.dart';
import 'ui/app_colors.dart';
import 'ui/home_page.dart';
import 'ui/login_page.dart';

void main() {
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
