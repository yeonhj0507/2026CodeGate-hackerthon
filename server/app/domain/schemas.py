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
    """퀴즈 1문항의 진단 결과. parentConcept 가 선행→후행 엣지 복원 근거.

    아래 문항·선지 필드는 **OX 퀴즈 재료**다(추천 탭 개념 상세). 서버는 퀴즈를 저장하지
    않으므로(명세 §4.2 stateless) 익스텐션이 실어 보내지 않으면 만들 방법이 없다.
    구버전 익스텐션도 그대로 동작하도록 전부 선택 필드로 둔다.
    """

    conceptTag: str
    parentConcept: str | None = None
    level: int = 0
    correct: bool

    question: str | None = None
    selectedOption: str | None = None  # 사용자가 고른 보기. 오답이면 OX 의 "거짓" 재료
    correctOption: str | None = None


class ConceptRelation(Strict):
    """퀴즈 트리가 품고 있던 선행→후행 관계 한 줄.

    `from_`(선행)을 알아야 `to`(후행)를 이해한다. 방향은 `GraphEdge` 와 같다.
    """

    from_: str = Field(alias="from")
    to: str


class ScrapRequest(Strict):
    """스크랩 페이로드에는 **기사 원문이 없다**(명세 §3.4).

    원문은 `/quiz` 에서 이미 처리했으므로 재전송하지 않고, 출처 식별은 URL로만 한다.
    서버에 원문이 영속되는 지점을 없애기 위한 결정이다.
    """

    articleUrl: str
    articleTitle: str
    results: list[ScrapResult]
    # 퀴즈 트리에 이미 들어 있던 선행 관계. **정답·오답과 무관하게** 보낸다.
    #
    # 이게 없으면 엣지는 사용자가 틀려서 재질문으로 내려갔을 때만 생긴다
    # (merge.py 의 parentConcept 경로). 다 맞히면 개념이 전부 고립되고, 엣지를
    # 훑는 결핍·확장 추천까지 함께 굶는다. LLM 이 이미 만들어 둔 관계라
    # 추가 호출 비용이 없다. 구버전 익스텐션 호환을 위해 optional.
    relations: list[ConceptRelation] = Field(default_factory=list)


class ScrapResponse(Strict):
    ok: bool = True
    buffered: int  # 이 요청으로 버퍼에 쌓인 결과 개수


# ------------------------------------------------- /thoughtmap/update


class SourceArticle(Strict):
    """노드의 출처 기사 메타. URL이 식별자이고 원문은 담지 않는다(명세 §7)."""

    url: str
    title: str = ""


class OxQuiz(Strict):
    """개념 상세에 붙는 O/X 한 문항.

    LLM 이 만들지 않는다. 사용자가 실제로 골랐던 오답 선지를 그대로 진술문으로 쓰므로
    (그래서 `answer=False`) "내가 왜 틀렸는지"를 그 자리에서 되짚게 된다.
    """

    statement: str
    answer: bool
    sourceQuestion: str | None = None


class GraphNode(Strict):
    id: str
    concept: str
    state: str = STATE_UNKNOWN
    isPrereq: bool = False
    sourceArticles: list[SourceArticle] = Field(default_factory=list)
    summaryMeta: str | None = None
    oxQuiz: OxQuiz | None = None

    # 그래프 시각화 노출 여부(명세 §4.4·§7). 확장 후보를 "수락 전 비노출"로 두기 위한 필드다.
    #
    # 다만 현재 확장 신호(재도전·형제)는 **사용자가 이미 퀴즈로 만난 노드**만 고르므로,
    # 후보로 뽑혔다고 false 로 강등하면 보던 노드가 사라지는 UX 가 된다. 그래서 서버는
    # 한 번 true 인 노드를 되돌리지 않고(단조 증가), 결과적으로 현재는 항상 true 다.
    # 그래프에 없던 개념을 후보로 만드는 신호가 생기면 그때 false 가 의미를 갖는다.
    promoted: bool = True


class GraphEdge(Strict):
    """개념 사이의 관계 한 줄.

    **방향: from = 후행(기사의 핵심어) → to = 선행(먼저 알아야 할 개념).**

    화살표를 따라가면 더 근본적인 개념으로 내려간다. 로컬앱 지도는 Sugiyama
    상→하 레이아웃이라 `from` 이 위층에 놓이므로, 이 방향이면 기사에서 만난
    핵심어가 맨 위에 서고 그 아래로 선행 개념이 뻗는다.

    ⚠️ 이 방향은 예전과 반대다(과거: from=선행 → to=후행). 엣지를 읽는 코드는
    전부 이 규칙을 따라야 한다 — merge/recommend/_attach_summaries 가 그렇다.
    """

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
    """확장 추천 — **아는 개념에서 뻗어나가는 새 키워드**.

    아직 그래프에 없는 개념만 온다. 그래서 `conceptId` 는 그래프 노드 id 가 아니라
    정규화 키이며, 로컬앱은 이 항목을 그래프에서 찾을 수 없다(수락 전에는 노드가
    없는 게 정상이다 — 명세 §4.4 의 `promoted` 흐름).

    `reason` 은 자연어가 아니라 신호 종류다. 문구 매핑은 로컬앱 소관.
    - neighbor: 내가 이해한 개념과 같은 기사에서 함께 다뤄지는 개념
    """

    conceptId: str
    conceptTag: str
    reason: Literal["neighbor"] = "neighbor"
    # 이 개념을 데려온 근거 — 함께 등장한 내 개념들. 로컬앱이 이유를 설명할 수 있다.
    viaConcepts: list[str] = Field(default_factory=list)
    # 이 개념이 실제로 쓰인 기사. 카드에서 바로 읽으러 갈 수 있게 함께 보낸다.
    articleTitle: str = ""
    articleUrl: str = ""


class RetryConcept(Strict):
    """다시 도전할 개념 — 오답을 되짚는 신호.

    확장 추천과 분리한다. 둘 다 "이해완료를 발판 삼는다"는 점은 같지만, 이쪽은
    **이미 내 그래프에 있고 틀린 것**이고 확장은 **아직 없는 새 것**이다. 한 섹션에
    섞으면 "확장"이라는 이름이 오답 복기를 가리키게 된다.

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
    # 제휴 데이터셋에서 왔는지, 웹 검색 폴백으로 채웠는지. 로컬앱이 출처를 표시할 수 있다.
    source: Literal["partner", "search"] = "partner"


class Recommendations(Strict):
    gapConcepts: list[ConceptRecommendation] = Field(default_factory=list)
    expansionConcepts: list[ExpansionConcept] = Field(default_factory=list)
    retryConcepts: list[RetryConcept] = Field(default_factory=list)
    articles: list[ArticleRecommendation] = Field(default_factory=list)


class ThoughtmapUpdateResponse(Strict):
    graph: Graph
    recommendations: Recommendations
    # 이번 응답에 반영된 스크랩 수 (디버깅·데모용)
    consumedScraps: int = 0

    # 반영된 스크랩의 id. **아직 서버에 남아 있다.**
    #
    # 예전에는 응답을 만든 직후 서버가 지웠는데, 클라이언트가 그 응답을 못 받으면
    # (타임아웃·네트워크 순단·앱 종료) 진단 결과가 서버에서도 로컬에서도 사라졌다.
    # 실제로 QA 중 한 세션이 통째로 날아갔다. 이제 로컬 반영을 마친 클라이언트가
    # `/thoughtmap/ack` 로 이 id 들을 돌려줄 때 지운다.
    #
    # ack 이 안 와도 안전하다 — 병합은 같은 스크랩을 두 번 먹어도 결과가 같고
    # (상태 재적용·출처 중복 제거·OX 미덮어씀), 버퍼는 TTL·행수 상한으로 정리된다.
    consumedScrapIds: list[str] = Field(default_factory=list)


class ScrapAckRequest(Strict):
    """로컬 반영을 마쳤으니 이 스크랩들을 지워도 된다는 통보."""

    scrapIds: list[str] = Field(default_factory=list)


class ScrapAckResponse(Strict):
    deleted: int = 0


# ------------------------------------------------------------ /explore


class ExploreRequest(Strict):
    """탐색 탭 — 키워드 2~3개를 묶어 더 파고들기.

    서버는 그래프를 보관하지 않으므로 노드 id 만으로는 개념명을 모른다.
    로컬앱이 id 와 이름을 함께 보낸다.
    """

    conceptIds: list[str] = Field(default_factory=list)
    conceptTags: list[str] = Field(min_length=1, max_length=5)


class ExploreResponse(Strict):
    explanation: str
    articles: list[ArticleRecommendation] = Field(default_factory=list)
    # 웹 뉴스 검색이 실패했는지. 제휴 기사는 그대로 실리되, 이 값이 True 면
    # 융합검색 화면이 기사 영역에 "뉴스 검색 실패"를 알린다.
    searchFailed: bool = False
