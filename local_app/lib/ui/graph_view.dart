import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/dto/graph.dart';
import '../providers/providers.dart';
import 'app_colors.dart';
import 'article_nodes.dart';
import 'node_detail_card.dart';
import 'radial_cluster_layout.dart';

/// 생각 지도 시각화(명세 §5.1 "뇌 지도").
///
/// **기사 중심 방사형 레이아웃**을 쓴다(radial_cluster_layout.dart). 기사가
/// 클러스터의 중심에 오고, level0(기사에서 바로 다룬 개념)이 첫 고리, 그 선행
/// 개념이 바깥 고리로 감싼다. 좌표 계산은 [computeRadialLayout] 이 하고, 여기서는
/// 그 **중심 좌표**를 그대로 그린다.
///
/// **렌더는 graphview 없이 직접 한다.** 좌표를 우리가 이미 다 갖고 있어서
/// (`computeRadialLayout`), 캔버스는 `InteractiveViewer`(줌·팬) + `Stack`(노드) +
/// `CustomPaint`(엣지)면 충분하다. 이렇게 하면 노드 드래그·상세 오버레이·줌이
/// 전부 우리 손 안에 들어온다.
///
/// **노드는 손으로 옮길 수 있다.** 노드를 바로 끌면([_ConceptNode] 의 pan) 그
/// 위치가 [nodePositionsProvider] 에 실시간 반영되고, 놓는 순간 로컬 DB에 영구
/// 저장된다. 저장된 위치는 방사형 자동 배치 위에 덮어씌워진다([RadialLayout.merged]).
/// 빈 곳을 끌면 화면이 팬되고, 길게 눌러 끌면 "탐색" 키워드로 담기는 건 그대로다.
///
/// **기본 보기는 '최소 배율 고정' 맞춤이다.** 노드가 많아지면 전체를 다 담으려는
/// 맞춤은 배율을 극단적으로 낮춰 노드가 보이지 않을 만큼 작아진다. 그래서 기본
/// 진입 시에는 배율을 읽기 좋은 하한([_minZoomScale]) 아래로는 내리지 않고, 넘치는
/// 부분은 팬으로 둘러보게 한다([_zoomToFit]). 전체를 한눈에 보고 싶을 때는
/// 좌하단 '전체 보기' 버튼이 탈출구다.
class ThoughtMapView extends ConsumerStatefulWidget {
  const ThoughtMapView({super.key, required this.graph});

  final Graph graph;

  @override
  ConsumerState<ThoughtMapView> createState() => _ThoughtMapViewState();
}

class _ThoughtMapViewState extends ConsumerState<ThoughtMapView>
    with SingleTickerProviderStateMixin {
  // 캔버스 변환(줌·팬) 행렬. 노드 상세 오버레이가 이 행렬로 화면 좌표를 다시
  // 구하고, 화면 맞춤([_zoomToFit])이 이 값을 직접 세팅한다.
  //
  // **우리가 소유한다.** InteractiveViewer 는 외부에서 받은 컨트롤러를 dispose
  // 하지 않으므로 여기서 정리한다.
  final _transformController = TransformationController();

  // 화면 맞춤 애니메이션. initState 에서 즉시 만든다 — late 로 두면 그래프가
  // 계속 비어 _zoomToFit 이 한 번도 안 불린 채 dispose 될 때 거기서 처음
  // 생성되면서 "deactivated widget" 에러가 난다.
  late final AnimationController _panController;
  Animation<Matrix4>? _panAnimation;

  /// 마지막 build 의 (수동 위치까지 반영된) 레이아웃. 오버레이·줌·드래그 시작점이
  /// 이 좌표를 참조한다.
  RadialLayout _layout = const RadialLayout({}, Rect.zero);

  @override
  void initState() {
    super.initState();
    _panController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
  }

  @override
  void dispose() {
    _panController.dispose();
    _transformController.dispose();
    super.dispose();
  }

  /// 기본 진입 배율의 하한/상한([_zoomToFit] 참고).
  static const _minZoomScale = 0.55;
  static const _maxZoomScale = 1.1;

  /// 마지막으로 화면에 맞춘 그래프의 모양. 노드·엣지 구성이 바뀔 때만 다시 맞춘다.
  /// 매 빌드마다 맞추면 사용자가 확대해 둔 상태를 빼앗는다.
  String? _fittedShape;

  /// 방사형 좌표를 그래프 모양이 바뀔 때만 다시 계산하기 위한 캐시. 드래그로
  /// 수동 위치만 바뀔 때는 BFS를 다시 돌리지 않고 이 base 위에 덮어씌운다.
  String? _layoutShape;
  RadialLayout _baseLayout = const RadialLayout({}, Rect.zero);

  String _shapeOf(Graph g) => [
        for (final n in g.nodes) n.id,
        '|',
        for (final e in g.edges) '${e.from}>${e.to}',
      ].join(',');

  RadialLayout _baseLayoutFor(Graph g) {
    final shape = _shapeOf(g);
    if (shape != _layoutShape) {
      _layoutShape = shape;
      _baseLayout = computeRadialLayout(g);
    }
    return _baseLayout;
  }

  void _fitWhenShapeChanged(Graph g) {
    final shape = _shapeOf(g);
    if (shape == _fittedShape) return;
    _fittedShape = shape;
    // 레이아웃이 끝난 뒤라야 뷰포트 크기와 노드 좌표가 잡힌다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _zoomToFit();
    });
  }

  /// 그래프 전체를 화면에 맞춘다. 채움 비율을 낮춰(0.85) 여백을 남기고, 배율은
  /// 읽기 좋은 하한/상한 사이로 고정한다(방사형 클러스터가 많아지면 전체를
  /// 담으려는 배율이 극단적으로 낮아져 노드가 안 보이기 때문).
  void _zoomToFit() {
    final bounds = _layout.bounds;
    if (bounds.width <= 0 || bounds.height <= 0) return;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    final vp = renderBox.size;
    const paddingFactor = 0.85;
    final fit = math.min(
      (vp.width / bounds.width) * paddingFactor,
      (vp.height / bounds.height) * paddingFactor,
    );
    final scale = fit.clamp(_minZoomScale, _maxZoomScale);

    // 캔버스는 bounds.topLeft 를 원점(0,0)으로 그린다(build 참고). 그래서
    // minX/minY 항 없이 뷰포트 중앙에 배치하면 된다.
    final tx = (vp.width - bounds.width * scale) / 2;
    final ty = (vp.height - bounds.height * scale) / 2;
    final target = Matrix4.identity()
      ..translateByDouble(tx, ty, 0, 1)
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
  Widget build(BuildContext context) {
    if (widget.graph.isEmpty) return const _EmptyGraph();

    // 기사 노드는 화면에서만 존재한다. 저장·동기화되는 그래프는 그대로 둔다
    // (article_nodes.dart 주석 — 서버가 기사를 개념으로 착각하면 안 된다).
    final graph = withArticleNodes(widget.graph);

    // 자동 배치(캐시) 위에 사용자가 옮긴 수동 위치를 덮어씌운다.
    final overrides = ref.watch(nodePositionsProvider);
    final layout = _baseLayoutFor(graph).merged(overrides);
    _layout = layout;

    _fitWhenShapeChanged(graph);

    // 선택 상태는 일부러 여기서 watch하지 않는다. 여기서 watch하면 노드를 고를
    // 때마다 그래프 전체가 다시 만들어지고 레이아웃이 튄다. 선택 표시는
    // [_ConceptNode]가, 상세 카드는 [_NodeDetailOverlay]가 스스로 구독한다.

    final origin = layout.bounds.topLeft;
    final canvasSize = layout.bounds.size;

    // 엣지 — 중심에서 중심으로 잇는다(선은 불투명한 노드에 가려 상자 가장자리에서
    // 나오는 것처럼 보인다). 가리키는 노드가 실제로 있을 때만 그린다.
    final lines = <_EdgeLine>[];
    for (final e in graph.edges) {
      final a = layout.centers[e.from];
      final b = layout.centers[e.to];
      if (a == null || b == null) continue;
      // 기사→개념 줄은 개념 사이의 관계선보다 연하게.
      final isSource = e.type == articleEdgeType;
      final color = isSource
          ? AppColors.pinkMuted.withValues(alpha: 0.45)
          : e.type == EdgeType.prereq
              ? const Color(0xFFD9D2C8)
              : const Color(0xFFE8E2D8);
      final width = isSource
          ? 1.0
          : e.type == EdgeType.prereq
              ? 1.6
              : 1.0;
      lines.add(_EdgeLine(a - origin, b - origin, color, width));
    }

    // 노드 — 중심 좌표에 FractionalTranslation 으로 자기 중심을 맞춘다(노드 크기를
    // 몰라도 정확히 중앙에 온다).
    final nodeWidgets = <Widget>[];
    for (final node in graph.nodes) {
      final center = layout.centers[node.id];
      if (center == null) continue;
      final p = center - origin;
      nodeWidgets.add(Positioned(
        left: p.dx,
        top: p.dy,
        child: FractionalTranslation(
          translation: const Offset(-0.5, -0.5),
          child: isArticleNodeId(node.id)
              ? _ArticleNode(node: node, center: center)
              : _ConceptNode(node: node, center: center),
        ),
      ));
    }

    return Stack(
      children: [
        Positioned.fill(
          child: InteractiveViewer(
            transformationController: _transformController,
            constrained: false,
            // 노드 위 드래그는 노드의 pan 이 제스처 아레나에서 이겨(빈 곳에서만
            // 캔버스가 팬된다), panEnabled 를 따로 끄지 않아도 배경이 안 딸려온다.
            boundaryMargin: const EdgeInsets.all(double.infinity),
            minScale: 0.05,
            maxScale: 4,
            child: SizedBox(
              width: canvasSize.width,
              height: canvasSize.height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: _EdgePainter(lines)),
                  ),
                  ...nodeWidgets,
                ],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: _NodeDetailOverlay(
            graph: graph,
            centers: layout.centers,
            origin: origin,
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

/// 엣지를 중심-중심 직선으로 그리는 페인터. 노드 뒤에 깔린다.
class _EdgeLine {
  const _EdgeLine(this.a, this.b, this.color, this.strokeWidth);

  final Offset a;
  final Offset b;
  final Color color;
  final double strokeWidth;
}

class _EdgePainter extends CustomPainter {
  const _EdgePainter(this.lines);

  final List<_EdgeLine> lines;

  @override
  void paint(Canvas canvas, Size size) {
    for (final l in lines) {
      canvas.drawLine(
        l.a,
        l.b,
        Paint()
          ..color = l.color
          ..strokeWidth = l.strokeWidth
          ..style = PaintingStyle.stroke
          ..isAntiAlias = true,
      );
    }
  }

  // build 마다 새 리스트가 오므로(수동 위치·그래프 변경 시) 그때 다시 그린다.
  // 팬·줌은 부모 Transform 이 합성으로 처리하므로 여기선 다시 그릴 필요가 없다.
  @override
  bool shouldRepaint(_EdgePainter old) => !identical(old.lines, lines);
}

/// 선택된 노드 옆에 뜨는 상세 카드.
///
/// 좌하단 고정이 아니라 **노드를 가리지 않는 자리**에 뜬다 — 오른쪽에 공간이
/// 있으면 오른쪽, 없으면 왼쪽. 팬·줌으로 캔버스가 움직이면 카드도 노드에
/// 딸려 가야 하므로, 노드의 중심 좌표(팬·줌과 무관하게 고정)를 매 프레임
/// [transformController]의 현재 행렬로 변환해 화면 좌표를 다시 구한다.
///
/// 노드의 정확한 크기는 측정하지 않고 넉넉히 어림한다([_nodeHalfW]/[_nodeHalfH]) —
/// 카드가 노드를 안 덮고 옆에 서기만 하면 되므로 이 정도면 충분하다.
class _NodeDetailOverlay extends ConsumerWidget {
  const _NodeDetailOverlay({
    required this.graph,
    required this.centers,
    required this.origin,
    required this.transformController,
  });

  final Graph graph;
  final Map<String, Offset> centers;
  final Offset origin;
  final TransformationController transformController;

  static const _cardWidth = 320.0;
  static const _cardMaxHeight = 420.0;
  static const _gap = 16.0;
  static const _nodeHalfW = 95.0;
  static const _nodeHalfH = 22.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(selectedNodeIdProvider);
    // 기사 노드는 개념이 아니다 — 눌러도 개념 상세를 띄우지 않는다.
    if (selectedId == null || isArticleNodeId(selectedId)) {
      return const SizedBox.shrink();
    }
    final node = graph.nodeById(selectedId);
    final center = centers[selectedId];
    if (node == null || center == null) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        return AnimatedBuilder(
          animation: transformController,
          builder: (context, _) {
            final viewport = constraints.biggest;
            final m = transformController.value;
            final scale = m.getMaxScaleOnAxis();
            final screenCenter =
                MatrixUtils.transformPoint(m, center - origin);
            final nodeRect = Rect.fromCenter(
              center: screenCenter,
              width: _nodeHalfW * 2 * scale,
              height: _nodeHalfH * 2 * scale,
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
                child:
                    CircularProgressIndicator(strokeWidth: 2, color: style.text),
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

/// 그래프 노드 하나. 색으로 이해상태를, 모양으로 선행개념 여부를 나타낸다.
///
/// 선택 여부를 자기가 구독하되, **선택돼도 크기가 변하지 않게** 만든다 — 테두리
/// 두께를 고정하고 색과 그림자로만 선택을 표시한다.
///
/// 제스처가 세 갈래다:
///   - **탭** — 노드를 선택한다(상세 카드).
///   - **바로 끌기(pan)** — 노드를 지도 위에서 옮긴다. 실시간으로
///     [nodePositionsProvider]에 반영되고, 놓으면 영구 저장된다.
///   - **길게 눌러 끌기** — "탐색" 탭의 키워드로 담긴다([LongPressDraggable]).
/// 바로 끌기는 즉시 움직임으로 승부가 나고, 가만히 눌러 있으면 롱프레스가
/// 이겨서 탐색 드래그가 시작된다 — 둘은 자연히 갈린다.
class _ConceptNode extends ConsumerStatefulWidget {
  const _ConceptNode({required this.node, required this.center});

  final GraphNode node;

  /// 이 노드의 현재 중심(절대 좌표). 드래그 시작점으로 삼는다.
  final Offset center;

  @override
  ConsumerState<_ConceptNode> createState() => _ConceptNodeState();
}

class _ConceptNodeState extends ConsumerState<_ConceptNode> {
  /// 드래그 중 누적되는 중심 좌표(절대). 리빌드로 widget.center 가 갱신돼도
  /// 우리 누적값을 기준으로 이어 간다.
  Offset? _dragCenter;

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
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
        ],
      ),
    );

    final positions = ref.read(nodePositionsProvider.notifier);

    return LongPressDraggable<String>(
      data: node.id,
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
        behavior: HitTestBehavior.opaque,
        onTap: () => ref.read(selectedNodeIdProvider.notifier).state =
            selected ? null : node.id,
        onPanStart: (_) => _dragCenter = widget.center,
        onPanUpdate: (details) {
          // details.delta 는 변환된 캔버스 안이라 이미 레이아웃 좌표계다
          // (스케일 보정 불필요). 절대 중심에 그대로 더한다.
          final next = (_dragCenter ?? widget.center) + details.delta;
          _dragCenter = next;
          positions.drag(node.id, next);
        },
        onPanEnd: (_) {
          positions.commit(node.id);
          _dragCenter = null;
        },
        onPanCancel: () {
          if (_dragCenter != null) {
            positions.commit(node.id);
            _dragCenter = null;
          }
        },
        child: content,
      ),
    );
  }
}

/// 기사 노드. 개념 노드와 **다르게 생겨야 한다** — 이해 대상이 아니기 때문이다.
///
/// 개념 노드와 다른 점:
///   - 선택되지 않는다. 상세 패널은 개념을 설명하는 자리다.
///   - 탐색 탭으로 끌어다 놓을 수 없다. 기사는 개념이 아니라 키워드가 못 된다.
///   - 탭하면 기사가 브라우저에서 열린다(URL 이 있을 때만).
/// 반면 **바로 끌면 개념 노드처럼 지도 위에서 옮겨진다**(위치 영구 저장).
class _ArticleNode extends ConsumerStatefulWidget {
  const _ArticleNode({required this.node, required this.center});

  final GraphNode node;

  /// 이 노드의 현재 중심(절대 좌표). 드래그 시작점으로 삼는다.
  final Offset center;

  @override
  ConsumerState<_ArticleNode> createState() => _ArticleNodeState();
}

class _ArticleNodeState extends ConsumerState<_ArticleNode> {
  /// 드래그 중 누적되는 중심 좌표(절대). [_ConceptNodeState] 와 같은 방식.
  Offset? _dragCenter;

  SourceArticle? get _article => widget.node.sourceArticles.isEmpty
      ? null
      : widget.node.sourceArticles.first;

  Future<void> _open() async {
    final url = _article?.url ?? '';
    final uri = Uri.tryParse(url);
    if (url.isEmpty || uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final hasUrl = (_article?.url ?? '').isNotEmpty;
    final positions = ref.read(nodePositionsProvider.notifier);

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

    // 제스처(탭=열기, 바로 끌기=이동)를 가장 안쪽에 둔다. Tooltip 을 제스처
    // 안에 넣으면 Tooltip 이 얹는 롱프레스 인식기가 pan 승부에 끼어들어
    // 드래그가 씹힌다 — 그래서 Tooltip 은 바깥으로 뺀다.
    final interactive = MouseRegion(
      cursor: hasUrl ? SystemMouseCursors.click : SystemMouseCursors.grab,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: hasUrl ? _open : null,
        onPanStart: (_) => _dragCenter = widget.center,
        onPanUpdate: (details) {
          final next = (_dragCenter ?? widget.center) + details.delta;
          _dragCenter = next;
          positions.drag(node.id, next);
        },
        onPanEnd: (_) {
          positions.commit(node.id);
          _dragCenter = null;
        },
        onPanCancel: () {
          if (_dragCenter != null) {
            positions.commit(node.id);
            _dragCenter = null;
          }
        },
        child: content,
      ),
    );

    if (!hasUrl) return interactive;
    return Tooltip(
      message: '기사 열기 — ${node.concept}',
      waitDuration: const Duration(milliseconds: 400),
      child: interactive,
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
