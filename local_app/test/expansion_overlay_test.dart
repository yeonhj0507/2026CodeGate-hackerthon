import 'package:flutter_test/flutter_test.dart';
import 'package:prober_local/data/dto/graph.dart';
import 'package:prober_local/data/dto/recommendation.dart';
import 'package:prober_local/ui/expansion_overlay.dart';

/// 확장 후보를 지도에 임시로 얹는 규칙.
///
/// 표시용 그래프만 만들고 로컬 DB 는 건드리지 않는다 — 그래서 이 함수는 순수하다.
/// 원본 그래프가 그대로 남는지까지 본다(추천이 학습 데이터를 오염시키면 안 된다).
void main() {
  const mine = Graph(
    nodes: [
      GraphNode(
        id: '환헤지',
        concept: '환헤지',
        state: NodeState.understood,
        isPrereq: false,
      ),
      GraphNode(
        id: '환투기',
        concept: '환투기',
        state: NodeState.understood,
        isPrereq: false,
      ),
    ],
  );

  const leverage = ExpansionRecommendation(
    conceptId: '레버리지',
    conceptTag: '레버리지',
    viaConcepts: ['환헤지', '환투기'],
  );

  test('후보가 회색 임시 노드로 들어온다', () {
    final out = withExpansionCandidates(mine, [leverage]);

    final added = out.nodeById('레버리지')!;
    expect(added.concept, '레버리지');
    // unknown 이라 회색("추천 개념")으로 그려지고 이해완료/미이해 집계에도 안 잡힌다.
    expect(added.state, NodeState.unknown);
    expect(added.isUnderstood, isFalse);
    expect(added.isNotUnderstood, isFalse);
  });

  test('근거가 된 내 개념마다 선으로 이어진다', () {
    final out = withExpansionCandidates(mine, [leverage]);

    final links = out.edges.where((e) => e.to == '레버리지').toList();
    expect(links.map((e) => e.from), containsAll(['환헤지', '환투기']));
    // 선행 관계가 아니라 곁가지다 — 옅게 그려지도록 related 를 쓴다.
    expect(links.every((e) => e.type == EdgeType.related), isTrue);
  });

  test('원본 그래프는 그대로다', () {
    final before = mine.nodes.length;
    withExpansionCandidates(mine, [leverage]);

    expect(mine.nodes.length, before);
    expect(mine.edges, isEmpty);
  });

  test('후보가 없으면 그래프를 그대로 돌려준다', () {
    expect(identical(withExpansionCandidates(mine, const []), mine), isTrue);
  });

  test('그 사이 동기화로 이미 들어온 개념은 다시 넣지 않는다', () {
    const already = Graph(nodes: [
      GraphNode(
        id: '레버리지',
        concept: '레버리지',
        state: NodeState.understood,
        isPrereq: false,
      ),
    ]);

    final out = withExpansionCandidates(already, [leverage]);

    expect(out.nodes.where((n) => n.id == '레버리지'), hasLength(1));
    expect(out.nodeById('레버리지')!.state, NodeState.understood,
        reason: '이미 아는 개념을 추천 후보로 덮어쓰면 안 된다');
  });

  test('그래프에 없는 근거로는 선을 긋지 않는다', () {
    const orphan = ExpansionRecommendation(
      conceptId: '기축통화',
      conceptTag: '기축통화',
      viaConcepts: ['원화 국제화'], // 내 그래프에 없다
    );

    final out = withExpansionCandidates(mine, [orphan]);

    expect(out.nodeById('기축통화'), isNotNull, reason: '노드는 그린다');
    expect(out.edges, isEmpty, reason: '이을 곳이 없으면 선은 긋지 않는다');
  });
}
