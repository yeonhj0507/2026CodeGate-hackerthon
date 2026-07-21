import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphview/GraphView.dart' as gv;

import '../data/dto/graph.dart';
import '../providers/providers.dart';
import 'app_colors.dart';
import 'node_detail_card.dart';

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

class _ThoughtMapViewState extends ConsumerState<ThoughtMapView>
    with SingleTickerProviderStateMixin {
  // 노드 상세 카드가 팬·줌을 따라가려면 캔버스 변환 행렬을 직접 들고 있어야
  // 한다 — GraphViewController 에 넘기고 이 컨트롤러로 직접 구독한다.
  final _transformController = TransformationController();
  late final _controller =
      gv.GraphViewController(transformationController: _transformController);

  // graphview 패키지의 zoomToFit()은 뷰포트의 95%를 채우게 고정돼 있어 꽉 차
  // 보인다는 피드백을 받아, 우리가 직접 재구현해 여백을 더 준다. 애니메이션은
  // 패키지 내부 구현(GraphView.dart의 animateToMatrix)과 같은 방식으로 맞췄다.
  //
  // initState 에서 즉시 만든다 — late 필드로 두면 그래프가 계속 비어 있어
  // _zoomToFit 이 한 번도 안 불린 채 dispose 될 때 거기서 처음 생성되면서
  // "deactivated widget" 에러가 난다.
  late final AnimationController _panController;
  Animation<Matrix4>? _panAnimation;

  @override
  void initState() {
    super.initState();
    _panController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
  }

  /// 마지막으로 화면에 맞춘 그래프의 모양. 노드·엣지 구성이 바뀔 때만 다시 맞춘다.
  /// 매 빌드마다 맞추면 사용자가 확대해 둔 상태를 빼앗는다.
  String? _fittedShape;

  /// [_NodeDetailOverlay]가 선택된 노드의 레이아웃 좌표를 찾을 수 있게 마지막
  /// build 의 노드 맵을 들고 있는다. 노드 위치는 레이아웃 시점에 고정되고
  /// 팬·줌만 바뀌므로, 선택이 바뀔 때마다 그래프를 다시 만들 필요는 없다.
  ///
  /// [_transformController]는 우리가 만들었지만 dispose는 하지 않는다 —
  /// GraphViewController 에 넘기고 나면 GraphView 내부(`_GraphViewState`)가
  /// 소유권을 가져가 자기 dispose 시점에 정리한다. 여기서 또 dispose 하면
  /// "used after being disposed" 로 죽는다.
  Map<String, gv.Node> _nodesById = const {};

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
      if (mounted) _zoomToFit();
    });
  }

  /// graphview 의 zoomToFit()과 같은 계산이지만 채움 비율을 낮춰(0.7) 화면에
  /// 여백을 더 남긴다. 노드 좌표는 [_nodesById]에서, 뷰포트 크기는 이 위젯
  /// 자신의 RenderBox 에서 얻는다.
  void _zoomToFit() {
    if (_nodesById.isEmpty) return;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    for (final node in _nodesById.values) {
      minX = math.min(minX, node.position.dx);
      minY = math.min(minY, node.position.dy);
      maxX = math.max(maxX, node.position.dx + node.size.width);
      maxY = math.max(maxY, node.position.dy + node.size.height);
    }
    final boundsWidth = maxX - minX;
    final boundsHeight = maxY - minY;
    if (boundsWidth <= 0 || boundsHeight <= 0) return;

    final vp = renderBox.size;
    const paddingFactor = 0.7;
    final scale = math.min(
      (vp.width / boundsWidth) * paddingFactor,
      (vp.height / boundsHeight) * paddingFactor,
    );

    final scaledWidth = boundsWidth * scale;
    final scaledHeight = boundsHeight * scale;
    final centerOffset = Offset(
      (vp.width - scaledWidth) / 2 - minX * scale,
      (vp.height - scaledHeight) / 2 - minY * scale,
    );

    final target = Matrix4.identity()
      ..translateByDouble(centerOffset.dx, centerOffset.dy, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);

    _panController.reset();
    _panAnimation =
        Matrix4Tween(begin: _transformController.value, end: target).animate(
      CurvedAnimation(parent: _panController, curve: Curves.linear),
    );
    _panAnimation!.addListener(_onPanTick);
    _panController.forward();
  }

  void _onPanTick() {
    final animation = _panAnimation;
    if (animation == null) return;
    _transformController.value = animation.value;
    if (!_panController.isAnimating) {
      animation.removeListener(_onPanTick);
      _panAnimation = null;
    }
  }

  @override
  void dispose() {
    _panController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final graph = widget.graph;
    if (graph.isEmpty) return const _EmptyGraph();

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
    _nodesById = nodesById;
    for (final e in graph.edges) {
      final from = nodesById[e.from];
      final to = nodesById[e.to];
      if (from == null || to == null) continue;
      gvGraph.addEdge(
        from,
        to,
        paint: Paint()
          ..color = e.type == EdgeType.prereq
              ? const Color(0xFFD9D2C8)
              : const Color(0xFFE8E2D8)
          ..strokeWidth = e.type == EdgeType.prereq ? 1.6 : 1.0
          ..style = PaintingStyle.stroke,
      );
    }

    final config = gv.SugiyamaConfiguration()
      ..nodeSeparation = 40
      ..levelSeparation = 70
      ..orientation = gv.SugiyamaConfiguration.ORIENTATION_TOP_BOTTOM
      ..addTriangleToEdge = false;

    final algorithm = gv.SugiyamaAlgorithm(config);
    Widget nodeBuilder(gv.Node gvNode) {
      final id = gvNode.key!.value as String;
      final node = graph.nodeById(id);
      if (node == null) return const SizedBox.shrink();
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
        Positioned.fill(
          child: _NodeDetailOverlay(
            graph: graph,
            nodesById: _nodesById,
            transformController: _transformController,
          ),
        ),
        Positioned(
          left: 0,
          bottom: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _SyncFab(),
              const SizedBox(height: 12),
              // 확대하다 길을 잃어도 한 번에 돌아올 수 있게 둔다. 자동 맞춤은
              // 그래프 모양이 바뀔 때만 돌기 때문에, 그 사이의 탈출구가 필요하다.
              _CanvasFab(
                tooltip: '전체 보기',
                heroTag: 'graph-fit',
                onPressed: _zoomToFit,
                icon: Icons.fit_screen_outlined,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 선택된 노드 옆에 뜨는 상세 카드.
///
/// 좌하단 고정이 아니라 **노드를 가리지 않는 자리**에 뜬다 — 오른쪽에 공간이
/// 있으면 오른쪽, 없으면 왼쪽. 팬·줌으로 캔버스가 움직이면 카드도 노드에
/// 딸려 가야 하므로, 레이아웃 좌표([gv.Node.position], 팬·줌과 무관하게
/// 고정)를 매 프레임 [transformController]의 현재 행렬로 변환해 화면 좌표를
/// 다시 구한다.
class _NodeDetailOverlay extends ConsumerWidget {
  const _NodeDetailOverlay({
    required this.graph,
    required this.nodesById,
    required this.transformController,
  });

  final Graph graph;
  final Map<String, gv.Node> nodesById;
  final TransformationController transformController;

  static const _cardWidth = 320.0;
  static const _cardMaxHeight = 420.0;
  static const _gap = 16.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(selectedNodeIdProvider);
    final node = selectedId == null ? null : graph.nodeById(selectedId);
    final gvNode = selectedId == null ? null : nodesById[selectedId];
    if (node == null || gvNode == null) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        return AnimatedBuilder(
          animation: transformController,
          builder: (context, _) {
            final viewport = constraints.biggest;
            final nodeRect = MatrixUtils.transformRect(
              transformController.value,
              gvNode.position & gvNode.size,
            );

            // 오른쪽에 카드가 들어갈 자리가 있으면 오른쪽에, 아니면 왼쪽에 —
            // 어느 쪽도 넉넉하지 않으면 더 넓은 쪽을 고른다.
            final spaceRight = viewport.width - nodeRect.right;
            final spaceLeft = nodeRect.left;
            final placeRight =
                spaceRight >= _cardWidth + _gap || spaceRight >= spaceLeft;
            final rawLeft = placeRight
                ? nodeRect.right + _gap
                : nodeRect.left - _gap - _cardWidth;
            final maxLeft = viewport.width - _cardWidth;
            final left = rawLeft < 0
                ? 0.0
                : (maxLeft > 0 && rawLeft > maxLeft ? maxLeft : rawLeft);

            final rawTop = nodeRect.center.dy - _cardMaxHeight / 2;
            final maxTop = viewport.height - _cardMaxHeight;
            final top = rawTop < 0
                ? 0.0
                : (maxTop > 0 && rawTop > maxTop ? maxTop : rawTop);

            return Stack(
              children: [
                Positioned(
                  left: left,
                  top: top,
                  child: NodeDetailCard(
                    node: node,
                    graph: graph,
                    onClose: () =>
                        ref.read(selectedNodeIdProvider.notifier).state = null,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// "내 이력 가져오기" — 아이콘만 남긴 버전. 마지막 동기화 시각은 라벨 대신
/// 툴팁으로 보여준다(Figma 좌하단 버튼 스택).
class _SyncFab extends ConsumerWidget {
  const _SyncFab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncControllerProvider);
    final synced = sync.lastSyncedAt;
    final message = synced == null
        ? '내 이력 가져오기'
        : '마지막 동기화 '
            '${synced.hour.toString().padLeft(2, '0')}:'
            '${synced.minute.toString().padLeft(2, '0')}';

    final style = nodeStyleOfState(NodeState.unknown);
    return Tooltip(
      message: message,
      child: FloatingActionButton.small(
        heroTag: 'graph-sync',
        backgroundColor: style.fill,
        foregroundColor: style.text,
        elevation: 1,
        shape: CircleBorder(side: BorderSide(color: style.border, width: 1.4)),
        onPressed: sync.inProgress
            ? null
            : () => ref.read(syncControllerProvider.notifier).sync(),
        child: sync.inProgress
            ? SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: style.text),
              )
            : const Icon(Icons.sync),
      ),
    );
  }
}

/// 캔버스 위에 뜨는 아이콘 버튼 공용 스타일 — "추천 개념"(모르는 노드) 카드와
/// 같은 톤(흰 배경·회색 테두리)으로 맞춘다.
class _CanvasFab extends StatelessWidget {
  const _CanvasFab({
    required this.tooltip,
    required this.heroTag,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final String heroTag;
  final VoidCallback? onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final style = nodeStyleOfState(NodeState.unknown);
    return Tooltip(
      message: tooltip,
      child: FloatingActionButton.small(
        heroTag: heroTag,
        backgroundColor: style.fill,
        foregroundColor: style.text,
        elevation: 1,
        shape: CircleBorder(side: BorderSide(color: style.border, width: 1.4)),
        onPressed: onPressed,
        child: Icon(icon),
      ),
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
        // 타원형 — 완전히 둥글게 잡아 실제 높이가 얼마든 알약 모양으로 보인다.
        borderRadius: BorderRadius.circular(999),
        // 평소엔 테두리를 안 보이게 투명으로만 둔다 — Border 자체를 null로
        // 빼면 두께만큼 박스 크기가 변해서 위 클래스 문서에 적힌 "선택돼도
        // 크기가 변하지 않게" 불변식이 깨지고 그래프가 튄다.
        border: Border.all(
          color: selected ? AppColors.pink : Colors.transparent,
          width: 1.8,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            node.concept,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
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
