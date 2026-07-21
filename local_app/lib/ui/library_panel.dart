import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/providers.dart';

/// 보관함 — 열람한 기사를 카드로.
///
/// **서버 왕복이 없다.** 학습 데이터의 원본은 로컬이고(명세 §4.5), 스크랩은 동기화 시점에
/// 서버에서 소비·삭제되므로 서버에는 애초에 이 목록이 없다. 그래프 노드가 들고 있는
/// `sourceArticles` 를 URL 로 묶으면 "어떤 기사에서 무엇을 배웠는지"가 그대로 나온다.
class LibraryPanel extends ConsumerWidget {
  const LibraryPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(libraryProvider);
    final scheme = Theme.of(context).colorScheme;

    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '아직 보관된 기사가 없어요.\n기사를 읽고 동기화하면 여기에 쌓입니다.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.outline, height: 1.6, fontSize: 13),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text('열람한 기사 ${entries.length}건',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('기사마다 어떤 개념을 배웠는지 함께 봅니다',
            style: TextStyle(fontSize: 11.5, color: scheme.outline)),
        const SizedBox(height: 12),
        for (final entry in entries) _LibraryCard(entry: entry),
      ],
    );
  }
}

class _LibraryCard extends ConsumerWidget {
  const _LibraryCard({required this.entry});

  final LibraryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final article = entry.article;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: const Color(0xFF1D2130),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: article.hasUrl
                  ? () async {
                      final uri = Uri.tryParse(article.url);
                      if (uri != null) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    }
                  : null,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(article.label,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.4)),
                  ),
                  if (article.hasUrl) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.open_in_new, size: 15, color: scheme.outline),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            // 미리보기 자리 — 서버가 원문을 보관하지 않으므로(명세 §3.4) 요약 대신
            // "이 기사에서 무엇을 배웠는지"를 보여준다.
            Text(
              '개념 ${entry.concepts.length}개 · 이해완료 ${entry.understoodCount}개',
              style: TextStyle(fontSize: 11.5, color: scheme.outline),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final node in entry.concepts)
                  ActionChip(
                    label: Text(node.concept, style: const TextStyle(fontSize: 11.5)),
                    avatar: Icon(
                      node.isUnderstood ? Icons.check_circle : Icons.help_outline,
                      size: 14,
                      color: node.isUnderstood
                          ? const Color(0xFF4ADE80)
                          : const Color(0xFFF87171),
                    ),
                    // 그래프에서 그 개념 자리로 데려간다.
                    onPressed: () =>
                        ref.read(selectedNodeIdProvider.notifier).state = node.id,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
