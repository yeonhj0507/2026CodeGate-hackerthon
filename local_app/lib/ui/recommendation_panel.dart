import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/api/mock_data.dart';
import '../data/dto/graph.dart';
import '../data/dto/recommendation.dart';
import '../providers/providers.dart';
import 'app_colors.dart';
import 'widgets/panel_header.dart';

/// 추천 열람(명세 §5.3).
///
/// 서버가 그래프와 함께 돌려준 것 중 결핍 보완(모를 것 같은 개념)과 기사를
/// 두 섹션으로 보여준다. 기사 추천 소스는 신문사 제휴 자체 데이터셋
/// (명세 §4.4 확정)이므로 외부 브라우저로 연다.
///
/// "모를 것 같은 개념"을 누르면 이 탭을 벗어나지 않고 인라인으로 개념 상세를
/// 보여준다([inlineConceptDetailProvider]) — 패널 아이콘이 "탐색"으로 넘어가면
/// 안 된다는 요구사항 때문에 그래프 선택([selectedNodeIdProvider])과는
/// 별개의 상태로 다룬다.
class RecommendationPanel extends ConsumerWidget {
  const RecommendationPanel({
    super.key,
    required this.recommendations,
    required this.graph,
    required this.onClose,
  });

  final Recommendations recommendations;
  final Graph graph;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailId = ref.watch(inlineConceptDetailProvider);
    final detailNode = detailId == null ? null : graph.nodeById(detailId);

    if (detailId != null && detailNode != null) {
      String? reason;
      for (final c in recommendations.gapConcepts) {
        if (c.conceptId == detailId) {
          reason = c.reason;
          break;
        }
      }
      return _ConceptDetailView(
        node: detailNode,
        graph: graph,
        reason: reason,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PanelHeader(title: '추천', onClose: onClose),
        const SizedBox(height: 14),
        Expanded(
          child: recommendations.isEmpty
              ? const Center(
                  child: Text(
                    '동기화하면 여기에\n추천 개념과 기사가 나타납니다.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: AppColors.textMuted, height: 1.6, fontSize: 13),
                  ),
                )
              : ListView(
                  children: [
                    if (recommendations.gapConcepts.isNotEmpty) ...[
                      const Text('모를 것 같은 개념',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary)),
                      const SizedBox(height: 10),
                      for (final c in recommendations.gapConcepts)
                        _ConceptCard(recommendation: c),
                    ],
                    if (recommendations.articles.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      const Text('읽을 만한 기사',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary)),
                      const SizedBox(height: 10),
                      for (final a in recommendations.articles)
                        _ArticleCard(recommendation: a),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _ConceptCard extends ConsumerWidget {
  const _ConceptCard({required this.recommendation});

  final ConceptRecommendation recommendation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nodeId =
        recommendation.conceptId.isEmpty ? null : recommendation.conceptId;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.pinkBg,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          // 개념 상세는 이 탭 안에서 인라인으로 펼친다 — 탐색 탭으로 넘어가지 않는다.
          onTap: nodeId == null
              ? null
              : () => ref.read(inlineConceptDetailProvider.notifier).state =
                  nodeId,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  recommendation.conceptTag,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.pink),
                ),
                if (recommendation.reason != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    recommendation.reason!,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textMuted, height: 1.5),
                  ),
                ],
              ],
            ),
          ),
        ),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _open(context),
          child: Container(
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
                        recommendation.title,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.open_in_new,
                        size: 14, color: AppColors.textMuted),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  [
                    if (recommendation.publisher != null)
                      recommendation.publisher!,
                    if (recommendation.reason != null) recommendation.reason!,
                  ].join(' · '),
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textMuted, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "모를 것 같은 개념"을 눌렀을 때 추천 탭 안에서 펼쳐지는 개념 상세.
/// 개념 · 개념 설명 · OX 퀴즈 1개 · 연관 개념으로 구성된다.
class _ConceptDetailView extends ConsumerWidget {
  const _ConceptDetailView({
    required this.node,
    required this.graph,
    required this.reason,
  });

  final GraphNode node;
  final Graph graph;
  final String? reason;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final related = graph.edges
        .where((e) => e.from == node.id || e.to == node.id)
        .map((e) => e.from == node.id
            ? graph.nodeById(e.to)
            : graph.nodeById(e.from))
        .whereType<GraphNode>()
        .toSet()
        .toList();
    final quiz = MockData.conceptQuizzes[node.id];

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () =>
                ref.read(inlineConceptDetailProvider.notifier).state = null,
            child: const Row(
              children: [
                Icon(Icons.arrow_back, size: 16, color: AppColors.textMuted),
                SizedBox(width: 6),
                Text('추천으로 돌아가기',
                    style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            node.concept,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            node.summaryMeta ?? reason ?? '아직 이 개념에 대한 설명이 준비되지 않았어요.',
            style: const TextStyle(
                fontSize: 12.5, height: 1.6, color: AppColors.textPrimary),
          ),
          if (quiz != null) ...[
            const SizedBox(height: 18),
            _OxQuizCard(quiz: quiz),
          ],
          if (related.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Text('연관 개념',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMuted)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final n in related)
                  ActionChip(
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: AppColors.border),
                    label: Text(n.concept,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textPrimary)),
                    onPressed: () => ref
                        .read(inlineConceptDetailProvider.notifier)
                        .state = n.id,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// OX 퀴즈 하나. 누르면 정답 여부를 바로 보여준다(서버 채점 없이 로컬에서만).
class _OxQuizCard extends StatefulWidget {
  const _OxQuizCard({required this.quiz});

  final ConceptQuiz quiz;

  @override
  State<_OxQuizCard> createState() => _OxQuizCardState();
}

class _OxQuizCardState extends State<_OxQuizCard> {
  bool? _picked;

  @override
  Widget build(BuildContext context) {
    final answered = _picked != null;
    final correct = answered && _picked == widget.quiz.answer;

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
          const Text('OX 퀴즈',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted)),
          const SizedBox(height: 6),
          Text(
            widget.quiz.question,
            style: const TextStyle(
                fontSize: 13, height: 1.5, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _OxButton(
                label: 'O',
                selected: _picked == true,
                onTap: answered ? null : () => setState(() => _picked = true),
              ),
              const SizedBox(width: 8),
              _OxButton(
                label: 'X',
                selected: _picked == false,
                onTap: answered ? null : () => setState(() => _picked = false),
              ),
            ],
          ),
          if (answered) ...[
            const SizedBox(height: 10),
            Text(
              (correct ? '정답이에요. ' : '아쉬워요. ') + widget.quiz.explanation,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.5,
                color: correct ? AppColors.textPrimary : AppColors.pink,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OxButton extends StatelessWidget {
  const _OxButton({required this.label, required this.selected, this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.pinkBgSoft : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: selected ? AppColors.pink : AppColors.border),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: selected ? AppColors.pink : AppColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
