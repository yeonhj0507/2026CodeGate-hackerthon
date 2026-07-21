import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/api/mock_data.dart';
import '../data/dto/graph.dart';
import '../data/dto/recommendation.dart';
import '../providers/providers.dart';
import 'app_colors.dart';
import 'widgets/panel_header.dart';

/// "탐색" 탭 — 뇌지도에서 개념을 드래그해다 놓으면(최대 5개) "더 탐색하기"로
/// 각 키워드의 설명과 기사 2개씩을 함께 보여준다.
///
/// 키워드는 오직 드래그로만 담긴다 — 그래프 노드를 짧게 탭하는 것(=노드 상세
/// 카드 열기, [NodeDetailCard])과 완전히 독립된 액션이다.
class ExplorePanel extends ConsumerWidget {
  const ExplorePanel({super.key, required this.graph, required this.onClose});

  static const maxKeywords = 5;

  final Graph graph;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIds = ref.watch(exploreKeywordProvider);
    final revealed = ref.watch(exploreRevealedProvider);
    final selectedNodes =
        selectedIds.map(graph.nodeById).whereType<GraphNode>().toList();

    void add(String id) {
      final current = ref.read(exploreKeywordProvider);
      if (current.contains(id) || current.length >= maxKeywords) return;
      ref.read(exploreKeywordProvider.notifier).state = [...current, id];
      ref.read(exploreRevealedProvider.notifier).state = false;
    }

    void remove(String id) {
      ref.read(exploreKeywordProvider.notifier).state =
          ref.read(exploreKeywordProvider).where((e) => e != id).toList();
      ref.read(exploreRevealedProvider.notifier).state = false;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PanelHeader(title: '탐색', onClose: onClose),
        const SizedBox(height: 4),
        Text(
          '함께 알아보고 싶은 개념을 최대 $maxKeywords개까지 골라보세요 '
          '(${selectedIds.length}/$maxKeywords)',
          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
        const SizedBox(height: 10),
        _KeywordDropZone(
          selectedNodes: selectedNodes,
          canAcceptMore: selectedIds.length < maxKeywords,
          onAccept: add,
          onRemove: remove,
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: selectedNodes.isEmpty
                ? null
                : () => ref.read(exploreRevealedProvider.notifier).state = true,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.pink,
              disabledBackgroundColor: AppColors.border,
            ),
            child: const Text('더 탐색하기'),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: revealed && selectedNodes.isNotEmpty
              ? ListView(
                  children: [
                    for (final n in selectedNodes) ...[
                      _ExploreResult(node: n),
                      const SizedBox(height: 14),
                    ],
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// 뇌지도에서 드래그해온 노드를 받는 드롭 영역. 담긴 키워드는 칩으로 보여주고
/// 칩의 ×로 뺄 수 있다.
class _KeywordDropZone extends StatelessWidget {
  const _KeywordDropZone({
    required this.selectedNodes,
    required this.canAcceptMore,
    required this.onAccept,
    required this.onRemove,
  });

  final List<GraphNode> selectedNodes;
  final bool canAcceptMore;
  final ValueChanged<String> onAccept;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          canAcceptMore && !selectedNodes.any((n) => n.id == details.data),
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidateData, rejectedData) {
        final hovering = candidateData.isNotEmpty;
        return Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: hovering ? AppColors.pinkBgSoft : AppColors.panelBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: hovering ? AppColors.pink : AppColors.border,
              width: hovering ? 1.6 : 1,
            ),
          ),
          child: selectedNodes.isEmpty
              ? const Center(
                  child: Text(
                    '뇌지도에서 개념을 길게 눌러 여기로 끌어다 놓으세요',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                  ),
                )
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final n in selectedNodes)
                      _SelectedKeywordChip(
                        label: n.concept,
                        onRemove: () => onRemove(n.id),
                      ),
                  ],
                ),
        );
      },
    );
  }
}

class _SelectedKeywordChip extends StatelessWidget {
  const _SelectedKeywordChip({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 12, right: 4, top: 5, bottom: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.pink),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.pink)),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onRemove,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close, size: 13, color: AppColors.pink),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExploreResult extends StatelessWidget {
  const _ExploreResult({required this.node});

  final GraphNode node;

  @override
  Widget build(BuildContext context) {
    final content = MockData.exploreContent[node.id];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.panelBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            node.concept,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            content?.summary ?? '아직 이 개념에 대한 설명이 준비되지 않았어요.',
            style: const TextStyle(
                fontSize: 12.5, height: 1.6, color: AppColors.textPrimary),
          ),
          if (content != null && content.articles.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('관련 기사',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMuted)),
            const SizedBox(height: 8),
            for (final a in content.articles) _ExploreArticleTile(article: a),
          ],
        ],
      ),
    );
  }
}

class _ExploreArticleTile extends StatelessWidget {
  const _ExploreArticleTile({required this.article});

  final ArticleRecommendation article;

  Future<void> _open(BuildContext context) async {
    final uri = Uri.tryParse(article.url);
    final ok =
        uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('링크를 열지 못했습니다: ${article.url}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _open(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    article.title,
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.textPrimary),
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.open_in_new,
                    size: 12, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
