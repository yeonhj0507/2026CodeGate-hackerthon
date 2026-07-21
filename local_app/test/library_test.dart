import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prober_local/data/dto/graph.dart';
import 'package:prober_local/providers/providers.dart';

/// 보관함은 **서버 왕복 없이** 그래프에서 역산한다(명세 §4.5 — 학습 데이터 원본은 로컬).
/// 그 역산 규칙을 여기서 못 박는다.
void main() {
  ProviderContainer containerFor(Graph graph) {
    final c = ProviderContainer(overrides: [
      graphProvider.overrideWith((ref) => Stream.value(graph)),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  Future<List<LibraryEntry>> entriesOf(Graph graph) async {
    final c = containerFor(graph);
    // graphProvider 가 값을 낼 때까지 기다린 뒤 파생 provider 를 읽는다.
    await c.read(graphProvider.future);
    return c.read(libraryProvider);
  }

  const articleA = SourceArticle(url: 'https://n.example/a', title: '금리 기사');
  const articleB = SourceArticle(url: 'https://n.example/b', title: '환율 기사');

  test('기사 URL 로 묶여 카드가 만들어진다', () async {
    final entries = await entriesOf(const Graph(nodes: [
      GraphNode(
        id: 'c1',
        concept: '기준금리',
        state: NodeState.notUnderstood,
        isPrereq: false,
        sourceArticles: [articleA],
      ),
      GraphNode(
        id: 'c2',
        concept: '통화정책',
        state: NodeState.understood,
        isPrereq: true,
        sourceArticles: [articleA],
      ),
      GraphNode(
        id: 'c3',
        concept: '환율',
        state: NodeState.understood,
        isPrereq: false,
        sourceArticles: [articleB],
      ),
    ]));

    expect(entries, hasLength(2));
    // 많이 배운 기사가 위로 온다.
    expect(entries.first.article.url, articleA.url);
    expect(entries.first.concepts.map((n) => n.concept),
        containsAll(['기준금리', '통화정책']));
    expect(entries.first.understoodCount, 1);
  });

  test('한 개념이 여러 기사에 걸치면 양쪽 카드에 모두 등장한다(크로스기사)', () async {
    final entries = await entriesOf(const Graph(nodes: [
      GraphNode(
        id: 'c1',
        concept: '기준금리',
        state: NodeState.understood,
        isPrereq: false,
        sourceArticles: [articleA, articleB],
      ),
    ]));

    expect(entries, hasLength(2));
    for (final e in entries) {
      expect(e.concepts.single.concept, '기준금리');
    }
  });

  test('출처가 없는 노드는 보관함에 뜨지 않는다', () async {
    final entries = await entriesOf(const Graph(nodes: [
      GraphNode(
        id: 'c1',
        concept: '추천으로만 등장한 개념',
        state: NodeState.unknown,
        isPrereq: false,
      ),
    ]));

    expect(entries, isEmpty);
  });

  test('URL 없는 구형 항목은 제목으로 묶인다', () async {
    final entries = await entriesOf(const Graph(nodes: [
      GraphNode(
        id: 'c1',
        concept: '기준금리',
        state: NodeState.understood,
        isPrereq: false,
        sourceArticles: [SourceArticle(url: '', title: '옛 기사')],
      ),
    ]));

    expect(entries, hasLength(1));
    expect(entries.single.article.label, '옛 기사');
    expect(entries.single.article.hasUrl, isFalse);
  });
}
