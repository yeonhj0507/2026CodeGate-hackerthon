/// 방사형 뇌 지도 미리보기(개발용 독립 실행 진입점).
///
/// 실제 DB·로그인·동기화를 전부 건너뛰고, 더미 그래프로 기사 클러스터를 여러 개
/// 띄운다. 클러스터 개수와 가지(level0/1/2) 수를 화면에서 바꿔 가며 방사형 배치와
/// 기본 배율을 눈으로 튜닝하기 위한 화면이다.
///
/// 실행:
///   flutter run -t lib/dev/radial_preview.dart -d windows
///
/// 배치가 마음에 들 때까지 여기서 조절한 뒤, 값은 radial_cluster_layout.dart 의
/// [RadialLayoutConfig] 와 graph_view.dart 의 배율 상수에 반영하면 된다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/app_colors.dart';
import '../ui/graph_view.dart';
import 'dummy_graph.dart';

void main() => runApp(const ProviderScope(child: _PreviewApp()));

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '방사형 지도 미리보기',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.canvasBg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.pink,
          brightness: Brightness.light,
        ),
      ),
      home: const _PreviewPage(),
    );
  }
}

class _PreviewPage extends StatefulWidget {
  const _PreviewPage();

  @override
  State<_PreviewPage> createState() => _PreviewPageState();
}

class _PreviewPageState extends State<_PreviewPage> {
  int _articles = 4;
  int _l0 = 3;
  int _l1 = 2;
  int _l2 = 1;

  @override
  Widget build(BuildContext context) {
    final graph = buildDummyGraph(
      articles: _articles,
      level0PerArticle: _l0,
      level1PerLevel0: _l1,
      level2PerLevel1: _l2,
    );

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _controls(graph.nodes.length),
            const Divider(height: 1),
            Expanded(
              child: ThoughtMapView(
                // 구성이 바뀌면 위젯을 새로 만들어 배율 맞춤을 다시 돌린다.
                key: ValueKey('$_articles-$_l0-$_l1-$_l2'),
                graph: graph,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _controls(int conceptCount) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Wrap(
        spacing: 20,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _stepper('기사(클러스터)', _articles, 1, 12,
              (v) => setState(() => _articles = v)),
          _stepper('level0 / 기사', _l0, 1, 6, (v) => setState(() => _l0 = v)),
          _stepper('level1 / level0', _l1, 0, 4, (v) => setState(() => _l1 = v)),
          _stepper('level2 / level1', _l2, 0, 3, (v) => setState(() => _l2 = v)),
          Text('개념 $conceptCount개',
              style: const TextStyle(
                  color: AppColors.textMuted, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _stepper(
      String label, int value, int lo, int hi, ValueChanged<int> onChanged) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: value > lo ? () => onChanged(value - 1) : null,
              icon: const Icon(Icons.remove_circle_outline, size: 20),
            ),
            SizedBox(
              width: 20,
              child: Text('$value',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary)),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: value < hi ? () => onChanged(value + 1) : null,
              icon: const Icon(Icons.add_circle_outline, size: 20),
            ),
          ],
        ),
      ],
    );
  }
}
