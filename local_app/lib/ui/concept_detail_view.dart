import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/dto/graph.dart';
import '../providers/providers.dart';

/// 추천 탭에서 개념을 누르면 열리는 상세.
///
/// 개념 · 설명(`summaryMeta`) · **O/X 퀴즈** · 연관 개념 네 가지를 한 화면에 둔다.
/// OX 는 서버가 사용자가 실제로 골랐던 오답 선지를 그대로 문장으로 준 것이라,
/// 여기서 다시 풀어 보는 것이 곧 오답 복기다.
class ConceptDetailView extends ConsumerStatefulWidget {
  const ConceptDetailView({
    super.key,
    required this.node,
    required this.graph,
    required this.onBack,
  });

  final GraphNode node;
  final Graph graph;
  final VoidCallback onBack;

  @override
  ConsumerState<ConceptDetailView> createState() => _ConceptDetailViewState();
}

class _ConceptDetailViewState extends ConsumerState<ConceptDetailView> {
  /// 사용자가 고른 답. null 이면 아직 안 풀었다.
  bool? _picked;

  @override
  void didUpdateWidget(ConceptDetailView old) {
    super.didUpdateWidget(old);
    // 다른 개념으로 넘어가면 O/X 상태를 초기화한다.
    if (old.node.id != widget.node.id) _picked = null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final node = widget.node;

    // 연관 개념 — 선행(from→this)과 후행(this→to). node_detail_panel 과 같은 규칙.
    final prereqs = widget.graph.edges
        .where((e) => e.to == node.id)
        .map((e) => widget.graph.nodeById(e.from))
        .whereType<GraphNode>()
        .toList();
    final unlocks = widget.graph.edges
        .where((e) => e.from == node.id)
        .map((e) => widget.graph.nodeById(e.to))
        .whereType<GraphNode>()
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        TextButton.icon(
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back, size: 16),
          label: const Text('추천 목록'),
          style: TextButton.styleFrom(padding: EdgeInsets.zero),
        ),
        const SizedBox(height: 4),
        Text(node.concept,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),

        if (node.summaryMeta != null) ...[
          _Label('이 개념, 다시 정리하면'),
          const SizedBox(height: 6),
          Text(node.summaryMeta!,
              style: const TextStyle(fontSize: 13, height: 1.65)),
          const SizedBox(height: 20),
        ],

        if (node.oxQuiz != null) ...[
          _Label('O / X 로 확인하기'),
          const SizedBox(height: 8),
          _OxCard(
            quiz: node.oxQuiz!,
            picked: _picked,
            onPick: (v) => setState(() => _picked = v),
          ),
          const SizedBox(height: 20),
        ],

        if (prereqs.isNotEmpty) ...[
          _Label('먼저 알아야 하는 개념'),
          const SizedBox(height: 6),
          _Chips(nodes: prereqs, scheme: scheme),
          const SizedBox(height: 16),
        ],
        if (unlocks.isNotEmpty) ...[
          _Label('이 개념이 받쳐주는 개념'),
          const SizedBox(height: 6),
          _Chips(nodes: unlocks, scheme: scheme),
        ],
      ],
    );
  }
}

class _OxCard extends StatelessWidget {
  const _OxCard({required this.quiz, required this.picked, required this.onPick});

  final OxQuiz quiz;
  final bool? picked;
  final ValueChanged<bool> onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final answered = picked != null;
    final correct = picked == quiz.answer;

    return Card(
      margin: EdgeInsets.zero,
      color: const Color(0xFF1D2130),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(quiz.statement,
                style: const TextStyle(fontSize: 13.5, height: 1.6)),
            const SizedBox(height: 12),
            Row(
              children: [
                _OxButton(label: 'O', value: true, picked: picked, onPick: onPick),
                const SizedBox(width: 8),
                _OxButton(label: 'X', value: false, picked: picked, onPick: onPick),
              ],
            ),
            if (answered) ...[
              const SizedBox(height: 12),
              Text(
                correct
                    ? '정답이에요. 정답은 ${quiz.answer ? 'O' : 'X'} 입니다.'
                    : '아쉬워요. 정답은 ${quiz.answer ? 'O' : 'X'} 입니다.',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: correct ? const Color(0xFF4ADE80) : const Color(0xFFF87171),
                ),
              ),
              if (quiz.sourceQuestion != null) ...[
                const SizedBox(height: 6),
                Text('원래 문항 — ${quiz.sourceQuestion!}',
                    style: TextStyle(fontSize: 11.5, color: scheme.outline, height: 1.5)),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _OxButton extends StatelessWidget {
  const _OxButton({
    required this.label,
    required this.value,
    required this.picked,
    required this.onPick,
  });

  final String label;
  final bool value;
  final bool? picked;
  final ValueChanged<bool> onPick;

  @override
  Widget build(BuildContext context) {
    final selected = picked == value;
    return SizedBox(
      width: 56,
      child: OutlinedButton(
        onPressed: () => onPick(value),
        style: OutlinedButton.styleFrom(
          backgroundColor: selected ? const Color(0xFF2B3350) : null,
          padding: const EdgeInsets.symmetric(vertical: 10),
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class _Chips extends ConsumerWidget {
  const _Chips({required this.nodes, required this.scheme});

  final List<GraphNode> nodes;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final n in nodes)
          ActionChip(
            label: Text(n.concept, style: const TextStyle(fontSize: 12)),
            // 그래프에서 그 자리를 짚어 준다.
            onPressed: () =>
                ref.read(selectedNodeIdProvider.notifier).state = n.id,
          ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.outline,
        ));
  }
}
