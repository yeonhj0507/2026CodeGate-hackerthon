import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/dto/graph.dart';
import '../providers/providers.dart';
import 'graph_view.dart';

/// 노드 상세. 크로스기사 연결은 그래프에 이미 병합돼 있으므로 별도 탐색 화면
/// 없이 여기서 "출처 기사" 목록으로 드러난다(명세 §5.1).
///
/// `summaryMeta`가 개인화 요약이 흡수된 자리다(명세 §4.4) — 별도 요약 열람
/// 기능은 두지 않는다.
class NodeDetailPanel extends ConsumerWidget {
  const NodeDetailPanel({super.key, required this.node, required this.graph});

  final GraphNode node;
  final Graph graph;

  /// 출처 기사 원문 열기. 실패해도 조용히 넘긴다 — 부가 동작이라 흐름을 막지 않는다.
  Future<void> _openArticle(SourceArticle article) async {
    final uri = Uri.tryParse(article.url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = nodeStyleOf(node);
    final scheme = Theme.of(context).colorScheme;

    final prereqs = graph.edges
        .where((e) => e.to == node.id && e.type == EdgeType.prereq)
        .map((e) => graph.nodeById(e.from))
        .whereType<GraphNode>()
        .toList();
    final unlocks = graph.edges
        .where((e) => e.from == node.id && e.type == EdgeType.prereq)
        .map((e) => graph.nodeById(e.to))
        .whereType<GraphNode>()
        .toList();
    final related = graph.edges
        .where((e) => e.type != EdgeType.prereq)
        .map((e) => e.from == node.id
            ? graph.nodeById(e.to)
            : (e.to == node.id ? graph.nodeById(e.from) : null))
        .whereType<GraphNode>()
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF181B26),
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    node.concept,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: '닫기',
                  icon: const Icon(Icons.close),
                  onPressed: () =>
                      ref.read(selectedNodeIdProvider.notifier).state = null,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                _Chip(label: style.label, color: style.border),
                if (node.isPrereq)
                  const _Chip(label: '선행개념', color: Color(0xFF8AA0FF)),
              ],
            ),
            if (node.summaryMeta != null) ...[
              const SizedBox(height: 18),
              _SectionTitle('이 개념, 다시 정리하면'),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF20242F),
                  borderRadius: BorderRadius.circular(10),
                  border: Border(
                    left: BorderSide(color: style.border, width: 3),
                  ),
                ),
                child: Text(
                  node.summaryMeta!,
                  style: const TextStyle(height: 1.6, fontSize: 13),
                ),
              ),
            ],
            if (node.sourceArticles.isNotEmpty) ...[
              const SizedBox(height: 18),
              _SectionTitle(
                node.sourceArticles.length > 1
                    ? '출처 기사 ${node.sourceArticles.length}건 — 여러 기사에서 반복 등장'
                    : '출처 기사',
              ),
              const SizedBox(height: 6),
              for (final article in node.sourceArticles)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: InkWell(
                    // URL 이 있으면 원문을 외부 브라우저로 연다.
                    onTap: article.hasUrl ? () => _openArticle(article) : null,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.article_outlined,
                            size: 15, color: scheme.outline),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(article.label,
                              style:
                                  const TextStyle(fontSize: 12.5, height: 1.4)),
                        ),
                        if (article.hasUrl) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.open_in_new,
                              size: 13, color: scheme.outline),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
            if (prereqs.isNotEmpty) ...[
              const SizedBox(height: 18),
              _SectionTitle('먼저 알아야 하는 개념'),
              const SizedBox(height: 8),
              _NodeChips(nodes: prereqs),
            ],
            if (unlocks.isNotEmpty) ...[
              const SizedBox(height: 18),
              _SectionTitle('이 개념이 받쳐주는 개념'),
              const SizedBox(height: 8),
              _NodeChips(nodes: unlocks),
            ],
            if (related.isNotEmpty) ...[
              const SizedBox(height: 18),
              _SectionTitle('연관 개념'),
              const SizedBox(height: 8),
              _NodeChips(nodes: related),
            ],
          ],
        ),
      ),
    );
  }
}

/// 연결 개념 칩. 누르면 그래프 선택이 그 노드로 옮겨간다.
class _NodeChips extends ConsumerWidget {
  const _NodeChips({required this.nodes});

  final List<GraphNode> nodes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final n in nodes)
          ActionChip(
            label: Text(n.concept, style: const TextStyle(fontSize: 12)),
            avatar: CircleAvatar(
              radius: 5,
              backgroundColor: nodeStyleOf(n).border,
            ),
            onPressed: () =>
                ref.read(selectedNodeIdProvider.notifier).state = n.id,
          ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
        color: Theme.of(context).colorScheme.outline,
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
