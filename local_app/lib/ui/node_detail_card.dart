import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/dto/graph.dart';
import 'app_colors.dart';
import 'graph_view.dart';

/// 뇌지도에서 노드를 클릭하면 뜨는 노드 상세 카드.
///
/// 도킹 패널(추천/탐색/보관함)과는 완전히 독립적이다 — 그래프 위에 바로
/// 떠서 상태칩·재요약·출처 기사·선행/후행/연관 개념을 보여주고, 탭 전환은
/// 일으키지 않는다.
class NodeDetailCard extends StatelessWidget {
  const NodeDetailCard({
    super.key,
    required this.node,
    required this.graph,
    required this.onClose,
  });

  final GraphNode node;
  final Graph graph;
  final VoidCallback onClose;

  Future<void> _openArticle(SourceArticle article) async {
    final uri = Uri.tryParse(article.url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final style = nodeStyleOf(node);

    // 엣지는 `from`=후행 → `to`=선행이다. 내가 가리키는 쪽이 먼저 알아야 할
    // 개념이고, 나를 가리키는 쪽이 내가 열어 주는 개념이다.
    final prereqs = graph.edges
        .where((e) => e.from == node.id && e.type == EdgeType.prereq)
        .map((e) => graph.nodeById(e.to))
        .whereType<GraphNode>()
        .toList();
    final unlocks = graph.edges
        .where((e) => e.to == node.id && e.type == EdgeType.prereq)
        .map((e) => graph.nodeById(e.from))
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
      width: 320,
      constraints: const BoxConstraints(maxHeight: 420),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
              color: Color(0x1F000000), blurRadius: 20, offset: Offset(0, 6)),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    node.concept,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary),
                  ),
                ),
                IconButton(
                  tooltip: '닫기',
                  icon: const Icon(Icons.close,
                      size: 16, color: AppColors.textMuted),
                  onPressed: onClose,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              children: [
                _Chip(label: style.label, color: style.border),
              ],
            ),
            if (node.summaryMeta != null) ...[
              const SizedBox(height: 14),
              const _SectionTitle('이 개념, 다시 정리하면'),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.panelBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border(left: BorderSide(color: style.border, width: 3)),
                ),
                child: Text(
                  node.summaryMeta!,
                  style: const TextStyle(
                      height: 1.6, fontSize: 12.5, color: AppColors.textPrimary),
                ),
              ),
            ],
            if (node.sourceArticles.isNotEmpty) ...[
              const SizedBox(height: 14),
              _SectionTitle(
                node.sourceArticles.length > 1
                    ? '출처 기사 ${node.sourceArticles.length}건'
                    : '출처 기사',
              ),
              const SizedBox(height: 6),
              for (final article in node.sourceArticles)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: InkWell(
                    onTap: article.hasUrl ? () => _openArticle(article) : null,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.article_outlined,
                            size: 14, color: AppColors.textMuted),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(article.label,
                              style: const TextStyle(
                                  fontSize: 12,
                                  height: 1.4,
                                  color: AppColors.textPrimary)),
                        ),
                        if (article.hasUrl) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.open_in_new,
                              size: 12, color: AppColors.textMuted),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
            if (prereqs.isNotEmpty) ...[
              const SizedBox(height: 14),
              const _SectionTitle('먼저 알아야 하는 개념'),
              const SizedBox(height: 8),
              _NodeChips(nodes: prereqs),
            ],
            if (unlocks.isNotEmpty) ...[
              const SizedBox(height: 14),
              const _SectionTitle('이 개념이 받쳐주는 개념'),
              const SizedBox(height: 8),
              _NodeChips(nodes: unlocks),
            ],
            if (related.isNotEmpty) ...[
              const SizedBox(height: 14),
              const _SectionTitle('연관 개념'),
              const SizedBox(height: 8),
              _NodeChips(nodes: related),
            ],
          ],
        ),
      ),
    );
  }
}

/// 연결 개념 칩. 그래프 이동은 하지 않고 라벨만 보여준다 — 다른 노드로 옮기려면
/// 그래프에서 직접 클릭해야 한다(카드는 지금 선택된 노드 하나만 다룬다).
class _NodeChips extends StatelessWidget {
  const _NodeChips({required this.nodes});

  final List<GraphNode> nodes;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final n in nodes)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(radius: 4, backgroundColor: nodeStyleOf(n).border),
                const SizedBox(width: 5),
                Text(n.concept,
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.textPrimary)),
              ],
            ),
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
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
        color: AppColors.textMuted,
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
        color: color.withValues(alpha: 0.12),
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
