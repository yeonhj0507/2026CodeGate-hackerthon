import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prober_local/data/db/database.dart';
import 'package:prober_local/data/dto/graph.dart';
import 'package:prober_local/data/dto/recommendation.dart';
import 'package:prober_local/providers/providers.dart';
import 'package:prober_local/ui/recommendation_panel.dart';

/// 추천 탭의 **인라인 개념 상세**와 O/X.
///
/// O/X 문항은 서버가 사용자의 실제 오답 선지를 그대로 진술문으로 만들어 준 것이다
/// (LLM 호출 없음 — server `merge.py:_attach_ox_quiz`). 그래서 이 화면은 픽스처가
/// 아니라 **노드에 실려 온 `oxQuiz`**를 그려야 한다. 여기가 어긋나면 O/X 가 실제
/// 학습 이력과 무관한 내용을 보여주게 된다.
void main() {
  const graph = Graph(
    nodes: [
      GraphNode(
        id: 'c_전가',
        concept: 'NDF의 환율 전가 경로',
        state: NodeState.notUnderstood,
        isPrereq: false,
        summaryMeta: 'NDF 거래가 현물 환율을 밀어 올리는 경로를 말한다.',
        oxQuiz: OxQuiz(
          statement: 'NDF 거래는 계약대로 달러가 오가서 통화 가치에 영향이 없다',
          answer: false,
          sourceQuestion: '차액만 정산하는 NDF 가 환율을 흔드는 경로는?',
        ),
      ),
      GraphNode(
        id: 'c_환헤지',
        concept: '환헤지',
        state: NodeState.understood,
        isPrereq: true,
      ),
    ],
    edges: [GraphEdge(from: 'c_환헤지', to: 'c_전가', type: EdgeType.prereq)],
  );

  const recs = Recommendations(
    gapConcepts: [
      ConceptRecommendation(
        conceptId: 'c_전가',
        conceptTag: 'NDF의 환율 전가 경로',
        reason: '진단에서 놓친 개념',
      ),
    ],
  );

  Future<ProviderContainer> pumpPanel(WidgetTester tester) async {
    // O/X 정답은 로컬 DB에 상태·XP를 쓴다. 인메모리로 갈아끼우지 않으면
    // 테스트가 실제 앱 DB 파일을 건드린다.
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: RecommendationPanel(recommendations: recs, graph: graph),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<ProviderContainer> openDetail(WidgetTester tester) async {
    final container = await pumpPanel(tester);
    await tester.tap(find.text('NDF의 환율 전가 경로'));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('개념을 누르면 같은 탭 안에서 상세가 열린다', (tester) async {
    final container = await openDetail(tester);

    expect(find.text('추천으로 돌아가기'), findsOneWidget);
    expect(find.text('NDF 거래가 현물 환율을 밀어 올리는 경로를 말한다.'), findsOneWidget);
    expect(container.read(inlineConceptDetailProvider), 'c_전가');
    // 지도 선택은 건드리지 않는다 — 옮기면 같은 개념이 지도와 패널에 동시에 뜬다.
    expect(container.read(selectedNodeIdProvider), isNull);
  });

  testWidgets('O/X 문항은 노드에 실려 온 진술문 그대로다', (tester) async {
    await openDetail(tester);

    expect(find.text('OX 퀴즈'), findsOneWidget);
    expect(find.text('NDF 거래는 계약대로 달러가 오가서 통화 가치에 영향이 없다'),
        findsOneWidget);
  });

  testWidgets('답을 고르면 정답 여부와 정답이 드러난다', (tester) async {
    await openDetail(tester);

    expect(find.textContaining('정답은'), findsNothing, reason: '풀기 전에는 답이 보이면 안 된다');

    // 이 진술은 사용자가 골랐던 오답이므로 정답은 X 다.
    await tester.tap(find.text('O'));
    await tester.pumpAndSettle();

    expect(find.textContaining('아쉬워요'), findsOneWidget);
    expect(find.textContaining('정답은 X'), findsOneWidget);
  });

  testWidgets('한 번 답하면 다시 고를 수 없다', (tester) async {
    await openDetail(tester);

    await tester.tap(find.text('X'));
    await tester.pumpAndSettle();
    expect(find.textContaining('정답이에요'), findsOneWidget);

    await tester.tap(find.text('O'));
    await tester.pumpAndSettle();
    expect(find.textContaining('정답이에요'), findsOneWidget,
        reason: '답을 바꿔 정답을 맞힐 수 있으면 복기가 되지 않는다');
  });

  testWidgets('해설 영역은 두지 않는다', (tester) async {
    // OX 는 LLM 없이 오답 선지에서 뽑으므로 서버에 해설이 없다.
    // 진술문 자체가 자기가 틀렸던 문장이라 해설 자리를 비워 둔다.
    await openDetail(tester);
    await tester.tap(find.text('O'));
    await tester.pumpAndSettle();

    expect(find.textContaining('차액만 정산하는 NDF'), findsNothing);
  });

  testWidgets('OX 재료가 없는 개념은 카드를 숨긴다(구버전 서버 호환)', (tester) async {
    final container = await pumpPanel(tester);
    container.read(inlineConceptDetailProvider.notifier).state = 'c_환헤지';
    await tester.pumpAndSettle();

    expect(find.text('환헤지'), findsWidgets);
    expect(find.text('OX 퀴즈'), findsNothing);
  });

  testWidgets('연관 개념을 누르면 그 개념 상세로 넘어간다', (tester) async {
    final container = await openDetail(tester);

    expect(find.text('연관 개념'), findsOneWidget);
    await tester.tap(find.text('환헤지'));
    await tester.pumpAndSettle();

    expect(container.read(inlineConceptDetailProvider), 'c_환헤지');
  });

  testWidgets('돌아가기를 누르면 추천 목록으로 복귀한다', (tester) async {
    final container = await openDetail(tester);

    await tester.tap(find.text('추천으로 돌아가기'));
    await tester.pumpAndSettle();

    expect(container.read(inlineConceptDetailProvider), isNull);
    expect(find.text('모를 것 같은 개념'), findsOneWidget);
  });
}
