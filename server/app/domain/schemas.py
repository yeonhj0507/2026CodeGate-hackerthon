"""API 계약 스키마 (Pydantic v2).

**필드명은 담당1(구현계획① §5)·로컬앱 `lib/data/dto/graph.dart` 와의 계약이므로
임의로 바꾸지 않는다.** camelCase 를 그대로 쓴다.
"""

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

# --- 노드 이해상태 / 엣지 타입 (graph.dart 의 NodeState·EdgeType 과 동일) ---

STATE_UNDERSTOOD = "understood"
STATE_NOT_UNDERSTOOD = "not_understood"
STATE_UNKNOWN = "unknown"

EDGE_PREREQ = "prereq"
EDGE_RELATED = "related"


class Strict(BaseModel):
    model_config = ConfigDict(populate_by_name=True)


# ---------------------------------------------------------------- /quiz


class QuizRequest(Strict):
    articleTitle: str
    articleBody: str


class Followup(Strict):
    """선행개념 재질문. level 1~2, 깊이 2가 상한(명세 §4.2)."""

    level: int = Field(ge=1, le=2)
    prereqConceptTag: str
    question: str
    options: list[str] = Field(min_length=2)
    answerIndex: int = Field(ge=0)
    explanation: str
    followups: list["Followup"] = Field(default_factory=list)


class QuizItem(Strict):
    claimId: str
    conceptTag: str
    anchorText: str
    paragraphIndex: int = Field(ge=0)
    question: str
    options: list[str] = Field(min_length=2)
    answerIndex: int = Field(ge=0)
    explanation: str
    followups: list[Followup] = Field(default_factory=list)


class QuizResponse(Strict):
    quiz: list[QuizItem]


# ---------------------------------------------------------------- /scrap


class ScrapResult(Strict):
    """퀴즈 1문항의 진단 결과. parentConcept 가 선행→후행 엣지 복원 근거."""

    conceptTag: str
    parentConcept: str | None = None
    level: int = 0
    correct: bool


class ScrapRequest(Strict):
    """스크랩 페이로드에는 **기사 원문이 없다**(명세 §3.4).

    원문은 `/quiz` 에서 이미 처리했으므로 재전송하지 않고, 출처 식별은 URL로만 한다.
    서버에 원문이 영속되는 지점을 없애기 위한 결정이다.
    """

    articleUrl: str
    articleTitle: str
    results: list[ScrapResult]


class ScrapResponse(Strict):
    ok: bool = True
    buffered: int  # 이 요청으로 버퍼에 쌓인 결과 개수


# ------------------------------------------------- /thoughtmap/update


class SourceArticle(Strict):
    """노드의 출처 기사 메타. URL이 식별자이고 원문은 담지 않는다(명세 §7)."""

    url: str
    title: str = ""


class GraphNode(Strict):
    id: str
    concept: str
    state: str = STATE_UNKNOWN
    isPrereq: bool = False
    sourceArticles: list[SourceArticle] = Field(default_factory=list)
    summaryMeta: str | None = None

    # 그래프 시각화 노출 여부(명세 §4.4·§7). 확장 후보를 "수락 전 비노출"로 두기 위한 필드다.
    #
    # 다만 현재 확장 신호(재도전·형제)는 **사용자가 이미 퀴즈로 만난 노드**만 고르므로,
    # 후보로 뽑혔다고 false 로 강등하면 보던 노드가 사라지는 UX 가 된다. 그래서 서버는
    # 한 번 true 인 노드를 되돌리지 않고(단조 증가), 결과적으로 현재는 항상 true 다.
    # 그래프에 없던 개념을 후보로 만드는 신호가 생기면 그때 false 가 의미를 갖는다.
    promoted: bool = True


class GraphEdge(Strict):
    # `from` 은 파이썬 예약어라 필드명은 from_ 이고 JSON 키만 "from" 이다.
    # FastAPI 는 response_model 직렬화 시 by_alias=True 를 쓰므로 계약이 유지된다.
    from_: str = Field(alias="from")
    to: str
    type: Literal["prereq", "related"] = EDGE_PREREQ


class Graph(Strict):
    nodes: list[GraphNode] = Field(default_factory=list)
    edges: list[GraphEdge] = Field(default_factory=list)


class UserContext(Strict):
    """로컬앱이 보내는 사용자 컨텍스트. 서버는 저장하지 않고 참조만 한다(명세 §4.5).

    로컬앱 스키마가 아직 확정 전이라 미지의 키도 버리지 않고 받아 둔다.
    """

    model_config = ConfigDict(populate_by_name=True, extra="allow")

    # 최근 학습 이력 (선택)
    learningHistory: list[dict] = Field(default_factory=list)
    # 기사 선호 패턴: 카테고리·키워드 가중치 (선택)
    preferredCategories: list[str] = Field(default_factory=list)
    preferredKeywords: list[str] = Field(default_factory=list)


class ThoughtmapUpdateRequest(Strict):
    graph: Graph = Field(default_factory=Graph)
    userContext: UserContext = Field(default_factory=UserContext)


class ConceptRecommendation(Strict):
    """결핍 보완 추천 — "모를 것 같은 개념"(명세 §4.4).

    `conceptId` 는 그래프 노드 id(정규화 키)라 로컬앱이 그래프에서 위치를 짚을 수 있다.
    """

    conceptId: str
    conceptTag: str
    reason: str


class ExpansionConcept(Strict):
    """확장 추천 — 이해완료를 발판 삼은 심화(명세 §4.4, 신규).

    `reason` 은 자연어가 아니라 신호 종류다. 사용자에게 보일 문구 매핑은 로컬앱 소관.
    - retry:   선행을 이해했으니 원래 주장에 다시 도전
    - sibling: 같은 상위 개념을 공유하는 옆 갈래
    """

    conceptId: str
    conceptTag: str
    reason: Literal["retry", "sibling"]


class ArticleRecommendation(Strict):
    title: str
    url: str
    publisher: str = ""
    summary: str = ""
    matchedConcepts: list[str] = Field(default_factory=list)


class Recommendations(Strict):
    gapConcepts: list[ConceptRecommendation] = Field(default_factory=list)
    expansionConcepts: list[ExpansionConcept] = Field(default_factory=list)
    articles: list[ArticleRecommendation] = Field(default_factory=list)


class ThoughtmapUpdateResponse(Strict):
    graph: Graph
    recommendations: Recommendations
    # 이번 동기화로 소비·삭제된 스크랩 수 (디버깅·데모용)
    consumedScraps: int = 0
