import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/dto/graph.dart';
import '../data/dto/recommendation.dart';
import '../providers/providers.dart';

/// 탐색 탭 — 키워드 2~3개를 골라 "더 탐색하기".
///
/// 개별 개념을 하나씩 보는 추천 탭과 달리, **여러 개념을 묶었을 때 무엇이 보이는지**를
/// 서버에 물어본다(설명 2~3문장 + 기사 2건).
class ExplorePanel extends ConsumerWidget {
  const ExplorePanel({super.key, required this.graph});

  final Graph graph;

  static const _maxPick = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final picked = ref.watch(exploreSelectionProvider);
    final result = ref.watch(exploreControllerProvider);

    // 진단된 개념만 후보로 둔다 — 아직 만나지 않은 개념은 묶어봐야 의미가 없다.
    final candidates =
        graph.nodes.where((n) => n.state != NodeState.unknown).toList();

    if (candidates.isEmpty) {
      return _Hint(
        text: '아직 탐색할 개념이 없어요.\n기사를 읽고 동기화하면 여기에 키워드가 쌓입니다.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text('키워드를 2~3개 고르세요',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('묶었을 때 어떻게 이어지는지 설명해 드릴게요',
            style: TextStyle(fontSize: 11.5, color: scheme.outline)),
        const SizedBox(height: 12),

        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final node in candidates)
              FilterChip(
                label: Text(node.concept, style: const TextStyle(fontSize: 12)),
                selected: picked.contains(node.id),
                // 상한을 넘기면 더 못 고르게 막는다(서버도 5개까지만 받는다).
                onSelected: (on) {
                  final next = {...picked};
                  if (on) {
                    if (next.length >= _maxPick) return;
                    next.add(node.id);
                  } else {
                    next.remove(node.id);
                  }
                  ref.read(exploreSelectionProvider.notifier).state = next;
                },
              ),
          ],
        ),
        const SizedBox(height: 14),

        FilledButton.icon(
          onPressed: picked.isEmpty || result.isLoading
              ? null
              : () => ref.read(exploreControllerProvider.notifier).run(
                    picked.map(graph.nodeById).whereType<GraphNode>().toList(),
                  ),
          icon: result.isLoading
              ? const SizedBox(
                  width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.travel_explore, size: 18),
          label: Text(result.isLoading ? '찾는 중…' : '더 탐색하기'),
        ),

        const SizedBox(height: 18),
        result.when(
          loading: () => const SizedBox.shrink(),
          error: (e, _) => _Hint(text: '탐색에 실패했어요.\n$e'),
          data: (data) {
            if (data == null) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (data.explanation.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1D2130),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(data.explanation,
                        style: const TextStyle(fontSize: 13, height: 1.7)),
                  ),
                  const SizedBox(height: 16),
                ],
                if (data.articles.isNotEmpty) ...[
                  Text('이어서 읽어보기',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: scheme.outline)),
                  const SizedBox(height: 8),
                  for (final a in data.articles) _ExploreArticle(article: a),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ExploreArticle extends StatelessWidget {
  const _ExploreArticle({required this.article});

  final ArticleRecommendation article;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: const Color(0xFF1D2130),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final uri = Uri.tryParse(article.url);
          if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(article.title,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.open_in_new, size: 15, color: scheme.outline),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                [
                  if (article.publisher != null) article.publisher!,
                  if (article.isFromSearch) '웹 검색',
                ].join(' · '),
                style: TextStyle(fontSize: 11.5, color: scheme.outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
                height: 1.6,
                fontSize: 13)),
      ),
    );
  }
}
