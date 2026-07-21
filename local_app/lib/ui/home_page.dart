import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config.dart';
import '../data/dto/graph.dart';
import '../providers/providers.dart';
import 'app_colors.dart';
import 'archive_panel.dart';
import 'expansion_overlay.dart';
import 'explore_panel.dart';
import 'graph_view.dart';
import 'onboarding_view.dart';
import 'recommendation_panel.dart';
import 'widgets/logo_mark.dart';
import 'xp_panel.dart';

/// 홈 — 좌측 생각 지도, 우측 도킹 패널(추천/탐색/보관함 전환).
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  @override
  void initState() {
    super.initState();
    // 트리거 ①: 앱 실행 시 최초 1회 자동 동기화(명세 §5.2). 폴링은 하지 않는다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 접속 기록이 먼저다 — 스트릭 XP를 찍고 나서 동기화 XP가 얹혀야
      // 배지가 한 번만 튀고 최종값으로 안착한다.
      ref.read(xpProvider.notifier).registerVisit();
      ref.read(syncControllerProvider.notifier).syncOnLaunch();
    });
  }

  @override
  Widget build(BuildContext context) {
    final graphAsync = ref.watch(graphProvider);
    final sync = ref.watch(syncControllerProvider);
    final mode = ref.watch(rightPanelModeProvider);

    _listenForSyncFeedback();

    final graph = graphAsync.valueOrNull ?? Graph.empty;

    // 추천 패널이 열려 있는 동안만 확장 후보를 지도에 임시 노드로 얹는다.
    // 카드에 낱말만 뜨면 그 개념이 내가 아는 것 중 무엇에서 나왔는지 안 보인다.
    final displayGraph = mode == RightPanelMode.recommendations
        ? withExpansionCandidates(graph, sync.recommendations.expansionConcepts)
        : graph;

    // 노드 상세 카드는 ThoughtMapView 가 노드 옆에 직접 띄운다(_NodeDetailOverlay).
    // 여기서 좌하단에 고정으로 그리지 않는다.

    return Scaffold(
      backgroundColor: AppColors.canvasBg,
      body: SafeArea(
        child: Padding(
          // 위쪽은 커스텀 타이틀바(38px)가 이미 띄워주므로 덜 준다.
          padding: const EdgeInsets.fromLTRB(32, 8, 32, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TopBar(mode: mode),
              const SizedBox(height: 20),
              Expanded(
                child: graph.isEmpty
                    ? const OnboardingView()
                    : _MainContent(
                        graph: displayGraph,
                        sync: sync,
                        mode: mode,
                        onErrorDismiss: () => ref
                            .read(syncControllerProvider.notifier)
                            .clearError(),
                        onClosePanel: () => ref
                            .read(rightPanelModeProvider.notifier)
                            .state = RightPanelMode.closed,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 동기화가 끝나면 "몇 개가 새로 반영됐는지"를 스낵바로 알린다.
  void _listenForSyncFeedback() {
    ref.listen<SyncState>(syncControllerProvider, (prev, next) {
      if (prev == null || !prev.inProgress || next.inProgress) return;
      if (next.error != null) return;
      final added = next.addedNodeCount ?? 0;
      if (!mounted) return;
      final xp = next.xpGained;
      final base = added > 0
          ? '새 개념 $added개가 생각 지도에 반영됐어요.'
          : '반영할 새 진단 기록이 없습니다.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text(xp > 0 ? '$base  +$xp XP' : base),
          action: xp > 0
              ? SnackBarAction(
                  label: '내역',
                  onPressed: () => showXpSheet(context),
                )
              : null,
        ),
      );
    });
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.mode});

  final RightPanelMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 동기화 버튼과 마지막 동기화 시각은 지도 좌하단 FAB 로 옮겼다
    // (graph_view.dart 의 _SyncFab). 상단바는 로고와 패널 전환만 남긴다.
    return Row(
      children: [
        const LogoLockup(),
        const Spacer(),
        if (AppConfig.useMock) ...[
          const _MockBadge(),
          const SizedBox(width: 12),
        ],
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: AppColors.textMuted),
          onSelected: (v) {
            if (v == 'logout') {
              ref.read(authControllerProvider.notifier).logout();
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'logout', child: Text('로그아웃')),
          ],
        ),
        const SizedBox(width: 16),
        _PanelModeSwitch(mode: mode),
      ],
    );
  }
}

/// 우상단 플로팅 아이콘 3개로 도킹 패널 모드를 전환한다(Figma 전 화면 공통).
class _PanelModeSwitch extends ConsumerWidget {
  const _PanelModeSwitch({required this.mode});

  final RightPanelMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void select(RightPanelMode m) =>
        ref.read(rightPanelModeProvider.notifier).state = m;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ModeButton(
          icon: Icons.lightbulb_outline,
          tooltip: '추천',
          active: mode == RightPanelMode.recommendations,
          onTap: () => select(RightPanelMode.recommendations),
        ),
        const SizedBox(width: 8),
        _ModeButton(
          icon: Icons.travel_explore,
          tooltip: '탐색',
          active: mode == RightPanelMode.explore,
          onTap: () => select(RightPanelMode.explore),
        ),
        const SizedBox(width: 8),
        _ModeButton(
          icon: Icons.inventory_2_outlined,
          tooltip: '보관함',
          active: mode == RightPanelMode.archive,
          onTap: () => select(RightPanelMode.archive),
        ),
      ],
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: active ? AppColors.pinkBgSoft : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
                color: active ? AppColors.pink : AppColors.border),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x12000000), blurRadius: 10, offset: Offset(0, 2)),
            ],
          ),
          child: Icon(icon,
              size: 20, color: active ? AppColors.pink : AppColors.textMuted),
        ),
      ),
    );
  }
}

class _MainContent extends StatelessWidget {
  const _MainContent({
    required this.graph,
    required this.sync,
    required this.mode,
    required this.onErrorDismiss,
    required this.onClosePanel,
  });

  final Graph graph;
  final SyncState sync;
  final RightPanelMode mode;
  final VoidCallback onErrorDismiss;
  final VoidCallback onClosePanel;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  _FilterChips(),
                  SizedBox(width: 12),
                  // 경험치 배지 — 눌러서 적립 내역을 연다. 상단바를 비우면서
                  // 필터 칩 옆으로 내려왔다.
                  XpBadge(),
                ],
              ),
              const SizedBox(height: 8),
              if (sync.error != null)
                _SyncErrorBar(
                  message: sync.error!.message,
                  onDismiss: onErrorDismiss,
                ),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      // 도킹 패널이 열리고 닫히면 그래프 캔버스의 가용 너비가
                      // 바뀐다. graphview의 내부 InteractiveViewer가 그 변화에
                      // 맞춰 스스로 재조정되지 않고 확대/위치가 깨지는 문제가
                      // 있어(패키지 이슈), 패널 열림 여부가 바뀔 때마다 키를
                      // 바꿔 위젯을 통째로 새로 만든다 — 그러면 새 너비 기준
                      // 으로 레이아웃을 처음부터 다시 계산한다.
                      child: ThoughtMapView(
                        key: ValueKey(mode != RightPanelMode.closed),
                        graph: graph,
                      ),
                    ),
                    const Positioned(right: 16, top: 16, child: _Legend()),
                    // 노드 상세 카드는 ThoughtMapView 안에서 노드 옆에 뜬다.
                  ],
                ),
              ),
            ],
          ),
        ),
        if (mode != RightPanelMode.closed) ...[
          const SizedBox(width: 24),
          SizedBox(
            width: 360,
            child: _DockedPanel(
              child: switch (mode) {
                RightPanelMode.closed => const SizedBox.shrink(),
                RightPanelMode.recommendations => RecommendationPanel(
                    recommendations: sync.recommendations,
                    graph: graph,
                    onClose: onClosePanel,
                  ),
                RightPanelMode.explore =>
                  ExplorePanel(graph: graph, onClose: onClosePanel),
                RightPanelMode.archive =>
                  ArchivePanel(onClose: onClosePanel),
              },
            ),
          ),
        ],
      ],
    );
  }
}

/// 우측 도킹 패널 공용 컨테이너(Figma "Right Panel (docked)"). 닫기 버튼은
/// 각 패널의 [PanelHeader]가 타이틀과 같은 줄에 그린다.
class _DockedPanel extends StatelessWidget {
  const _DockedPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.pinkBgFaint,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

/// 상단 기간 필터 드롭다운. 시안엔 있지만 실제 필터링 로직은 아직 없다 — UI만 배치한다.
class _FilterChips extends StatefulWidget {
  const _FilterChips();

  @override
  State<_FilterChips> createState() => _FilterChipsState();
}

class _FilterChipsState extends State<_FilterChips> {
  static const _options = ['전체', '최근 7일', '1개월', '3개월'];

  String _selected = _options.first;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      initialValue: _selected,
      onSelected: (v) => setState(() => _selected = v),
      itemBuilder: (_) => [
        for (final option in _options)
          PopupMenuItem(value: option, child: Text(option)),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.chipSelectedBg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _selected,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, size: 18, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

class _MockBadge extends StatelessWidget {
  const _MockBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3D6),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFD8A93B)),
      ),
      child: const Text(
        'MOCK',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Color(0xFF8A6D1E),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _LegendRow(
              color: nodeStyleOfState(NodeState.understood).border,
              label: nodeStyleOfState(NodeState.understood).label),
          const SizedBox(height: 6),
          _LegendRow(
              color: nodeStyleOfState(NodeState.notUnderstood).border,
              label: nodeStyleOfState(NodeState.notUnderstood).label),
          const SizedBox(height: 6),
          _LegendRow(
              color: nodeStyleOfState(NodeState.unknown).border,
              label: nodeStyleOfState(NodeState.unknown).label),
          const SizedBox(height: 6),
          // 기사 노드는 이해상태가 없다. 색이 아니라 아이콘으로 구분되므로
          // 범례도 같은 아이콘을 쓴다.
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 12,
                child: Icon(Icons.article_outlined,
                    size: 12, color: AppColors.textMuted),
              ),
              SizedBox(width: 8),
              Text('기사 — 눌러서 열기',
                  style:
                      TextStyle(fontSize: 11.5, color: AppColors.textPrimary)),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.color,
    required this.label,
  });

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            border: Border.all(color: color, width: 1.4),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Text(label,
            style: const TextStyle(fontSize: 11.5, color: AppColors.textPrimary)),
      ],
    );
  }
}

class _SyncErrorBar extends StatelessWidget {
  const _SyncErrorBar({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.pinkBg,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.cloud_off, size: 16, color: AppColors.pink),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '동기화 실패 — $message',
              style: const TextStyle(color: AppColors.pink, fontSize: 12.5),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            color: AppColors.pink,
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}
