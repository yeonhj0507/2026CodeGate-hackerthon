import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/xp/xp_rules.dart';
import '../providers/providers.dart';
import 'app_colors.dart';
import 'widgets/panel_header.dart';
import 'widgets/xp_burst.dart';

/// 상단바에 붙는 XP 배지. 누르면 상세가 열린다.
///
/// **XP가 쌓이는 모든 경로가 여기 하나로 모인다.** 동기화·OX 퀴즈 정답·접속
/// 스트릭 전부 결국 [xpProvider]를 갱신하고 끝나므로(providers.dart 참고),
/// 효과도 호출부마다 넣지 않고 이 배지 하나에만 건다 — 어디서 XP가 들어와도
/// 숫자가 카운트업되고, 재도전 성공·기사 잇기처럼 큰 사건이면 반짝인다.
///
/// 색을 상단바 배경에 기대지 않고 [AppColors.pinkBg] 위에 얹은 이유:
/// 홈 상단바는 아직 구(舊) 다크 색이 남아 있고 라이트 팔레트 이관이 진행 중이라,
/// 어느 쪽 배경에서도 읽히는 자립형 칩으로 둔다.
class XpBadge extends ConsumerStatefulWidget {
  const XpBadge({super.key});

  @override
  ConsumerState<XpBadge> createState() => _XpBadgeState();
}

class _XpBadgeState extends ConsumerState<XpBadge> {
  /// count-up 애니메이션의 출발점. [XpSnapshot.total]이 늘어도 바로 따라잡지
  /// 않고, `TweenAnimationBuilder`가 이 값에서 새 값까지 눈에 보이게 센 뒤에만
  /// 갱신한다(`onEnd`).
  int _lastTotal = 0;

  /// 값이 바뀔 때마다 [XpBurst]를 새로 재생시키는 트리거.
  int _burstTrigger = 0;

  @override
  void initState() {
    super.initState();
    _lastTotal = ref.read(xpProvider).total;
  }

  @override
  Widget build(BuildContext context) {
    final xp = ref.watch(xpProvider);

    // 총량이 바뀔 때만 반응한다 — recent 목록 갱신 등 다른 필드 변화로
    // 불필요하게 재생되지 않게.
    ref.listen<XpSnapshot>(
      xpProvider,
      (prev, next) {
        if (next.total == prev?.total) return;
        // XpController는 XpSnapshot.empty로 시작해 refresh()가 끝나야 저장된
        // 값을 받는다(providers.dart). 그 첫 전환(empty → 실제 값)은 "방금
        // 얻었다"가 아니라 "과거 이력을 막 읽어 왔다"이므로 축하하지 않는다 —
        // 안 그러면 재도전 성공 이력이 있는 사용자는 앱을 켤 때마다 폭죽이 튄다.
        if (prev == null || identical(prev, XpSnapshot.empty)) return;
        final arrived = newlyArrivedEvents(prev, next);
        final celebrate =
            arrived.any((e) => e.kind?.isCelebration ?? false);
        if (celebrate) setState(() => _burstTrigger++);
      },
    );

    return Tooltip(
      message: '경험치 — 눌러서 내역 보기',
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => showXpSheet(context),
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.pinkBg,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.bolt, size: 15, color: AppColors.pink),
                  const SizedBox(width: 4),
                  Text(
                    'Lv.${xp.level}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.pink,
                    ),
                  ),
                  const SizedBox(width: 7),
                  TweenAnimationBuilder<int>(
                    tween: IntTween(begin: _lastTotal, end: xp.total),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOutCubic,
                    onEnd: () {
                      // 다음 변화가 여기서부터 다시 세어 나가도록 고정한다.
                      // setState 없이 값만 갱신 — 이 프레임에서 다시 그릴
                      // 이유가 없다(이미 최종값을 보여준 상태).
                      _lastTotal = xp.total;
                    },
                    builder: (context, value, _) => Text(
                      '$value XP',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.pinkMuted,
                      ),
                    ),
                  ),
                  if (xp.streak > 0) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.local_fire_department,
                        size: 14, color: AppColors.pinkStrong),
                    const SizedBox(width: 2),
                    Text(
                      '${xp.streak}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.pinkStrong,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            XpBurst(trigger: _burstTrigger),
          ],
        ),
      ),
    );
  }
}

void showXpSheet(BuildContext context) {
  showDialog<void>(context: context, builder: (_) => const _XpDialog());
}

class _XpDialog extends ConsumerWidget {
  const _XpDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final xp = ref.watch(xpProvider);

    return Dialog(
      backgroundColor: AppColors.canvasBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
              child: PanelHeader(
                title: '내 경험치',
                onClose: () => Navigator.of(context).pop(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: _LevelHeader(xp: xp),
            ),
            const Divider(height: 1, color: AppColors.border),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                children: [
                  const _SectionLabel('이렇게 쌓여요'),
                  const SizedBox(height: 8),
                  for (final kind in XpKind.values) _RuleRow(kind: kind),
                  const SizedBox(height: 22),
                  const _SectionLabel('최근 획득'),
                  const SizedBox(height: 8),
                  if (xp.recent.isEmpty)
                    const Text(
                      '아직 없어요. 기사를 하나 읽고 “내 이력 가져오기”를 눌러보세요.',
                      style: TextStyle(
                          fontSize: 12.5, color: AppColors.textMuted),
                    )
                  else
                    for (final e in xp.recent) _EventRow(event: e),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
              decoration: const BoxDecoration(
                color: AppColors.panelBg,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lock_open, size: 14, color: AppColors.textMuted),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '모아둔 XP는 앞으로 유료 기능을 여는 데 쓸 수 있어요. (준비 중)',
                      style: TextStyle(
                          fontSize: 11.5, color: AppColors.textMuted),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LevelHeader extends StatelessWidget {
  const _LevelHeader({required this.xp});

  final XpSnapshot xp;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              'Lv.${xp.level}',
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: AppColors.pink,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${xp.total} XP',
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
            const Spacer(),
            if (xp.streak > 0)
              Row(
                children: [
                  const Icon(Icons.local_fire_department,
                      size: 16, color: AppColors.pinkStrong),
                  const SizedBox(width: 4),
                  Text(
                    '${xp.streak}일 연속',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.pinkStrong,
                    ),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: xp.levelProgress,
            minHeight: 7,
            backgroundColor: AppColors.pinkBgSoft,
            valueColor: const AlwaysStoppedAnimation(AppColors.pink),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '다음 레벨까지 ${xp.toNextLevel} XP',
          style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.4,
        color: AppColors.textMuted,
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.kind});

  final XpKind kind;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            padding: const EdgeInsets.symmetric(vertical: 2),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.pinkBgSoft,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              '+${kind.amount}',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: AppColors.pink,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  kind.label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  kind.description,
                  style: const TextStyle(
                      fontSize: 11.5, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final XpEvent event;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.label,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (event.detail.isNotEmpty)
                  Text(
                    event.detail,
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.textMuted),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '+${event.amount}',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              color: AppColors.pink,
            ),
          ),
        ],
      ),
    );
  }
}
