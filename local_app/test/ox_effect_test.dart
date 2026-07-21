import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prober_local/data/api/mock_api_client.dart';
import 'package:prober_local/data/db/database.dart';
import 'package:prober_local/data/dto/graph.dart';
import 'package:prober_local/data/repository/thoughtmap_repository.dart';

/// O/X 를 맞히면 **실제로 무언가 바뀌어야 한다.**
///
/// 처음엔 O/X 카드가 화면만 바꾸고 끝났다 — 정답을 맞혀도 노드는 미이해 그대로였고
/// XP도 0이었다. 화면에 "정답이에요"가 뜨니 테스트도 통과했다. 그래서 여기서는
/// 표시가 아니라 **상태와 적립**을 본다.
void main() {
  late AppDatabase db;
  late ThoughtmapRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = ThoughtmapRepository(api: MockApiClient(), db: db);
  });

  tearDown(() => db.close());

  const quiz = OxQuiz(statement: '틀렸던 진술', answer: false);

  /// 선행(이해완료) → 후행(미이해) 한 쌍.
  Future<void> seed({String followerState = NodeState.notUnderstood}) {
    return db.replaceGraph(Graph(
      nodes: [
        const GraphNode(
          id: 'prereq',
          concept: '환헤지',
          state: NodeState.understood,
          isPrereq: true,
        ),
        GraphNode(
          id: 'target',
          concept: 'NDF의 환율 전가 경로',
          state: followerState,
          isPrereq: false,
          oxQuiz: quiz,
        ),
      ],
      edges: const [
        GraphEdge(from: 'prereq', to: 'target', type: EdgeType.prereq),
      ],
    ));
  }

  test('맞히면 그 개념이 이해완료로 올라간다', () async {
    await seed();
    expect((await db.loadGraph()).nodeById('target')!.isNotUnderstood, isTrue);

    await repo.markUnderstoodByOxQuiz('target');

    expect((await db.loadGraph()).nodeById('target')!.isUnderstood, isTrue);
  });

  test('XP가 실제로 적립된다', () async {
    await seed();
    expect((await repo.loadXp()).total, 0);

    final granted = await repo.markUnderstoodByOxQuiz('target');

    expect(granted, isNotEmpty);
    expect((await repo.loadXp()).total, greaterThan(0));
  });

  test('선행을 이미 이해했으면 재도전 성공으로 친다', () async {
    // 동기화 경로와 같은 규칙(evaluateGraphXp)을 타는지 확인한다.
    await seed();
    final granted = await repo.markUnderstoodByOxQuiz('target');

    expect(granted.map((e) => e.kindName), contains('retrySuccess'));
  });

  test('두 번 맞혀도 XP는 한 번만 — 나중 동기화와도 중복되지 않는다', () async {
    await seed();
    final first = await repo.markUnderstoodByOxQuiz('target');
    expect(first, isNotEmpty);

    // 되돌린 뒤 다시 맞혀도 같은 dedupeKey 라 지급되지 않는다.
    await db.setNodeState('target', NodeState.notUnderstood);
    final second = await repo.markUnderstoodByOxQuiz('target');

    expect(second, isEmpty, reason: '같은 노드의 이해 전환은 평생 한 번만 지급한다');
  });

  test('이미 이해완료인 개념은 아무 일도 하지 않는다', () async {
    await seed(followerState: NodeState.understood);

    final granted = await repo.markUnderstoodByOxQuiz('target');

    expect(granted, isEmpty);
    expect((await repo.loadXp()).total, 0);
  });

  test('없는 노드를 가리켜도 깨지지 않는다', () async {
    await seed();
    expect(await repo.markUnderstoodByOxQuiz('없음'), isEmpty);
  });

  test('바뀐 상태는 서버로 올라갈 그래프에 실린다', () async {
    // 서버 merge.py 는 클라이언트 그래프로 노드를 채운 뒤 이번 스크랩에 등장한
    // 개념만 상태를 덮는다. 즉 올려 보내기만 하면 되돌아오지 않는다.
    await seed();
    await repo.markUnderstoodByOxQuiz('target');

    final toUpload = await repo.loadLocalGraph();
    expect(toUpload.nodeById('target')!.isUnderstood, isTrue);
  });
}
