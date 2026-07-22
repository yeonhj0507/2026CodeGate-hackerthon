import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prober_local/data/db/database.dart';
import 'package:prober_local/providers/providers.dart';
import 'package:prober_local/ui/onboarding_view.dart';

/// 빈 지도 온보딩에서도 "내 이력 가져오기"로 바로 동기화할 수 있어야 한다
/// (재설치 등으로 로컬만 비고 서버엔 이력이 남은 경우).
void main() {
  // 동기화는 syncControllerProvider → 실 DB 까지 물린다. 매번 인메모리로 띄운다.
  List<Override> dbOverride() {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    return [databaseProvider.overrideWithValue(db)];
  }

  testWidgets('동기화 버튼과 보조 익스텐션 버튼이 있다', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: dbOverride(),
      child: const MaterialApp(home: Scaffold(body: OnboardingView())),
    ));

    expect(find.text('내 이력 가져오기'), findsOneWidget);
    expect(find.text('크롬 익스텐션 설치'), findsOneWidget);
  });

  testWidgets('버튼을 누르면 동기화가 돌아 lastSyncedAt 이 채워진다', (tester) async {
    final container = ProviderContainer(overrides: dbOverride());
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: OnboardingView())),
    ));

    expect(container.read(syncControllerProvider).lastSyncedAt, isNull);

    await tester.tap(find.text('내 이력 가져오기'));
    await tester.pumpAndSettle();

    // 목 클라이언트로 동기화가 끝나면 시각이 찍힌다.
    expect(container.read(syncControllerProvider).lastSyncedAt, isNotNull);
  });
}
