import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/dto/recommendation.dart';
import '../providers/providers.dart';

/// 추천 열람(명세 §5.3).
///
/// 서버가 그래프와 함께 돌려준 세 종류를 그대로 세 섹션으로 나눠 보여준다
/// — 결핍 보완 / 심화(확장) / 기사. 기사 추천 소스는 신문사 제휴 자체
/// 데이터셋(명세 §4.4 확정)이므로 외부 브라우저로 연다.
class RecommendationPanel extends ConsumerWidget {
  const RecommendationPanel({
    super.key,
    required this.recommendations,
    this.onOpenConcept,
  });

  final Recommendations recommendations;

  /// 개념 카드를 눌렀을 때 상세 뷰를 열 콜백. null 이면 그래프 선택만 한다.
  final void Function(String conceptId)? onOpenConcept;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    if (recommendations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '동기화하면 여기에\n추천 개념과 기사가 나타납니다.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.outline, height: 1.6, fontSize: 13),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (recommendations.gapConcepts.isNotEmpty) ...[
          const _Header(
            icon: Icons.lightbulb_outline,
            title: '모를 것 같은 개념',
            subtitle: '스스로 찾아보면 좋을 개념이에요',
          ),
          const SizedBox(height: 10),
          for (final c in recommendations.gapConcepts)
            _ConceptCard(recommendation: c, onOpen: onOpenConcept),
        ],
        // 확장 추천은 콜드스타트에 비는 게 정상이라(명세 §4.4 한계) 섹션을
        // 숨기는 대신 안내를 띄운다 — 없어진 게 아니라 아직 이르다는 뜻.
        const SizedBox(height: 24),
        const _Header(
          icon: Icons.trending_up,
          title: '확장 개념',
          subtitle: '이해한 개념에서 한 걸음 더',
        ),
        const SizedBox(height: 10),
        if (recommendations.expansionConcepts.isEmpty)
          const _EmptyHint(
            text: '아직 확장 추천이 없어요.\n'
                '개념을 이해완료하면 여기에서 다음 단계를 알려드릴게요.',
          )
        else
          for (final e in recommendations.expansionConcepts)
            _ExpansionCard(recommendation: e, onOpen: onOpenConcept),
        if (recommendations.articles.isNotEmpty) ...[
          const SizedBox(height: 24),
          const _Header(
            icon: Icons.menu_book_outlined,
            title: '읽을 만한 기사',
            subtitle: '평소 읽는 주제를 반영했어요',
          ),
          const SizedBox(height: 10),
          for (final a in recommendations.articles)
            _ArticleCard(recommendation: a),
        ],
      ],
    );
  }
}

class _ConceptCard extends ConsumerWidget {
  const _ConceptCard({required this.recommendation, this.onOpen});

  final ConceptRecommendation recommendation;
  final void Function(String conceptId)? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final nodeId =
        recommendation.conceptId.isEmpty ? null : recommendation.conceptId;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: const Color(0xFF1D2130),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        // 추천을 유발한 노드가 있으면 그래프에서 그 자리를 짚어준다.
        onTap: nodeId == null
            ? null
            : () {
                ref.read(selectedNodeIdProvider.notifier).state = nodeId;
                onOpen?.call(nodeId);
              },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                recommendation.conceptTag,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600),
              ),
              if (recommendation.reason != null) ...[
                const SizedBox(height: 6),
                Text(
                  recommendation.reason!,
                  style: TextStyle(
                      fontSize: 12, color: scheme.outline, height: 1.5),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 확장 개념 카드. 탭하면 그래프에서 해당 노드를 짚어준다.
class _ExpansionCard extends ConsumerWidget {
  const _ExpansionCard({required this.recommendation, this.onOpen});

  final ExpansionRecommendation recommendation;
  final void Function(String conceptId)? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final nodeId =
        recommendation.conceptId.isEmpty ? null : recommendation.conceptId;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: const Color(0xFF1D2130),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: nodeId == null
            ? null
            : () {
                ref.read(selectedNodeIdProvider.notifier).state = nodeId;
                onOpen?.call(nodeId);
              },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      recommendation.conceptTag,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (recommendation.reason == ExpansionReason.retry)
                    Icon(Icons.replay, size: 15, color: scheme.primary),
                ],
              ),
              const SizedBox(height: 6),
              // 서버는 신호 종류만 주고 문구는 앱이 만든다(계약 §4).
              Text(
                recommendation.reason.label,
                style: TextStyle(
                    fontSize: 12, color: scheme.outline, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: scheme.outline, height: 1.6),
      ),
    );
  }
}

class _ArticleCard extends StatelessWidget {
  const _ArticleCard({required this.recommendation});

  final ArticleRecommendation recommendation;

  Future<void> _open(BuildContext context) async {
    final uri = Uri.tryParse(recommendation.url);
    final ok = uri != null &&
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('링크를 열지 못했습니다: ${recommendation.url}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: const Color(0xFF1D2130),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      recommendation.title,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.open_in_new, size: 15, color: scheme.outline),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                [
                  if (recommendation.publisher != null)
                    recommendation.publisher!,
                  if (recommendation.reason != null) recommendation.reason!,
                ].join(' · '),
                style: TextStyle(
                    fontSize: 12, color: scheme.outline, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: scheme.primary),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: TextStyle(fontSize: 11.5, color: scheme.outline)),
          ],
        ),
      ],
    );
  }
}
