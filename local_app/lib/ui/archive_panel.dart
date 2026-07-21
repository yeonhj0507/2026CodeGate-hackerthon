import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/dto/graph.dart';
import '../providers/providers.dart';
import 'app_colors.dart';
import 'graph_view.dart';
import 'widgets/panel_header.dart';

/// "보관함" — 지금까지 열람·진단한 기사 카드뷰.
///
/// **서버 왕복이 없다.** 스크랩은 동기화 시점에 서버에서 소비·삭제되고 학습
/// 데이터의 원본은 로컬이라(명세 §4.5), 이 목록은 애초에 서버에 없다. 그래프
/// 노드가 들고 있는 `sourceArticles` 를 되짚으면 "어떤 기사에서 무엇을 배웠는지"가
/// 그대로 나온다.
///
/// 묶는 규칙은 [libraryProvider] 가 갖는다 — URL 이 없는 구형 항목을 제목으로
/// 묶고, 많이 배운 기사를 위로 올린다. 서버 계약에 기사 단위 메타(진단 시각·
/// 소요 시간)가 없으므로 없는 값은 지어내지 않고 생략한다.
class ArchivePanel extends ConsumerWidget {
  const ArchivePanel({super.key, this.onClose});

  /// 도킹 패널에서 닫기(X)를 눌렀을 때. null 이면 헤더를 그리지 않는다.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(libraryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (onClose != null) ...[
          PanelHeader(title: '보관함', onClose: onClose!),
          const SizedBox(height: 14),
        ],
        Expanded(
          child: entries.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      '아직 진단한 기사가 없어요.\n'
                      '기사를 읽고 동기화하면 여기에 쌓입니다.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: AppColors.textMuted, fontSize: 13, height: 1.6),
                    ),
                  ),
                )
              : ListView(
                  children: [
                    for (final entry in entries)
                      _ArchiveCard(
                        title: entry.article.label,
                        url: entry.article.url,
                        nodes: entry.concepts,
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
