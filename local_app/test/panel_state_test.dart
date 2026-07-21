import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prober_local/providers/providers.dart';

/// 우측 패널·탐색 상태의 **기본값**을 못 박는다.
///
/// 기본값은 화면을 처음 열었을 때 무엇이 보이는가를 정하는 제품 결정이라,
/// 리팩터링 중에 슬쩍 바뀌면 아무도 눈치채지 못한 채 첫인상이 달라진다.
void main() {
  ProviderContainer container() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  test('우측 패널은 접힌 채로 시작한다', () {
    // 처음엔 생각 지도를 넓게 보여주고, 아이콘을 눌러야 패널이 열린다.
    expect(container().read(rightPanelModeProvider), RightPanelMode.closed);
  });

  test('탐색 키워드는 비어 있고, 담은 순서를 지키는 List 다', () {
    final c = container();
    expect(c.read(exploreKeywordProvider), isEmpty);

    c.read(exploreKeywordProvider.notifier).state = ['b', 'a'];
    expect(c.read(exploreKeywordProvider), ['b', 'a'],
        reason: '사용자가 담은 순서가 곧 표시 순서다 — 정렬하거나 Set 으로 만들지 않는다');
  });

  test('탐색 결과는 접힌 채로 시작한다', () {
    // 키워드만 담아서는 결과가 뜨지 않는다. 항상 버튼을 눌러야 한다.
    expect(container().read(exploreRevealedProvider), isFalse);
  });

  test('추천 인라인 상세는 닫힌 채로 시작한다', () {
    expect(container().read(inlineConceptDetailProvider), isNull);
  });

  test('지도 선택과 탐색 키워드는 서로를 건드리지 않는다', () {
    final c = container();

    c.read(selectedNodeIdProvider.notifier).state = 'n1';
    expect(c.read(exploreKeywordProvider), isEmpty,
        reason: '지도를 둘러보다 키워드가 저절로 쌓이면 안 된다');

    c.read(exploreKeywordProvider.notifier).state = ['n2'];
    expect(c.read(selectedNodeIdProvider), 'n1',
        reason: '키워드를 담았다고 지도 선택이 옮겨가면 안 된다');
  });
}
