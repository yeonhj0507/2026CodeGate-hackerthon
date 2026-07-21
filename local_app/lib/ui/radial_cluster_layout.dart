/// 기사 중심 방사형(radial) 레이아웃 — 기사별로 독립된 클러스터를 만든다.
///
/// 명세 §5.1 "뇌 지도"의 흐름을 그대로 지도에 담는다:
///   기사(중심) → level0(기사에서 바로 다룬 개념) → level1(그 개념의 선행) →
///   level2(선행의 선행) …
/// 안쪽 고리일수록 기사에 가깝고, 바깥으로 갈수록 더 근본적인 선행 개념이 온다.
///
/// **왜 커스텀 레이아웃인가.** 방사형 트리 배치는 (1) 엣지 방향을 그대로
/// 부모→자식으로 쓰고 (2) 여러 뿌리를 하나의 중심으로 모으는 것이 보통이다.
/// 우리는 (1) 선행 엣지가 `선행→후행`이라 방사 바깥 방향과 반대이고 (2) 기사가
/// 여러 개일 때 **기사마다 독립된 태양**이 되길 원한다. 그래서 여기서 좌표를
/// 직접 계산하고, 렌더러([ThoughtMapView])는 이 중심 좌표를 그대로 그린다.
///
/// 좌표는 노드 크기와 무관한 **중심 좌표**다. 노드는 이 좌표에 자기 중심을 맞춰
/// 배치되고(렌더러가 FractionalTranslation 으로 반너비만큼 당긴다), 엣지도
/// 중심에서 중심으로 잇는다 — 선은 불투명한 노드 상자에 가려 상자 가장자리에서
/// 나오는 것처럼 보인다.
library;

import 'dart:math';
import 'dart:ui';

import '../data/dto/graph.dart';
import 'article_nodes.dart';

/// 방사형 배치를 조절하는 상수. **여기 값만 만지면 지도 모양이 바뀐다.**
class RadialLayoutConfig {
  const RadialLayoutConfig({
    this.firstRingRadius = 170,
    this.ringGap = 130,
    this.clusterGap = 160,
    this.nodePadding = 130,
  });

  /// 기사 중심에서 level0 고리까지의 반지름.
  final double firstRingRadius;

  /// 고리와 고리(level n → level n+1) 사이 반지름 증가폭.
  final double ringGap;

  /// 클러스터(기사)와 클러스터 사이 여백.
  final double clusterGap;

  /// 클러스터 반지름·전체 경계를 잡을 때 노드 크기를 감안한 여유값(대략 반너비).
  final double nodePadding;
}

/// 계산 결과: 노드 id → 화면 중심 좌표, 그리고 전체 경계(줌 계산용).
class RadialLayout {
  const RadialLayout(this.centers, this.bounds);

  final Map<String, Offset> centers;
  final Rect bounds;

  bool get isEmpty => centers.isEmpty;

  /// 자동 배치 위에 **수동 위치**를 덮어씌운 새 레이아웃.
  ///
  /// [overrides] 는 노드 id → 사용자가 옮긴 중심 좌표다. 지금 그래프에 있는
  /// 노드만 반영하고(사라진 노드의 옛 좌표는 버린다), 경계도 옮긴 노드를 담게
  /// 다시 잡는다(줌 맞춤이 화면 밖으로 새지 않게).
  RadialLayout merged(Map<String, Offset> overrides) {
    if (overrides.isEmpty) return this;
    final next = Map<String, Offset>.of(centers);
    var changed = false;
    overrides.forEach((id, pos) {
      if (next.containsKey(id)) {
        next[id] = pos;
        changed = true;
      }
    });
    if (!changed) return this;

    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final c in next.values) {
      minX = min(minX, c.dx);
      minY = min(minY, c.dy);
      maxX = max(maxX, c.dx);
      maxY = max(maxY, c.dy);
    }
    // 원래 경계가 쥔 여백(nodePadding)을 그대로 유지한다.
    final pad = (bounds.left - centers.values.fold<double>(
            double.infinity, (m, c) => min(m, c.dx)))
        .abs();
    return RadialLayout(
      next,
      Rect.fromLTRB(minX - pad, minY - pad, maxX + pad, maxY + pad),
    );
  }
}

double _ringRadius(int ring, RadialLayoutConfig cfg) =>
    ring <= 0 ? 0 : cfg.firstRingRadius + (ring - 1) * cfg.ringGap;

/// [graph] (기사 노드·source 엣지가 이미 섞인 그래프)로부터 방사형 좌표를 만든다.
///
/// 순수 함수다 — 같은 그래프면 항상 같은 좌표가 나와야 한다(드래그·리빌드로
/// 레이아웃이 다시 돌아도 노드가 튀지 않게).
RadialLayout computeRadialLayout(
  Graph graph, [
  RadialLayoutConfig cfg = const RadialLayoutConfig(),
]) {
  if (graph.nodes.isEmpty) return const RadialLayout({}, Rect.zero);

  final isConcept = <String, bool>{
    for (final n in graph.nodes) n.id: !isArticleNodeId(n.id),
  };
  // 기사는 id 순으로 고정 정렬 — 배치가 빌드마다 흔들리지 않게.
  final articleIds = [
    for (final n in graph.nodes)
      if (isArticleNodeId(n.id)) n.id
  ]..sort();

  // 바깥 방향 자식 관계 두 종류.
  //  - 기사 → level0 개념: source 엣지(from=기사, to=개념).
  //  - 개념 → 그 선행: 선행 엣지(from=선행, to=후행)를 **뒤집어** 후행→선행으로 본다.
  final level0Of = <String, List<String>>{};
  final prereqsOf = <String, List<String>>{};
  for (final e in graph.edges) {
    if (e.type == articleEdgeType) {
      (level0Of[e.from] ??= []).add(e.to);
    } else if (e.type == EdgeType.prereq) {
      (prereqsOf[e.to] ??= []).add(e.from);
    }
  }

  final assigned = <String>{};
  final cluster = <String, String>{}; // conceptId → articleId
  final ring = <String, int>{}; // 노드 → 기사 중심으로부터의 고리 번호(기사=0)
  final children = <String, List<String>>{}; // 부모 → 바깥쪽 자식들(트리)

  // 기사마다 BFS. 개념은 **먼저 도달한 기사**에 한 번만 속한다(크로스기사 개념 중복 방지).
  for (final a in articleIds) {
    ring[a] = 0;
    cluster[a] = a;
    children[a] ??= [];

    final queue = <String>[];
    for (final c in (level0Of[a] ?? const [])) {
      if (isConcept[c] != true || assigned.contains(c)) continue;
      assigned.add(c);
      cluster[c] = a;
      ring[c] = 1;
      children[a]!.add(c);
      children[c] ??= [];
      queue.add(c);
    }
    for (var i = 0; i < queue.length; i++) {
      final n = queue[i];
      for (final p in (prereqsOf[n] ?? const [])) {
        if (isConcept[p] != true || assigned.contains(p)) continue;
        assigned.add(p);
        cluster[p] = a;
        ring[p] = ring[n]! + 1;
        (children[n] ??= []).add(p);
        children[p] ??= [];
        queue.add(p);
      }
    }
  }

  // 어느 기사에도 닿지 않은 개념(추천으로만 뜬 노드, 선행 사슬이 끊긴 노드 등).
  // **절대 버리지 않는다** — 별도 격자 클러스터로 모아 화면에 남긴다.
  final orphans = [
    for (final n in graph.nodes)
      if (isConcept[n.id] == true && !assigned.contains(n.id)) n.id
  ]..sort();

  // 클러스터별 노드 목록.
  final clusterNodes = <String, List<String>>{
    for (final a in articleIds) a: [a],
  };
  for (final entry in cluster.entries) {
    if (entry.key != entry.value) clusterNodes[entry.value]!.add(entry.key);
  }

  // 부분트리 잎(leaf) 수 — 자식에게 각도를 잎 수에 비례해 나눠 주기 위함.
  final leaves = <String, int>{};
  int countLeaves(String node) {
    final kids = children[node] ?? const [];
    if (kids.isEmpty) return leaves[node] = 1;
    var sum = 0;
    for (final k in kids) {
      sum += countLeaves(k);
    }
    return leaves[node] = sum;
  }

  // 클러스터 로컬 좌표(기사 중심을 원점으로).
  final localPos = <String, Offset>{};
  void place(String node, double a0, double a1) {
    final r = _ringRadius(ring[node]!, cfg);
    final mid = (a0 + a1) / 2;
    localPos[node] = r == 0 ? Offset.zero : Offset(r * cos(mid), r * sin(mid));
    final kids = children[node] ?? const [];
    if (kids.isEmpty) return;
    final total = leaves[node]!;
    var a = a0;
    for (final k in kids) {
      final span = (a1 - a0) * (leaves[k]! / total);
      place(k, a, a + span);
      a += span;
    }
  }

  final clusterRadius = <String, double>{};
  for (final a in articleIds) {
    countLeaves(a);
    // 뿌리(기사)에서 자식이 하나뿐이면 각도 전체를 쏟지 않고 위쪽 한 점에 몰리도록
    // -pi/2 를 기준으로 한 바퀴 돌린다(첫 개념이 12시 방향에서 시작).
    place(a, -pi / 2, 3 * pi / 2);
    var maxR = cfg.firstRingRadius;
    for (final n in clusterNodes[a]!) {
      maxR = max(maxR, localPos[n]!.distance);
    }
    clusterRadius[a] = maxR + cfg.nodePadding;
  }

  // 배치할 셀 목록: 기사 클러스터들 + (있으면) 고아 격자 하나.
  final cells = <String>[...articleIds];
  const orphanCellKey = '__orphans__';
  if (orphans.isNotEmpty) {
    // 고아들을 원점 기준 격자로 미리 배치(로컬 좌표).
    final cols = max(1, sqrt(orphans.length).ceil());
    const gap = 220.0;
    var oMaxR = cfg.firstRingRadius;
    for (var i = 0; i < orphans.length; i++) {
      final col = i % cols;
      final row = i ~/ cols;
      final p = Offset(col * gap, row * gap);
      localPos[orphans[i]] = p;
      oMaxR = max(oMaxR, p.distance);
    }
    // 격자 중심이 원점에 오도록 평행이동.
    final shift = Offset(((cols - 1) * gap) / 2,
        ((orphans.length - 1) ~/ cols) * gap / 2);
    for (final o in orphans) {
      localPos[o] = localPos[o]! - shift;
    }
    clusterNodes[orphanCellKey] = orphans;
    clusterRadius[orphanCellKey] = oMaxR + cfg.nodePadding;
    cells.add(orphanCellKey);
  }

  // 클러스터 격자 배치 — 셀 크기를 가장 큰 클러스터에 맞춰 균일하게.
  final maxRadius =
      cells.map((c) => clusterRadius[c]!).fold<double>(0, max);
  final cell = 2 * maxRadius + cfg.clusterGap;
  final cols = max(1, sqrt(cells.length).ceil());

  final centers = <String, Offset>{};
  for (var i = 0; i < cells.length; i++) {
    final col = i % cols;
    final row = i ~/ cols;
    final clusterCenter = Offset(col * cell + cell / 2, row * cell + cell / 2);
    for (final id in clusterNodes[cells[i]]!) {
      centers[id] = clusterCenter + localPos[id]!;
    }
  }

  // 경계(줌 계산용) — 노드 크기를 감안해 여유를 준다.
  var minX = double.infinity, minY = double.infinity;
  var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
  for (final c in centers.values) {
    minX = min(minX, c.dx);
    minY = min(minY, c.dy);
    maxX = max(maxX, c.dx);
    maxY = max(maxY, c.dy);
  }
  final pad = cfg.nodePadding;
  final bounds = Rect.fromLTRB(minX - pad, minY - pad, maxX + pad, maxY + pad);

  return RadialLayout(centers, bounds);
}
