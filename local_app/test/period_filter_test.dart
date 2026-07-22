import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prober_local/data/db/database.dart';
import 'package:prober_local/data/dto/graph.dart';
import 'package:prober_local/providers/providers.dart';

/// 기간 필터 — 개념을 **처음 배운 날**(first-seen) 기준으로 최근 것만 남긴다.
void main() {
  final now = DateTime.utc(2026, 7, 22, 12);

  Graph graphWith(List<String> ids) => Graph(
        nodes: [
          for (final id in ids)
            GraphNode(
                id: id,
                concept: id,
                state: NodeState.understood,
                isPrereq: false),
        ],
        edges: const [
          GraphEdge(from: '실질금리', to: '기준금리', type: EdgeType.prereq),
        ],
      );

  group('filterGraphByPeriod', () {
    test('창이 null(전체)이면 원본을 그대로 돌려준다', () {
      final g = graphWith(['실질금리', '기준금리']);
      final out = filterGraphByPeriod(g, const {}, null, now: now);
      expect(identical(out, g), isTrue);
    });

    test('창 안에 처음 배운 개념만 남고, 끊긴 엣지는 버린다', () {
      final g = graphWith(['실질금리', '기준금리']);
      final firstSeen = {
        '실질금리': now.subtract(const Duration(days: 2)), // 최근
        '기준금리': now.subtract(const Duration(days: 40)), // 오래됨
      };

      final out = filterGraphByPeriod(
          g, firstSeen, const Duration(days: 7), now: now);

      expect(out.nodes.map((n) => n.id), ['실질금리']);
      // 기준금리가 빠졌으니 실질금리→기준금리 엣지도 사라진다.
      expect(out.edges, isEmpty);
    });

    test('시간 정보가 없는 노드(추천·기사 등)는 최근 창에서 빠진다', () {
      final g = graphWith(['실질금리', '추천개념']);
      final firstSeen = {'실질금리': now.subtract(const Duration(days: 1))};

      final out = filterGraphByPeriod(
          g, firstSeen, const Duration(days: 7), now: now);

      expect(out.nodes.map((n) => n.id), ['실질금리']);
    });

    test('전부 창 안이면 원본을 그대로 돌려준다(불필요한 복제 없음)', () {
      final g = graphWith(['실질금리', '기준금리']);
      final firstSeen = {
        '실질금리': now.subtract(const Duration(days: 1)),
        '기준금리': now.subtract(const Duration(days: 3)),
      };
      final out = filterGraphByPeriod(
          g, firstSeen, const Duration(days: 7), now: now);
      expect(identical(out, g), isTrue);
    });
  });

  group('loadConceptFirstSeen', () {
    test('같은 개념의 여러 이력 중 가장 이른 시각을 돌려준다', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      // 같은 개념이 두 번(동기화 두 번) 기록됐다 — min 이 나와야 한다.
      final early = now.subtract(const Duration(days: 30));
      final late = now.subtract(const Duration(days: 1));
      await db.recordSyncOutcome(Graph(nodes: [
        GraphNode(
            id: 'c1',
            concept: '실질금리',
            state: NodeState.understood,
            isPrereq: false),
      ]));
      // 두 번째 기록을 직접 넣어 서로 다른 시각을 만든다.
      await db.into(db.learningHistories).insert(
            LearningHistoriesCompanion.insert(
              conceptTag: '실질금리',
              correct: true,
              occurredAt: early,
            ),
          );
      await db.into(db.learningHistories).insert(
            LearningHistoriesCompanion.insert(
              conceptTag: '실질금리',
              correct: true,
              occurredAt: late,
            ),
          );

      final firstSeen = await db.loadConceptFirstSeen();
      // drift 가 로컬 시각으로 돌려줘도 같은 순간이면 된다(isUtc 플래그 무시).
      expect(firstSeen['실질금리']!.toUtc(), early);
    });
  });
}
