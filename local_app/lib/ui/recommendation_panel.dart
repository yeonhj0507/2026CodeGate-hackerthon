import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/dto/graph.dart';
import '../data/dto/recommendation.dart';
import '../providers/providers.dart';
import 'app_colors.dart';
import 'widgets/panel_header.dart';

/// 추천 열람(명세 §5.3).
///
/// 서버가 그래프와 함께 돌려준 **세 종류**를 그대로 세 섹션으로 나눈다
/// — 결핍 보완 / 확장(심화) / 기사. 기사 추천 소스는 신문사 제휴 자체
/// 데이터셋(명세 §4.4 확정)이라 외부 브라우저로 연다.
///
/// 개념을 누르면 이 탭을 벗어나지 않고 **인라인으로** 상세를 편다
/// ([inlineConceptDetailProvider]). 패널이 다른 탭으로 넘어가면 안 되기 때문에
/// 그래프 선택([selectedNodeIdProvider])과는 별개의 상태로 다루고, 여기서
/// 지도 선택을 함께 옮기지도 않는다 — 옮기면 같은 개념의 상세가 지도와 패널
/// 양쪽에 동시에 떠서 같은 내용이 두 번 나온다.
class RecommendationPanel extends ConsumerWidget {
  const RecommendationPanel({
    super.key,
    required this.recommendations,
    required this.graph,
    this.onClose,
  });

  final Recommendations recommendations;

  /// 인라인 상세가 연관 개념·OX 를 뽑아 쓸 원본.
  final Graph graph;

  /// 도킹 패널에서 닫기(X)를 눌렀을 때. null 이면 헤더를 그리지 않는다.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailId = ref.watch(inlineConceptDetailProvider);
    final detailNode = detailId == null ? null : graph.nodeById(detailId);

    if (detailNode != null) {
      return _ConceptDetailView(
        node: detailNode,
        graph: graph,
        reason: _reasonFor(detailNode.id),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (onClose != null) ...[
          PanelHeader(title: '추천', onClose: onClose!),
          const SizedBox(height: 14),
        ],
        Expanded(
          child: recommendations.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      '동기화하면 여기에\n추천 개념과 기사가 나타납니다.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: AppColors.textMuted, height: 1.6, fontSize: 13),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    if (recommendations.gapConcepts.isNotEmpty) ...[
                      const _SectionTitle('모를 것 같은 개념'),
                      const SizedBox(height: 10),
                      for (final c in recommendations.gapConcepts)
                        _ConceptCard(recommendation: c),
                    ],
                    // 확장은 "아직 내 그래프에 없는 새 개념"이다. 제휴 데이터셋이
                    // 내 주제를 못 덮으면 비는 게 정상이라, 섹션을 숨기는 대신
                    // 안내를 띄운다 — 없어진 게 아니라 아직 재료가 없다는 뜻이다.
                    const SizedBox(height: 22),
                    const _SectionTitle('확장 개념'),
                    const SizedBox(height: 2),
                    const _SectionCaption('아는 개념에서 새로 알 수 있는 키워드'),
                    const SizedBox(height: 10),
                    if (recommendations.expansionConcepts.isEmpty)
                      const _EmptyHint(
                        text: '아직 추천할 키워드가 없어요.\n'
                            '기사를 더 읽으면 아는 개념 주변에서 찾아 드릴게요.',
                      )
                    else
                      for (final e in recommendations.expansionConcepts)
                        _ExpansionCard(recommendation: e),
                    // 다시 도전은 오답 이력이 있어야 생긴다. 없을 때는 섹션째
                    // 숨긴다 — 확장과 달리 "아직 이르다"가 곧 "틀린 게 없다"라
                    // 굳이 안내할 일이 아니다.
                    if (recommendations.retryConcepts.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      const _SectionTitle('다시 도전할 개념'),
                      const SizedBox(height: 10),
                      for (final e in recommendations.retryConcepts)
                        _RetryCard(recommendation: e),
                    ],
                    if (recommendations.articles.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      const _SectionTitle('읽을 만한 기사'),
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

  String? _reasonFor(String conceptId) {
    for (final c in recommendations.gapConcepts) {
      if (c.conceptId == conceptId) return c.reason;
    }
    return null;
  }
}

/// 개념 카드를 눌렀을 때 — 이 패널 안에서 상세만 편다.
///
/// **[selectedNodeIdProvider]는 건드리지 않는다.** 지도 선택은 지도 위 상세를
/// 여는 신호라, 여기서 함께 옮기면 같은 개념이 우측 패널과 지도 양쪽에 동시에
/// 뜬다. 지도 탭과 추천 탭은 각자의 상세를 갖는다.
void _openConcept(WidgetRef ref, String? nodeId) {
  if (nodeId == null || nodeId.isEmpty) return;
  ref.read(inlineConceptDetailProvider.notifier).state = nodeId;
}

class _ConceptCard extends ConsumerWidget {
  const _ConceptCard({required this.recommendation});

  final ConceptRecommendation recommendation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _CardShell(
      onTap: () => _openConcept(ref, recommendation.conceptId),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            recommendation.conceptTag,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary),
          ),
          if (recommendation.reason != null) ...[
            const SizedBox(height: 6),
            Text(
              recommendation.reason!,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textMuted, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}

/// 확장 개념 카드 — 아직 내 그래프에 없는 새 키워드.
///
/// 카드를 눌러도 짚어 줄 노드가 없다(지도에는 임시 회색 노드로만 떠 있다).
/// 대신 **그 개념이 실제로 쓰인 기사**로 바로 갈 수 있게 한다.
class _ExpansionCard extends StatelessWidget {
  const _ExpansionCard({required this.recommendation});

  final ExpansionRecommendation recommendation;

  Future<void> _open(BuildContext context) async {
    final uri = Uri.tryParse(recommendation.articleUrl);
    final ok = uri != null &&
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('링크를 열지 못했습니다: ${recommendation.articleUrl}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      onTap: recommendation.hasArticle ? () => _open(context) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  recommendation.conceptTag,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary),
                ),
              ),
              const Icon(Icons.auto_awesome, size: 15, color: AppColors.pink),
            ],
          ),
          const SizedBox(height: 6),
          // 서버는 근거 개념만 주고 문구는 앱이 만든다(계약 §4).
          Text(
            recommendation.label,
            style: const TextStyle(
                fontSize: 12, color: AppColors.textMuted, height: 1.5),
          ),
          if (recommendation.hasArticle) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.article_outlined,
                    size: 13, color: AppColors.pink),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    recommendation.articleTitle,
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.pink, height: 1.4),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.open_in_new,
                    size: 12, color: AppColors.textMuted),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 다시 도전할 개념 카드. 내 그래프 안의 노드라 눌러서 상세를 펼 수 있다.
class _RetryCard extends ConsumerWidget {
  const _RetryCard({required this.recommendation});

  final RetryRecommendation recommendation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _CardShell(
      onTap: () => _openConcept(ref, recommendation.conceptId),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  recommendation.conceptTag,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary),
                ),
              ),
              if (recommendation.reason == RetryReason.retry)
                const Icon(Icons.replay, size: 15, color: AppColors.pink),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            recommendation.reason.label,
            style: const TextStyle(
                fontSize: 12, color: AppColors.textMuted, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _SectionCaption extends StatelessWidget {
  const _SectionCaption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(fontSize: 11, color: AppColors.textMuted));
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
    return _CardShell(
      onTap: () => _open(context),
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
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.open_in_new,
                  size: 15, color: AppColors.textMuted),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            [
              if (recommendation.publisher != null) recommendation.publisher!,
              if (recommendation.reason != null) recommendation.reason!,
            ].join(' · '),
            style: const TextStyle(
                fontSize: 12, color: AppColors.textMuted, height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// 추천 탭의 카드 한 장. 라이트 팔레트에서는 그림자 대신 옅은 테두리로 나눈다.
class _CardShell extends StatelessWidget {
  const _CardShell({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.panelBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(14), child: child),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary));
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Text(
        text,
        style: const TextStyle(
            fontSize: 12, color: AppColors.textMuted, height: 1.6),
      ),
    );
  }
}

/// 개념 하나를 펼친 화면 — 개념명 · 설명 · O/X · 연관 개념.
///
/// 추천 탭 안에서 열리고 닫힌다(별도 화면으로 나가지 않는다).
class _ConceptDetailView extends ConsumerWidget {
  const _ConceptDetailView({
    required this.node,
    required this.graph,
    required this.reason,
  });

  final GraphNode node;
  final Graph graph;

  /// 이 개념이 추천된 이유. `summaryMeta` 가 아직 없을 때의 대체 설명이다.
  final String? reason;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 방향을 가리지 않고 이어진 개념을 모은다 — 상세에서는 선행/후행 구분보다
    // "이 개념 주변에 무엇이 있나"가 먼저다.
    final related = graph.edges
        .where((e) => e.from == node.id || e.to == node.id)
        .map((e) =>
            e.from == node.id ? graph.nodeById(e.to) : graph.nodeById(e.from))
        .whereType<GraphNode>()
        .toSet()
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
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
                    style:
                        TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
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
          if (node.oxQuiz != null) ...[
            const SizedBox(height: 18),
            _OxQuizCard(quiz: node.oxQuiz!, nodeId: node.id),
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
                    onPressed: () => _openConcept(ref, n.id),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// O/X 한 문항. 채점은 로컬에서 한다 — 서버는 이 답을 알 필요가 없다.
///
/// 문항은 서버가 사용자의 **실제 오답 선지**를 그대로 진술문으로 만들어 준 것이라
/// (LLM 호출 없음, server `merge.py:_attach_ox_quiz`), 여기서 다시 풀어 보는 것이
/// 곧 오답 복기다. 그래서 해설이 따로 없다 — 진술문 자체가 자기가 틀렸던 문장이다.
///
/// **맞히면 그 개념이 이해완료로 올라가고 XP가 붙는다.** 로컬이 학습 데이터의
/// 원본이라(명세 §4.5) 서버 왕복이 필요 없고, 다음 동기화에서 되돌아가지도
/// 않는다 — 서버는 이번 스크랩에 등장한 개념만 상태를 덮기 때문이다.
class _OxQuizCard extends ConsumerStatefulWidget {
  const _OxQuizCard({required this.quiz, required this.nodeId});

  final OxQuiz quiz;
  final String nodeId;

  @override
  ConsumerState<_OxQuizCard> createState() => _OxQuizCardState();
}

class _OxQuizCardState extends ConsumerState<_OxQuizCard> {
  bool? _picked;

  /// 정답으로 받은 XP. 0이면 안내를 띄우지 않는다(이미 이해완료였던 경우 등).
  int _xpGained = 0;

  @override
  void didUpdateWidget(_OxQuizCard old) {
    super.didUpdateWidget(old);
    // 다른 개념으로 넘어가면 O/X 를 처음 상태로 되돌린다.
    if (old.quiz.statement != widget.quiz.statement) {
      _picked = null;
      _xpGained = 0;
    }
  }

  Future<void> _pick(bool value) async {
    setState(() => _picked = value);
    if (value != widget.quiz.answer) return;

    final granted = await solveOxQuiz(ref, widget.nodeId);
    if (!mounted) return;
    setState(() => _xpGained = granted.fold(0, (sum, e) => sum + e.amount));
  }

  @override
  Widget build(BuildContext context) {
    final picked = _picked;
    final answered = picked != null;
    final correct = answered && picked == widget.quiz.answer;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.panelBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
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
            widget.quiz.statement,
            style: const TextStyle(
                fontSize: 13, height: 1.5, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _OxButton(
                label: 'O',
                selected: picked == true,
                onTap: answered ? null : () => _pick(true),
              ),
              const SizedBox(width: 8),
              _OxButton(
                label: 'X',
                selected: picked == false,
                onTap: answered ? null : () => _pick(false),
              ),
            ],
          ),
          if (answered) ...[
            const SizedBox(height: 10),
            Text(
              correct
                  ? '정답이에요. 정답은 ${widget.quiz.answer ? 'O' : 'X'} 입니다.'
                  : '아쉬워요. 정답은 ${widget.quiz.answer ? 'O' : 'X'} 입니다.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.5,
                fontWeight: FontWeight.w600,
                color: correct ? AppColors.textPrimary : AppColors.pink,
              ),
            ),
            if (_xpGained > 0) ...[
              const SizedBox(height: 6),
              Text(
                '이해완료로 올렸어요.  +$_xpGained XP',
                style: const TextStyle(
                  fontSize: 11.5,
                  height: 1.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.pink,
                ),
              ),
            ],
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
            border:
                Border.all(color: selected ? AppColors.pink : AppColors.border),
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
