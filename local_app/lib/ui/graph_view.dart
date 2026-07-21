import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphview/GraphView.dart' as gv;

import '../data/dto/graph.dart';
import '../providers/providers.dart';

/// 생각 지도 시각화(명세 §5.1 "뇌 지도").
///
/// 선행→후행 방향을 층으로 드러내야 하므로 Sugiyama(계층형) 레이아웃을 쓴다.
/// 말단(위쪽) 층에 선행 개념어가 모이고, 아래로 갈수록 그 개념들을 딛고 선
/// 상위 개념이 온다.
///
/// 줌·팬은 `GraphView.builder`가 내부에 품은 InteractiveViewer가 담당한다.
class ThoughtMapView extends ConsumerWidget {
  const ThoughtMapView({super.key, required this.graph});

  final Graph graph;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (graph.isEmpty) return const _EmptyGraph();

    // 선택 상태는 일부러 여기서 watch하지 않는다. 여기서 watch하면 노드를 고를
    // 때마다 그래프 전체가 다시 만들어지고 레이아웃이 튄다. 선택 표시는
    // [_ConceptNode]가 스스로 구독한다.

    // DTO → graphview 모델 변환. 엣지가 가리키는 노드가 실제로 존재할 때만
    // 연결한다(서버가 아직 없는 노드를 참조해도 렌더가 깨지지 않게).
    final gvGraph = gv.Graph()..isTree = false;
    final nodesById = <String, gv.Node>{
      for (final n in graph.nodes) n.id: gv.Node.Id(n.id),
    };
    for (final node in nodesById.values) {
      gvGraph.addNode(node);
    }
    for (final e in graph.edges) {
      final from = nodesById[e.from];
      final to = nodesById[e.to];
      if (from == null || to == null) continue;
      gvGraph.addEdge(
        from,
        to,
        paint: Paint()
          ..color = e.type == EdgeType.prereq
              ? const Color(0xFF5A6180)
              : const Color(0xFF39405C)
          ..strokeWidth = e.type == EdgeType.prereq ? 1.6 : 1.0
          ..style = PaintingStyle.stroke,
      );
    }

    final config = gv.SugiyamaConfiguration()
      ..nodeSeparation = 40
      ..levelSeparation = 70
      ..orientation = gv.SugiyamaConfiguration.ORIENTATION_TOP_BOTTOM;

    return gv.GraphView.builder(
      graph: gvGraph,
      algorithm: gv.SugiyamaAlgorithm(config),
      animated: false,
      // centerGraph는 쓰지 않는다 — 켜면 graphview가 캔버스를 잘못 잡아 노드가
      // 아예 보이지 않는다. 대신 좌상단 기준으로 그리고, 캔버스가 좁아지면
      // 사용자가 InteractiveViewer로 끌어서 본다.
      builder: (gv.Node gvNode) {
        final id = gvNode.key!.value as String;
        final node = graph.nodeById(id);
        if (node == null) return const SizedBox.shrink();
        return _ConceptNode(node: node);
      },
    );
  }
}

/// 그래프 노드 하나. 색으로 이해상태를, 모양으로 선행개념 여부를 나타낸다.
///
/// 선택 여부를 자기가 구독하되, **선택돼도 크기가 변하지 않게** 만든다.
/// 테두리 두께가 바뀌면 노드 크기가 달라져 Sugiyama 레이아웃이 다시 돌고
/// 지도 전체가 튄다. 그래서 두께는 고정하고 색과 그림자(레이아웃에 영향 없음)로만
/// 선택을 표시한다.
class _ConceptNode extends ConsumerWidget {
  const _ConceptNode({required this.node});

  final GraphNode node;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = nodeStyleOf(node);
    final selected =
        ref.watch(selectedNodeIdProvider.select((id) => id == node.id));

    return GestureDetector(
      onTap: () => ref.read(selectedNodeIdProvider.notifier).state =
          selected ? null : node.id,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        constraints: const BoxConstraints(maxWidth: 190),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: style.fill,
          borderRadius: BorderRadius.circular(node.isPrereq ? 20 : 10),
          border: Border.all(
            color: selected ? Colors.white : style.border,
            width: 1.8,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: style.border.withValues(alpha: 0.5),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              node.concept,
              style: TextStyle(
                color: style.text,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (node.isPrereq) ...[
              const SizedBox(height: 3),
              Text(
                '선행개념',
                style: TextStyle(
                  color: style.text.withValues(alpha: 0.65),
                  fontSize: 10,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 이해상태별 색. 상세 패널·범례와 색을 맞추기 위해 여기 한 곳에서 정한다.
class NodeStyle {
  const NodeStyle({
    required this.fill,
    required this.border,
    required this.text,
    required this.label,
  });

  final Color fill;
  final Color border;
  final Color text;
  final String label;
}

NodeStyle nodeStyleOf(GraphNode node) => nodeStyleOfState(node.state);

NodeStyle nodeStyleOfState(String state) {
  switch (state) {
    case NodeState.understood:
      return const NodeStyle(
        fill: Color(0xFF16362B),
        border: Color(0xFF3DDC97),
        text: Color(0xFFDFF7EC),
        label: '이해완료',
      );
    case NodeState.notUnderstood:
      return const NodeStyle(
        fill: Color(0xFF3A2233),
        border: Color(0xFFFF6B8B),
        text: Color(0xFFFFE1E8),
        label: '미이해',
      );
    default:
      // 서버가 새 상태값을 보내와도 렌더는 살아 있게 한다.
      return const NodeStyle(
        fill: Color(0xFF232734),
        border: Color(0xFF6B7394),
        text: Color(0xFFD8DCEA),
        label: '미확인',
      );
  }
}

class _EmptyGraph extends StatelessWidget {
  const _EmptyGraph();

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.hub_outlined, size: 56, color: outline),
          const SizedBox(height: 16),
          Text('아직 생각 지도가 비어 있어요',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SizedBox(
            width: 340,
            child: Text(
              '크롬 익스텐션으로 기사를 읽고 진단을 마치면, '
              '"내 이력 가져오기"를 눌렀을 때 이곳에 개념이 쌓입니다.',
              textAlign: TextAlign.center,
              style: TextStyle(color: outline, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
