import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/dto/graph.dart';
import 'app_colors.dart';
import 'graph_view.dart';
import 'widgets/panel_header.dart';

/// "보관함" — 지금까지 열람·진단한 기사 카드뷰(Figma S3).
///
/// 서버 계약(명세 §4)에 기사 단위 메타(진단 시각·소요 시간)가 아직 없어서,
/// 그래프에 이미 반영된 [GraphNode.sourceArticles]를 기사 URL 기준으로 묶어
/// 실제 데이터만으로 만든다. 카드마다 기사 링크와, 그 기사에서 학습한
/// 개념들을 보여준다. 없는 값(날짜·소요 시간)은 지어내지 않고 생략한다.
class ArchivePanel extends ConsumerWidget {
  const ArchivePanel({super.key, required this.graph, required this.onClose});

  final Graph graph;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conceptsByUrl = <String, List<GraphNode>>{};
    final labelByUrl = <String, String>{};
    for (final node in graph.nodes) {
      for (final article in node.sourceArticles) {
        conceptsByUrl.putIfAbsent(article.url, () => []).add(node);
        labelByUrl[article.url] = article.label;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PanelHeader(title: '보관함', onClose: onClose),
        const SizedBox(height: 14),
        Expanded(
          child: conceptsByUrl.isEmpty
              ? const Center(
                  child: Text(
                    '아직 진단한 기사가 없어요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                )
              : ListView(
                  children: [
                    for (final entry in conceptsByUrl.entries)
                      _ArchiveCard(
                        title: labelByUrl[entry.key]!,
                        url: entry.key,
                        nodes: entry.value,
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _ArchiveCard extends StatelessWidget {
  const _ArchiveCard({required this.title, required this.url, required this.nodes});

  final String title;
  final String url;
  final List<GraphNode> nodes;

  Future<void> _open(BuildContext context) async {
    final uri = Uri.tryParse(url);
    final ok =
        uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('링크를 열지 못했습니다: $url')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _open(context),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.open_in_new,
                        size: 13, color: AppColors.textMuted),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final n in nodes)
                      _ConceptChip(
                        label: n.concept,
                        color: nodeStyleOf(n).border,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 이 기사에서 학습한 개념 하나. 색으로 이해상태를 나타낸다(그래프 범례와 동일).
class _ConceptChip extends StatelessWidget {
  const _ConceptChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10.5, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
