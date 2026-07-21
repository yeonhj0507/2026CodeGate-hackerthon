import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/dto/graph.dart';
import '../data/dto/recommendation.dart';
import 'explore_panel.dart';
import 'library_panel.dart';
import 'recommendation_panel.dart';

/// 우측 패널의 3탭 — 추천 / 탐색 / 보관함.
///
/// 좌측 생각 지도는 그대로 두고 이 패널만 갈아 끼운다. 세 탭이 하는 일이 다르다.
///   추천  — 서버가 골라 준 것을 본다 (모를 법한 개념 · 확장 · 기사)
///   탐색  — 내가 고른 키워드를 묶어 물어본다
///   보관함 — 지금까지 읽은 것을 되짚는다 (로컬 전용)
///
/// 추천 탭의 목록↔상세 전환은 [RecommendationPanel]이 스스로 한다
/// (`inlineConceptDetailProvider`). 여기서 화면을 갈아 끼우면 상세를 여는 순간
/// 탭 전체가 바뀌어 버려, 패널이 다른 탭으로 넘어간 것처럼 보인다.
class SideTabs extends ConsumerStatefulWidget {
  const SideTabs({
    super.key,
    required this.graph,
    required this.recommendations,
  });

  final Graph graph;
  final Recommendations recommendations;

  @override
  ConsumerState<SideTabs> createState() => _SideTabsState();
}

class _SideTabsState extends ConsumerState<SideTabs>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        TabBar(
          controller: _tabs,
          labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          unselectedLabelColor: scheme.outline,
          tabs: const [
            Tab(text: '추천'),
            Tab(text: '탐색'),
            Tab(text: '보관함'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              RecommendationPanel(
                recommendations: widget.recommendations,
                graph: widget.graph,
              ),
              ExplorePanel(graph: widget.graph),
              const LibraryPanel(),
            ],
          ),
        ),
      ],
    );
  }
}
