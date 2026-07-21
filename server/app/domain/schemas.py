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
    articleTitle: str
    articleBody: str
    results: list[ScrapResult]


class ScrapResponse(Strict):
    ok: bool = True
    buffered: int  # 이 요청으로 버퍼에 쌓인 결과 개수


# ------------------------------------------------- /thoughtmap/update


class GraphNode(Strict):
    id: str
    concept: str
    state: str = STATE_UNKNOWN
    isPrereq: bool = False
    sourceArticles: list[str] = Field(default_factory=list)
    summaryMeta: str | None = None


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
    concept: str
    reason: str


class ArticleRecommendation(Strict):
    title: str
    url: str
    publisher: str = ""
    summary: str = ""
    matchedConcepts: list[str] = Field(default_factory=list)


class Recommendations(Strict):
    concepts: list[ConceptRecommendation] = Field(default_factory=list)
    articles: list[ArticleRecommendation] = Field(default_factory=list)


class ThoughtmapUpdateResponse(Strict):
    graph: Graph
    recommendations: Recommendations
    # 이번 동기화로 소비·삭제된 스크랩 수 (디버깅·데모용)
    consumedScraps: int = 0
