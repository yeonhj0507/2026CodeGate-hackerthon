import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config.dart';
import '../data/dto/graph.dart';
import '../providers/providers.dart';
import 'graph_view.dart';
import 'node_detail_panel.dart';
import 'side_tabs.dart';

/// 홈 — 좌측 생각 지도, 우측 추천 패널.
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
      ref.read(syncControllerProvider.notifier).syncOnLaunch();
    });
  }

  @override
  Widget build(BuildContext context) {
    final graphAsync = ref.watch(graphProvider);
    final sync = ref.watch(syncControllerProvider);
    final selectedId = ref.watch(selectedNodeIdProvider);

    _listenForSyncFeedback();

    final graph = graphAsync.valueOrNull ?? Graph.empty;
    final selected = selectedId == null ? null : graph.nodeById(selectedId);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF181B26),
        title: Row(
          children: [
            const Text('생각 지도',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 14),
            if (!graph.isEmpty) _GraphStats(graph: graph),
          ],
        ),
        actions: [
          if (AppConfig.useMock)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(child: _MockBadge()),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(child: _LastSynced(syncedAt: sync.lastSyncedAt)),
          ),
          // 트리거 ②: 수동 동기화.
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: sync.inProgress
                  ? null
                  : () => ref.read(syncControllerProvider.notifier).sync(),
              icon: sync.inProgress
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync, size: 18),
              label: Text(sync.inProgress ? '가져오는 중…' : '내 이력 가져오기'),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'logout') {
                ref.read(authControllerProvider.notifier).logout();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'logout', child: Text('로그아웃')),
            ],
          ),
        ],
      ),
      body: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                if (sync.error != null)
                  _SyncErrorBar(
                    message: sync.error!.message,
                    onDismiss: () =>
                        ref.read(syncControllerProvider.notifier).clearError(),
                  ),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ThoughtMapView(graph: graph),
                      ),
                      // 우상단에 둔다. 그래프는 위에서 아래로 뻗으며 가운데
                      // 정렬되므로, 좌하단에 두면 노드 상세가 열려 캔버스가
                      // 낮아졌을 때 노드를 덮는다.
                      if (!graph.isEmpty)
                        const Positioned(
                          right: 16,
                          top: 16,
                          child: _Legend(),
                        ),
                    ],
                  ),
                ),
                if (selected != null)
                  SizedBox(
                    height: 300,
                    child: NodeDetailPanel(node: selected, graph: graph),
                  ),
              ],
            ),
          ),
          Container(width: 1, color: Theme.of(context).colorScheme.outlineVariant),
          SizedBox(
            width: 340,
            child: SideTabs(
              graph: graph,
              recommendations: sync.recommendations,
            ),
          ),
        ],
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text(added > 0
              ? '새 개념 $added개가 생각 지도에 반영됐어요.'
              : '반영할 새 진단 기록이 없습니다.'),
        ),
      );
    });
  }
}

class _GraphStats extends StatelessWidget {
  const _GraphStats({required this.graph});

  final Graph graph;

  @override
  Widget build(BuildContext context) {
    final notUnderstood = graph.nodes.where((n) => n.isNotUnderstood).length;
    final understood = graph.nodes.where((n) => n.isUnderstood).length;
    return Text(
      '개념 ${graph.nodes.length} · 이해완료 $understood · 미이해 $notUnderstood',
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.normal,
        color: Theme.of(context).colorScheme.outline,
      ),
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
      style: TextStyle(
          fontSize: 12, color: Theme.of(context).colorScheme.outline),
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
        color: const Color(0xFF4A3A12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFD8A93B)),
      ),
      child: const Text(
        'MOCK',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Color(0xFFFFD98A),
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
        color: const Color(0xFF181B26).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2C3244)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _LegendRow(
              color: nodeStyleOfState(NodeState.understood).border,
              label: '이해완료'),
          const SizedBox(height: 6),
          _LegendRow(
              color: nodeStyleOfState(NodeState.notUnderstood).border,
              label: '미이해'),
          const SizedBox(height: 6),
          const _LegendRow(
              color: Color(0xFF8AA0FF), label: '둥근 노드 = 선행개념', rounded: true),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.color,
    required this.label,
    this.rounded = false,
  });

  final Color color;
  final String label;
  final bool rounded;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.25),
            border: Border.all(color: color, width: 1.4),
            borderRadius: BorderRadius.circular(rounded ? 6 : 3),
          ),
        ),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 11.5)),
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
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.errorContainer,
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Icon(Icons.cloud_off, size: 18, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '동기화 실패 — $message',
              style: TextStyle(color: scheme.onErrorContainer, fontSize: 13),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            color: scheme.onErrorContainer,
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}
