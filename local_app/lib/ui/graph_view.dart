import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphview/GraphView.dart' as gv;
import 'package:url_launcher/url_launcher.dart';

import '../data/dto/graph.dart';
import '../providers/providers.dart';
import 'app_colors.dart';
import 'article_nodes.dart';

/// 생각 지도 시각화(명세 §5.1 "뇌 지도").
///
/// 선행→후행 방향을 층으로 드러내야 하므로 Sugiyama(계층형) 레이아웃을 쓴다.
/// 말단(위쪽) 층에 선행 개념어가 모이고, 아래로 갈수록 그 개념들을 딛고 선
/// 상위 개념이 온다.
///
/// 줌·팬은 `GraphView.builder`가 내부에 품은 InteractiveViewer가 담당한다.
///
/// **엣지 없는 노드도 반드시 그린다.** graphview 1.5.1 의 기본 델리게이트는
/// 그릴 그래프를 *엣지에서만* 모은다([_AllNodesDelegate] 참고). 진단 초기에는
/// 개념 대부분이 아직 관계를 못 얻어 고립돼 있어서, 그대로 두면 "개념 6"인데
/// 지도에는 연결된 2개만 뜬다.
///
/// **전체 보기(zoomToFit)가 필수다.** Sugiyama 는 서로 연결되지 않은 노드들을
/// 같은 층에 가로로 죽 늘어놓는다. 진단 초기에는 개념 대부분이 고립돼 있어
/// 그래프 폭이 뷰포트를 쉽게 넘고, 기본 변환(1배·좌상단)으로 두면 화면에
/// **연결된 몇 개만 보이고 나머지는 캔버스 밖에 남는다**(헤더는 "개념 6"인데
/// 지도에는 2개만 뜨는 현상). `calculateGraphBounds` 는 음수 좌표까지 감안하므로
/// 맞춰 넣으면 전부 들어온다.
class ThoughtMapView extends ConsumerStatefulWidget {
  const ThoughtMapView({super.key, required this.graph});

  final Graph graph;

  @override
  ConsumerState<ThoughtMapView> createState() => _ThoughtMapViewState();
}

class _ThoughtMapViewState extends ConsumerState<ThoughtMapView> {
  final _controller = gv.GraphViewController();

  /// 마지막으로 화면에 맞춘 그래프의 모양. 노드·엣지 구성이 바뀔 때만 다시 맞춘다.
  /// 매 빌드마다 맞추면 사용자가 확대해 둔 상태를 빼앗는다.
  String? _fittedShape;

  String _shapeOf(Graph g) => [
        for (final n in g.nodes) n.id,
        '|',
        for (final e in g.edges) '${e.from}>${e.to}',
      ].join(',');

  /// 노드 하나가 **혼자** 리빌드될 때 나머지가 지워지는 것을 막는다.
  ///
  /// graphview 1.5.1 의 `performLayout` 은 전체 재계산이 아닐 때 자식 배치
  /// (`_layoutNodesLazily`)를 통째로 건너뛰는데, 그 뒤 `endLayout()` 은
  /// **이번 배치에서 재사용되지 않은 자식을 전부 언마운트**한다. 그래서 재계산
  /// 없는 재레이아웃이 한 번만 일어나도 노드가 몰살된다.
  ///
  /// 노드를 탭할 때는 상위(HomePage)가 선택 상태를 구독해 함께 리빌드되므로
  /// 재계산이 걸려 문제가 드러나지 않는다. 반면 드래그는 Draggable 이 자기
  /// 자식만 다시 그리기 때문에 이 경로를 정통으로 밟는다.
  void _keepNodesAlive() => _controller.forceRecalculation();

  void _fitWhenShapeChanged(Graph g) {
    final shape = _shapeOf(g);
    if (shape == _fittedShape) return;
    _fittedShape = shape;
    // 레이아웃이 끝난 뒤라야 뷰포트 크기와 노드 좌표가 잡힌다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.zoomToFit();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.graph.isEmpty) return const _EmptyGraph();

    // 기사 노드는 화면에서만 존재한다. 저장·동기화되는 그래프는 그대로 둔다
    // (article_nodes.dart 주석 — 서버가 기사를 개념으로 착각하면 안 된다).
    final graph = withArticleNodes(widget.graph);

    _fitWhenShapeChanged(graph);

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
      // 기사→개념 줄은 개념 사이의 관계선보다 연하게. 지도의 주인공은 개념이고
      // 기사선은 출처를 훑을 때만 눈에 들어오면 된다.
      final isSource = e.type == articleEdgeType;
      gvGraph.addEdge(
        from,
        to,
        paint: Paint()
          ..color = isSource
              ? AppColors.pinkMuted.withValues(alpha: 0.45)
              : e.type == EdgeType.prereq
                  ? const Color(0xFFD9D2C8)
                  : const Color(0xFFE8E2D8)
          ..strokeWidth = isSource
              ? 1.0
              : e.type == EdgeType.prereq
                  ? 1.6
                  : 1.0
          ..style = PaintingStyle.stroke,
      );
    }

    final config = gv.SugiyamaConfiguration()
      ..nodeSeparation = 40
      ..levelSeparation = 70
      ..orientation = gv.SugiyamaConfiguration.ORIENTATION_TOP_BOTTOM;

    final algorithm = gv.SugiyamaAlgorithm(config);
    Widget nodeBuilder(gv.Node gvNode) {
      final id = gvNode.key!.value as String;
      final node = graph.nodeById(id);
      if (node == null) return const SizedBox.shrink();
      if (isArticleNodeId(id)) return _ArticleNode(node: node);
      return _ConceptNode(node: node, keepNodesAlive: _keepNodesAlive);
    }

    return Stack(
      children: [
        Positioned.fill(
          child: gv.GraphView.builder(
            graph: gvGraph,
            controller: _controller,
            algorithm: algorithm,
            animated: false,
            // centerGraph는 쓰지 않는다 — 켜면 graphview가 캔버스를 잘못 잡아
            // 노드가 아예 보이지 않는다. 화면 맞춤은 zoomToFit 이 맡는다.
            builder: nodeBuilder,
          )..delegate = _AllNodesDelegate(
              graph: gvGraph,
              algorithm: algorithm,
              builder: nodeBuilder,
              controller: _controller,
            ),
        ),
        // 확대하다 길을 잃어도 한 번에 돌아올 수 있게 둔다. 자동 맞춤은 그래프
        // 모양이 바뀔 때만 돌기 때문에, 그 사이의 탈출구가 필요하다.
        Positioned(
          left: 16,
          bottom: 16,
          child: Tooltip(
            message: '전체 보기',
            child: FloatingActionButton.small(
              heroTag: 'graph-fit',
              onPressed: _controller.zoomToFit,
              child: const Icon(Icons.fit_screen_outlined),
            ),
          ),
        ),
      ],
    );
  }
}

/// 엣지에 걸리지 않은 노드까지 그리게 하는 델리게이트.
///
/// graphview 1.5.1 의 `GraphChildDelegate.getVisibleGraphOnly()` 는 그릴 그래프를
/// **엣지를 훑으며** 만든다.
///
/// ```dart
/// for (final edge in graph.edges) { ... visibleGraph.addEdgeS(edge); }
/// if (visibleGraph.nodes.isEmpty && graph.nodes.isNotEmpty) {
///   visibleGraph.addNode(graph.nodes.first);   // 노드 1개짜리 응급 처치
/// }
/// ```
///
/// 그래서 엣지가 하나도 안 걸린 노드는 조용히 빠진다(위젯이 아예 만들어지지 않아
/// 화면 밖으로 밀린 것과도 구분이 안 된다). 레이아웃 알고리즘 자체는 고립 노드를
/// 잘 배치하므로 — Sugiyama 는 이들을 최상단 층에 나란히 놓는다 — 여기서 노드
/// 목록만 채워 넣으면 된다.
class _AllNodesDelegate extends gv.GraphChildDelegate {
  _AllNodesDelegate({
    required super.graph,
    required super.algorithm,
    required super.builder,
    required super.controller,
  });

  @override
  gv.Graph getVisibleGraphOnly() {
    final visible = super.getVisibleGraphOnly();
    for (final node in graph.nodes) {
      // 상위 구현이 노드가 0개일 때 넣어 두는 응급 노드와 중복되지 않게 확인한다.
      if (isNodeVisible(node) && !visible.nodes.contains(node)) {
        visible.addNode(node);
      }
    }
    return visible;
  }
}

/// 그래프 노드 하나. 색으로 이해상태를, 모양으로 선행개념 여부를 나타낸다.
///
/// 선택 여부를 자기가 구독하되, **선택돼도 크기가 변하지 않게** 만든다.
/// 테두리 두께가 바뀌면 노드 크기가 달라져 Sugiyama 레이아웃이 다시 돌고
/// 지도 전체가 튄다. 그래서 두께는 고정하고 색과 그림자(레이아웃에 영향 없음)로만
/// 선택을 표시한다.
///
/// 짧게 누르면(탭) 노드가 선택되고, 길게 눌러 끌면(드래그) "탐색" 탭의 키워드로
/// 담긴다. 두 액션은 완전히 독립적이다 — 탭이 탐색 선택까지 건드리면 지도를
/// 둘러보다가 의도치 않게 키워드가 쌓인다.
class _ConceptNode extends ConsumerWidget {
  const _ConceptNode({required this.node, required this.keepNodesAlive});

  final GraphNode node;

  /// 드래그가 시작·종료될 때 지도 전체를 살려 두기 위한 신호([_keepNodesAlive]).
  /// 두 시점 모두 이 노드만 다시 그려지므로 둘 다 걸어야 한다.
  final VoidCallback keepNodesAlive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = nodeStyleOf(node);
    final selected =
        ref.watch(selectedNodeIdProvider.select((id) => id == node.id));

    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      constraints: const BoxConstraints(maxWidth: 190),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: style.fill,
        borderRadius: BorderRadius.circular(node.isPrereq ? 20 : 10),
        border: Border.all(
          color: selected ? AppColors.pink : style.border,
          width: 1.8,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: style.border.withValues(alpha: 0.35),
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
    );

    return LongPressDraggable<String>(
      data: node.id,
      onDragStarted: keepNodesAlive,
      onDragEnd: (_) => keepNodesAlive(),
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.pink,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 3)),
            ],
          ),
          child: Text(node.concept,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: content),
      child: GestureDetector(
        onTap: () => ref.read(selectedNodeIdProvider.notifier).state =
            selected ? null : node.id,
        child: content,
      ),
    );
  }
}

/// 기사 노드. 개념 노드와 **다르게 생겨야 한다** — 이해 대상이 아니기 때문이다.
///
/// 개념 노드와 세 가지가 다르다:
///   - 선택되지 않는다. 상세 패널은 개념을 설명하는 자리다.
///   - 탐색 탭으로 끌어다 놓을 수 없다. 기사는 개념이 아니라 키워드가 못 된다.
///   - 탭하면 기사가 브라우저에서 열린다(URL 이 있을 때만).
class _ArticleNode extends StatelessWidget {
  const _ArticleNode({required this.node});

  final GraphNode node;

  SourceArticle? get _article =>
      node.sourceArticles.isEmpty ? null : node.sourceArticles.first;

  Future<void> _open() async {
    final url = _article?.url ?? '';
    final uri = Uri.tryParse(url);
    if (url.isEmpty || uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final hasUrl = (_article?.url ?? '').isNotEmpty;

    final content = Container(
      constraints: const BoxConstraints(maxWidth: 210),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.panelBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border, width: 1.4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.article_outlined,
              size: 14, color: AppColors.textMuted),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              node.concept,
              // 제목은 개념어보다 길다. 두 줄에서 끊어 노드 크기가 튀지 않게 한다.
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11.5,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );

    if (!hasUrl) return content;

    return Tooltip(
      message: '기사 열기 — ${node.concept}',
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(onTap: _open, child: content),
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
        fill: AppColors.canvasBg,
        border: AppColors.textPrimary,
        text: AppColors.textPrimary,
        label: '이해완료',
      );
    case NodeState.notUnderstood:
      return const NodeStyle(
        fill: AppColors.pinkBg,
        border: AppColors.pinkStrong,
        text: AppColors.pink,
        label: '미이해',
      );
    default:
      // unknown 등 그 외 값: 아직 진단 전이라 추천 후보 풀에 그대로 속해 있는
      // 노드다(server/app/domain/thoughtmap/recommend.py 참고). 퀴즈 트리의
      // 선행 관계로만 들어온 개념도 여기 해당한다. 서버가 새 상태값을 보내와도
      // 렌더는 살아 있게 한다.
      return const NodeStyle(
        fill: AppColors.canvasBg,
        border: AppColors.gray,
        text: AppColors.gray,
        label: '추천 개념',
      );
  }
}

class _EmptyGraph extends StatelessWidget {
  const _EmptyGraph();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.hub_outlined, size: 56, color: AppColors.textMuted),
          const SizedBox(height: 16),
          Text('아직 생각 지도가 비어 있어요',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          const SizedBox(
            width: 340,
            child: Text(
              '크롬 익스텐션으로 기사를 읽고 진단을 마치면, '
              '"내 이력 가져오기"를 눌렀을 때 이곳에 개념이 쌓입니다.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
