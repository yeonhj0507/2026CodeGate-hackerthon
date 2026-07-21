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
import 'node_detail_card.dart';
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
    final selectedId = ref.watch(selectedNodeIdProvider);

    _listenForSyncFeedback();

    final graph = graphAsync.valueOrNull ?? Graph.empty;

    // 추천 패널이 열려 있는 동안만 확장 후보를 지도에 임시 노드로 얹는다.
    // 카드에 낱말만 뜨면 그 개념이 내가 아는 것 중 무엇에서 나왔는지 안 보인다.
    final displayGraph = mode == RightPanelMode.recommendations
        ? withExpansionCandidates(graph, sync.recommendations.expansionConcepts)
        : graph;

    // 상세도 표시용 그래프에서 찾는다 — 임시 노드를 눌렀을 때 빈손이 되지 않게.
    final selected = selectedId == null ? null : displayGraph.nodeById(selectedId);

    return Scaffold(
      backgroundColor: AppColors.canvasBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TopBar(mode: mode, graph: graph),
              const SizedBox(height: 20),
              Expanded(
                child: graph.isEmpty
                    ? const OnboardingView()
                    : _MainContent(
                        graph: displayGraph,
                        sync: sync,
                        mode: mode,
                        selected: selected,
                        onErrorDismiss: () => ref
                            .read(syncControllerProvider.notifier)
                            .clearError(),
                        onClosePanel: () => ref
                            .read(rightPanelModeProvider.notifier)
                            .state = RightPanelMode.closed,
                        onCloseNodeDetail: () => ref
                            .read(selectedNodeIdProvider.notifier)
                            .state = null,
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
  const _TopBar({required this.mode, required this.graph});

  final RightPanelMode mode;
  final Graph graph;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncControllerProvider);

    return Row(
      children: [
        const LogoLockup(),
        if (!graph.isEmpty) ...[
          const SizedBox(width: 14),
          _GraphStats(graph: graph),
        ],
        const Spacer(),
        // 경험치 배지 — 눌러서 적립 내역을 연다.
        const XpBadge(),
        const SizedBox(width: 12),
        if (AppConfig.useMock) ...[
          const _MockBadge(),
          const SizedBox(width: 12),
        ],
        _LastSynced(syncedAt: sync.lastSyncedAt),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: sync.inProgress
              ? null
              : () => ref.read(syncControllerProvider.notifier).sync(),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            side: const BorderSide(color: AppColors.border),
          ),
          icon: sync.inProgress
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync, size: 18),
          label: Text(sync.inProgress ? '가져오는 중…' : '내 이력 가져오기'),
        ),
        const SizedBox(width: 8),
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
    required this.selected,
    required this.onErrorDismiss,
    required this.onClosePanel,
    required this.onCloseNodeDetail,
  });

  final Graph graph;
  final SyncState sync;
  final RightPanelMode mode;
  final GraphNode? selected;
  final VoidCallback onErrorDismiss;
  final VoidCallback onClosePanel;
  final VoidCallback onCloseNodeDetail;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _FilterChips(),
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
                    if (selected != null)
                      Positioned(
                        left: 16,
                        bottom: 16,
                        child: NodeDetailCard(
                          node: selected!,
                          graph: graph,
                          onClose: onCloseNodeDetail,
                        ),
                      ),
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
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 20),
      decoration: BoxDecoration(
        color: AppColors.panelBg,
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

/// 지도가 지금 무엇을 담고 있는지 한 줄로. 노드가 화면 밖에 있어도 총량이
/// 보여서, 지도에 뜬 개수와 어긋나면 바로 눈에 띈다.
class _GraphStats extends StatelessWidget {
  const _GraphStats({required this.graph});

  final Graph graph;

  @override
  Widget build(BuildContext context) {
    final notUnderstood = graph.nodes.where((n) => n.isNotUnderstood).length;
    final understood = graph.nodes.where((n) => n.isUnderstood).length;
    return Text(
      '개념 ${graph.nodes.length} · 이해완료 $understood · 미이해 $notUnderstood',
      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
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

class _LastSynced extends StatelessWidget {
  const _LastSynced({required this.syncedAt});

  final DateTime? syncedAt;

  @override
  Widget build(BuildContext context) {
    if (syncedAt == null) return const SizedBox.shrink();
    final t = syncedAt!;
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return Text(
      '마지막 동기화 $hh:$mm',
      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
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
