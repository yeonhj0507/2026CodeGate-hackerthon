import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prober_local/ui/widgets/xp_burst.dart';

void main() {
  Future<void> pump(WidgetTester tester, Object trigger) {
    return tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: XpBurst(trigger: trigger))),
    ));
  }

  testWidgets('trigger가 그대로면 재생되지 않는다', (tester) async {
    await pump(tester, 0);
    await tester.pump(const Duration(milliseconds: 100));

    // rebuild해도 트리거 값이 안 바뀌면 didUpdateWidget이 무시한다.
    await pump(tester, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('trigger가 바뀌면 애니메이션이 재생되다 스스로 사라진다', (tester) async {
    await pump(tester, 1);

    await pump(tester, 2); // trigger 변경 → forward(from: 0)
    await tester.pump(); // 애니메이션 시작 프레임(t=0, 아직 안 보임)
    await tester.pump(const Duration(milliseconds: 300)); // 진행 중

    await tester.pump(const Duration(milliseconds: 500)); // 750ms 넘겨 종료
    expect(tester.takeException(), isNull);
  });

  testWidgets('여러 번 연달아 트리거해도 예외 없이 처리한다', (tester) async {
    await pump(tester, 1);
    for (var i = 2; i <= 5; i++) {
      await pump(tester, i);
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 750));
    expect(tester.takeException(), isNull);
  });
}
