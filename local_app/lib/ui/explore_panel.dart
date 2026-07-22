import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/dto/explore.dart';
import '../data/dto/graph.dart';
import '../data/dto/recommendation.dart';
import '../providers/providers.dart';
import 'app_colors.dart';
import 'widgets/panel_header.dart';

/// "탐색" 탭 — 뇌지도에서 개념을 끌어다 놓고 **묶어서** 물어본다.
///
/// 개별 개념을 하나씩 보는 추천 탭과 다른 점이 여기다. 서버 `/explore` 는 고른
/// 개념 전체를 한 번에 받아 **관계 중심 설명 한 덩어리**와 기사 2건을 돌려준다
/// (`EXPLORE_SYSTEM` 프롬프트). 그래서 결과도 키워드마다 나누지 않고 카드 하나로
/// 보여준다 — 개념별로 쪼개면 이 기능의 존재 이유가 사라진다.
///
/// 키워드는 오직 **드래그로만** 담긴다. 그래프 노드를 짧게 탭하는 것(노드 선택)과
/// 완전히 독립된 액션이라, 지도를 둘러보다 키워드가 저절로 쌓이지 않는다.
class ExplorePanel extends ConsumerWidget {
  const ExplorePanel({super.key, required this.graph, this.onClose});

  /// 서버가 한 번에 받는 개념 수 상한과 맞춘다(`ExploreRequest.conceptTags`).
  static const maxKeywords = 5;

  final Graph graph;

  /// 도킹 패널에서 닫기(X)를 눌렀을 때. null 이면 헤더를 그리지 않는다.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIds = ref.watch(exploreKeywordProvider);
    final revealed = ref.watch(exploreRevealedProvider);
    final result = ref.watch(exploreControllerProvider);
    final selectedNodes =
        selectedIds.map(graph.nodeById).whereType<GraphNode>().toList();

    // 키워드 구성이 바뀌면 결과를 접는다. 고른 것과 화면에 떠 있는 설명이
    // 어긋난 채로 남으면 안 되기 때문에, 결과는 항상 버튼을 눌러 갱신한다.
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

    Future<void> run() async {
      ref.read(exploreRevealedProvider.notifier).state = true;
      await ref.read(exploreControllerProvider.notifier).run(selectedNodes);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (onClose != null) ...[
          PanelHeader(title: '탐색', onClose: onClose!),
          const SizedBox(height: 14),
        ],
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
            onPressed: selectedNodes.isEmpty || result.isLoading ? null : run,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.pink,
              disabledBackgroundColor: AppColors.border,
            ),
            child: Text(result.isLoading ? '찾는 중…' : '더 탐색하기'),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: !revealed
              ? const SizedBox.shrink()
              : result.when(
                  loading: () => const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.pink),
                    ),
                  ),
                  error: (e, _) => _Hint('탐색에 실패했어요.\n$e'),
                  data: (data) => data == null || data.isEmpty
                      ? const _Hint('보여줄 내용을 찾지 못했어요.')
                      : _ExploreResultView(result: data),
                ),
        ),
      ],
    );
  }
}

/// 뇌지도에서 끌어온 노드를 받는 드롭 영역.
///
/// 담긴 키워드는 칩으로 보여주고 ×로 뺀다.
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
            color: hovering ? AppColors.pinkBgSoft : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: hovering ? AppColors.pink : Colors.transparent,
              width: 1.6,
            ),
            boxShadow: hovering
                ? null
                : const [
                    BoxShadow(
                        color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 2)),
                  ],
          ),
          child: selectedNodes.isEmpty
              ? const Center(
                  child: Text(
                    '뇌지도에서 개념을 길게 눌러 여기로 끌어다 놓으세요',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
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

/// 서버가 돌려준 **한 덩어리** 결과 — 묶어서 본 설명 + 이어 읽을 기사.
class _ExploreResultView extends StatelessWidget {
  const _ExploreResultView({required this.result});

  final ExploreResult result;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (result.explanation.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.all(Radius.circular(10)),
              boxShadow: [
                BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 2)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('이 개념들을 함께 보면',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textMuted)),
                const SizedBox(height: 8),
                Text(
                  result.explanation,
                  style: const TextStyle(
                      fontSize: 13, height: 1.7, color: AppColors.textPrimary),
                ),
              ],
            ),
          ),
        if (result.articles.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('이어서 읽어보기',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted)),
          const SizedBox(height: 8),
          for (final a in result.articles) _ExploreArticleTile(article: a),
        ],
        // 웹 뉴스 검색이 실패했으면 기사 영역에만 알린다(설명은 그대로 둔다).
        // 제휴 기사가 있으면 그 아래에, 없으면 이 안내만 뜬다.
        if (result.searchFailed) ...[
          const SizedBox(height: 16),
          const _SearchFailedNote(),
        ],
      ],
    );
  }
}

/// 웹 뉴스 검색이 실패했을 때 기사 영역에 뜨는 안내.
class _SearchFailedNote extends StatelessWidget {
  const _SearchFailedNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.pinkBgFaint,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: const Row(
        children: [
          Icon(Icons.error_outline, size: 15, color: AppColors.pink),
          SizedBox(width: 8),
          Expanded(
            child: Text('뉴스 검색에 실패했어요.',
                style: TextStyle(fontSize: 12, color: AppColors.textPrimary)),
          ),
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
    final ok = uri != null &&
        await launchUrl(uri, mode: LaunchMode.externalApplication);
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
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.all(Radius.circular(8)),
              boxShadow: [
                BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 2)),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        article.title,
                        style: const TextStyle(
                            fontSize: 11.5, color: AppColors.textPrimary),
                      ),
                      // 제휴 데이터셋에서 온 것과 웹 검색으로 채운 것을 구분한다.
                      if (article.publisher != null || article.isFromSearch) ...[
                        const SizedBox(height: 3),
                        Text(
                          [
                            if (article.publisher != null) article.publisher!,
                            if (article.isFromSearch) '웹 검색',
                          ].join(' · '),
                          style: const TextStyle(
                              fontSize: 10.5, color: AppColors.textMuted),
                        ),
                      ],
                    ],
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

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 12.5, height: 1.6, color: AppColors.textMuted),
        ),
      ),
    );
  }
}
