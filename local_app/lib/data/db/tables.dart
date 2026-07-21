/// 로컬 SQLite 스키마 (구현계획③ §3.1).
///
/// 이 5개 테이블이 **사용자 학습 데이터의 원본**이다. 서버는 계정·인증만
/// 보관하므로(명세 §4.5) 여기가 유일한 진실이다.
///
/// 행 클래스 이름에 `Row` 접미사를 붙인 이유: drift 기본 규칙대로면
/// `GraphNodes` → `GraphNode`가 되어 `data/dto/graph.dart`의 전송 DTO와
/// 이름이 충돌한다. 저장 모델과 전송 모델을 구분해 둔다.
library;

import 'package:drift/drift.dart';

/// 지식그래프 노드. `id`는 서버가 부여한 개념 노드 식별자.
@DataClassName('GraphNodeRow')
class GraphNodes extends Table {
  TextColumn get id => text()();
  TextColumn get concept => text()();

  /// understood / not_understood / unknown. 미지의 값도 그대로 보존한다.
  TextColumn get state => text()();

  BoolColumn get isPrereq => boolean().withDefault(const Constant(false))();

  /// 출처 기사 제목 목록을 JSON 배열 문자열로 보관.
  TextColumn get sourceArticlesJson =>
      text().withDefault(const Constant('[]'))();

  /// 개인화 요약이 흡수된 자리(명세 §4.4).
  TextColumn get summaryMeta => text().nullable()();

  /// 추천 탭 개념 상세의 O/X 문항을 JSON 으로 보관. 재료가 없으면 null.
  TextColumn get oxQuizJson => text().nullable()();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 개념 간 관계. 선행(from) → 후행(to).
@DataClassName('GraphEdgeRow')
class GraphEdges extends Table {
  TextColumn get fromId => text()();
  TextColumn get toId => text()();
  TextColumn get type => text()();

  @override
  Set<Column> get primaryKey => {fromId, toId, type};
}

/// 학습이력. 로컬 전용 — 서버로 보내기만 하고 응답으로 덮어쓰지 않는다.
@DataClassName('LearningHistoryRow')
class LearningHistories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get conceptTag => text()();

  /// null이면 main 문항(구현계획① §3.5).
  TextColumn get parentConcept => text().nullable()();

  IntColumn get level => integer().withDefault(const Constant(0))();
  BoolColumn get correct => boolean()();
  TextColumn get articleTitle => text().nullable()();
  DateTimeColumn get occurredAt => dateTime()();
}

/// 기사 선호 패턴. 서버의 기사 추천 랭킹 입력.
@DataClassName('ArticlePreferenceRow')
class ArticlePreferences extends Table {
  TextColumn get keyword => text()();
  TextColumn get category => text().nullable()();
  RealColumn get weight => real().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {keyword};
}

/// 반영 완료된 스크랩 기록. "임시 스크랩의 영구 반영본"(명세 §5.1)에 해당하며,
/// 어떤 기사가 언제 그래프에 녹아들었는지를 남긴다.
@DataClassName('AppliedScrapRow')
class AppliedScraps extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get articleTitle => text()();
  IntColumn get nodeCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get appliedAt => dateTime()();
}
