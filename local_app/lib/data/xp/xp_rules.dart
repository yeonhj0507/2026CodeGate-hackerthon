/// 경험치(XP) 규칙 — "무엇에 얼마를 줄 것인가"를 이 파일 하나에 모은다.
///
/// **판정 시점은 동기화**다. 익스텐션이 XP를 계산해 보내지 않는다 —
/// 그러면 스크랩 계약(`ScrapRequest`)과 서버를 모두 건드려야 하고, 서버가
/// 학습 데이터를 들여다보게 된다(명세 §4.5 위반). 대신 로컬이 **동기화 전후
/// 그래프의 차이**에서 사건을 역산한다. 그래서 여기 있는 규칙은 전부
/// `before`/`after` 그래프와 새로 반영된 기사 목록만으로 판정된다.
///
/// XP 자체는 **모아두기만 한다**. 유료 기능 해금은 아직 구현 대상이 아니다.
library;

import '../dto/graph.dart';

/// 한 레벨에 필요한 XP.
const int xpPerLevel = 100;

/// XP가 쌓이는 사건.
///
/// `amount`가 규칙의 전부다. 오답에 대한 **감점은 없다** — 프로버는 "모르는 걸
/// 드러내는" 서비스라서, 틀리면 손해라는 신호를 주는 순간 사용자는 아는 기사만
/// 고르게 된다. [followupCompleted]가 오답 경로에 붙어 있는 것도 같은 이유다.
enum XpKind {
  /// 문항을 맞혀 개념이 곧장 이해완료로 들어온 경우.
  correctAnswer(10, '정답', '퀴즈 문항을 맞혔어요'),

  /// 막힌 지점에서 선행 개념 재질문까지 내려가 답한 경우. **오답이어도 준다.**
  followupCompleted(15, '재질문 완주', '막힌 곳에서 선행 개념까지 파고들었어요'),

  /// 미이해로 남아 있던 개념이 이해완료로 바뀐 경우.
  understoodTransition(30, '미이해 → 이해', '몰랐던 개념을 이해완료로 바꿨어요'),

  /// 선행을 먼저 뚫은 뒤 원래 막혔던 개념을 정복한 경우.
  /// 추천의 `ExpansionReason.retry`가 노리는 바로 그 순간이라 배점이 가장 높다.
  retrySuccess(50, '재도전 성공', '선행을 익히고 원래 막혔던 개념을 정복했어요'),

  /// 서로 다른 기사에서 알게 된 개념끼리 새로 이어진 경우.
  crossArticleLink(25, '기사 잇기', '다른 기사에서 온 개념끼리 이어졌어요'),

  /// 기사 한 편의 진단이 생각 지도에 반영된 경우.
  articleCompleted(20, '기사 완독', '기사 한 편의 진단을 끝까지 마쳤어요'),

  /// 그날 처음 앱을 연 경우. 하루 1회.
  streakDay(10, '연속 접속', '오늘도 생각 지도를 열었어요');

  const XpKind(this.amount, this.label, this.description);

  final int amount;
  final String label;
  final String description;

  /// 화면 효과를 화려하게 켤 이벤트인지.
  ///
  /// 모든 이벤트를 다 화려하게 하면 하루에도 여러 번 뜨는 정답 알림까지
  /// 피로해진다. 그래서 드물고 배점 큰 두 가지만 켠다 — 재도전 성공은
  /// 프로버 서사의 클라이맥스(선행을 뚫고 원래 막힌 주장을 정복)이고,
  /// 기사 잇기는 다른 서비스가 못 주는 크로스기사 연결의 순간이다.
  bool get isCelebration =>
      this == XpKind.retrySuccess || this == XpKind.crossArticleLink;

  /// 저장된 문자열 → enum. 모르는 값이면 null(구버전 DB를 깨뜨리지 않는다).
  static XpKind? tryParse(String raw) {
    for (final k in values) {
      if (k.name == raw) return k;
    }
    return null;
  }
}

/// 획득한 XP 한 건.
///
/// [dedupeKey]가 이 설계의 핵심이다. 동기화는 몇 번이든 다시 눌릴 수 있고
/// 그때마다 같은 diff가 나올 수 있으므로, 사건마다 고유 키를 붙여 DB에서
/// UNIQUE로 막는다. "이해 전환"과 "재도전 성공"은 같은 노드의 같은 순간이므로
/// 키 접두사를 공유해 둘 중 하나만 지급된다.
class XpEvent {
  const XpEvent({
    required this.kindName,
    required this.amount,
    required this.dedupeKey,
    required this.detail,
    required this.occurredAt,
  });

  XpEvent.of(
    XpKind kind, {
    required this.dedupeKey,
    required this.detail,
    DateTime? at,
  })  : kindName = kind.name,
        amount = kind.amount,
        occurredAt = at ?? DateTime.now();

  final String kindName;
  final int amount;
  final String dedupeKey;

  /// 어떤 개념/기사에서 얻었는지. 내역 목록에 그대로 보여 준다.
  final String detail;

  final DateTime occurredAt;

  XpKind? get kind => XpKind.tryParse(kindName);

  String get label => kind?.label ?? kindName;
}

/// 동기화 한 번으로 발생한 XP 사건들을 뽑는다.
///
/// [before]는 동기화 직전의 로컬 그래프, [after]는 서버가 돌려준 갱신본,
/// [newArticles]는 이번에 처음 "영구 반영본"으로 기록된 기사 제목들이다.
///
/// 한 노드가 여러 규칙에 동시에 걸리지 않도록 갈래를 배타적으로 나눴다:
///   새 선행 노드 → [XpKind.followupCompleted]
///   새 일반 노드(이해완료) → [XpKind.correctAnswer]
///   기존 노드의 미이해 → 이해 → [XpKind.retrySuccess] 또는
///                              [XpKind.understoodTransition]
List<XpEvent> evaluateGraphXp({
  required Graph before,
  required Graph after,
  List<String> newArticles = const [],
  DateTime? at,
}) {
  final now = at ?? DateTime.now();
  final events = <XpEvent>[];

  final beforeById = {for (final n in before.nodes) n.id: n};
  final afterById = {for (final n in after.nodes) n.id: n};
  final beforeEdges = {for (final e in before.edges) _edgeKey(e)};

  /// 후행 → 선행 목록. 재도전 판정에 쓴다.
  final prereqsOf = <String, List<String>>{};
  for (final e in after.edges) {
    if (e.type != EdgeType.prereq) continue;
    prereqsOf.putIfAbsent(e.to, () => []).add(e.from);
  }

  for (final node in after.nodes) {
    final old = beforeById[node.id];

    if (old == null) {
      // ── 이번에 처음 생긴 노드 ──────────────────────────────────
      if (node.isPrereq) {
        // 선행 노드인데 상태가 잡혔다 = 재질문 트리를 실제로 내려가 답했다.
        // 관계(relations)는 정오답과 무관하게 올라오므로, 아직 진단되지 않은
        // unknown 선행 노드는 "완주"로 치지 않는다.
        if (node.state != NodeState.unknown) {
          events.add(XpEvent.of(
            XpKind.followupCompleted,
            dedupeKey: 'followup:${node.id}',
            detail: '선행 개념 ‘${node.concept}’까지 확인',
            at: now,
          ));
        }
      } else if (node.isUnderstood) {
        events.add(XpEvent.of(
          XpKind.correctAnswer,
          dedupeKey: 'correct:${node.id}',
          detail: '‘${node.concept}’ 문항 정답',
          at: now,
        ));
      }
      continue;
    }

    // ── 이미 있던 노드의 상태 변화 ─────────────────────────────────
    if (!(old.isNotUnderstood && node.isUnderstood)) continue;

    final solvedPrereq = (prereqsOf[node.id] ?? const <String>[])
        .any((id) => afterById[id]?.isUnderstood ?? false);

    events.add(XpEvent.of(
      solvedPrereq ? XpKind.retrySuccess : XpKind.understoodTransition,
      // 두 갈래가 키를 공유한다 — 한 노드의 "이해 전환"은 평생 한 번만 지급.
      dedupeKey: 'understood:${node.id}',
      detail: solvedPrereq
          ? '선행을 익히고 ‘${node.concept}’ 정복'
          : '‘${node.concept}’ 이해완료',
      at: now,
    ));
  }

  // ── 기사 사이를 잇는 새 엣지 ──────────────────────────────────────
  for (final edge in after.edges) {
    if (beforeEdges.contains(_edgeKey(edge))) continue;

    final from = afterById[edge.from];
    final to = afterById[edge.to];
    if (from == null || to == null) continue;

    final a = _articleKeys(from);
    final b = _articleKeys(to);
    if (a.isEmpty || b.isEmpty) continue;

    // 출처가 완전히 같으면 한 기사 안의 연결일 뿐이다. 한쪽에만 있는 기사가
    // 있어야 "다른 기사에서 온 개념이 붙었다"가 된다.
    if (a.length == b.length && a.containsAll(b)) continue;

    events.add(XpEvent.of(
      XpKind.crossArticleLink,
      dedupeKey: 'cross:${_edgeKey(edge)}',
      detail: '‘${from.concept}’ ↔ ‘${to.concept}’ 연결',
      at: now,
    ));
  }

  // ── 반영이 끝난 기사 ─────────────────────────────────────────────
  for (final title in newArticles) {
    if (title.isEmpty) continue;
    events.add(XpEvent.of(
      XpKind.articleCompleted,
      dedupeKey: 'article:$title',
      detail: title,
      at: now,
    ));
  }

  return events;
}

String _edgeKey(GraphEdge e) => '${e.from}->${e.to}:${e.type}';

/// 노드의 출처 기사 식별자 집합. URL이 있으면 URL이 식별자다(`SourceArticle` 주석).
Set<String> _articleKeys(GraphNode node) => {
      for (final a in node.sourceArticles)
        if (a.url.isNotEmpty)
          a.url
        else if (a.title.isNotEmpty)
          a.title,
    };

/// 접속 기록 결과. 스트릭 XP를 줄지 판단하는 데 쓴다.
class VisitOutcome {
  const VisitOutcome({
    required this.dayKey,
    required this.isFirstToday,
    required this.streak,
  });

  /// `yyyy-MM-dd`(로컬 기준).
  final String dayKey;

  /// 오늘 처음 연 것인지. false면 스트릭 XP를 주지 않는다.
  final bool isFirstToday;

  /// 오늘로 끝나는 연속 접속 일수.
  final int streak;
}

/// 화면에 보여 줄 XP 현황 한 벌.
class XpSnapshot {
  const XpSnapshot({
    this.total = 0,
    this.streak = 0,
    this.recent = const [],
  });

  static const empty = XpSnapshot();

  final int total;
  final int streak;

  /// 최근 획득 내역(최신순).
  final List<XpEvent> recent;

  int get level => total ~/ xpPerLevel + 1;

  /// 현재 레벨 안에서 쌓은 양.
  int get intoLevel => total % xpPerLevel;

  int get toNextLevel => xpPerLevel - intoLevel;

  double get levelProgress => intoLevel / xpPerLevel;
}

/// 이전 스냅샷과 비교해 **새로 나타난** 이벤트만 뽑는다.
///
/// `XpSnapshot`은 지금 상태의 스냅샷일 뿐 델타를 담지 않는다. 그런데 배지가
/// "방금 무엇이 들어왔는지"(count-up을 켤지, 축하 효과를 켤지)를 판단하려면
/// 델타가 필요하다. `recent`는 최신순 상위 N개라, [dedupeKey]가 이전 스냅샷의
/// `recent`에 없으면 이번에 처음 보인 것이다.
///
/// 동기화(여러 건 한꺼번에)든 OX 퀴즈·접속 스트릭(한 건씩)이든 같은 함수로
/// 처리된다 — XP가 쌓이는 경로는 여럿이어도 "새로 들어온 걸 찾는다"는 하나다.
List<XpEvent> newlyArrivedEvents(XpSnapshot? previous, XpSnapshot next) {
  final known = {for (final e in previous?.recent ?? const []) e.dedupeKey};
  return [
    for (final e in next.recent)
      if (!known.contains(e.dedupeKey)) e,
  ];
}
