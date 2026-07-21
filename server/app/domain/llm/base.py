"""LLM 프로바이더 경계.

퀴즈 생성과 개념 재요약만 LLM을 쓴다. 채점은 서버 미개입(객관식·클라이언트).
`LLM_PROVIDER` 환경변수로 mock/claude 를 갈아끼운다.
"""

from collections.abc import AsyncIterator
from dataclasses import dataclass, field
from typing import Protocol

from app.core.config import get_settings


@dataclass
class ConceptContext:
    """재요약 1건의 근거.

    서버는 기사 원문을 보관하지 않으므로(명세 §3.4·§4.4) 재요약은 원문 재독해가 아니라
    **개념 관계와 진단 결과**만으로 만들어진다. 여기 담기는 게 근거의 전부다.
    """

    concept: str
    is_prereq: bool = False
    # 진단 결과. True 면 맞힌 개념이라 설명의 방향이 달라진다(확인·확장 톤).
    # 이 플래그가 없으면 이해완료 개념에도 "몰라서 막혔다"고 쓰게 된다.
    understood: bool = False
    # 이 개념을 선행으로 두는 상위 개념들(= 이걸 몰라서 막힌 지점).
    parent_concepts: list[str] = field(default_factory=list)
    # 이 개념을 이해하려면 먼저 알아야 하는 더 얕은 개념들.
    prereq_concepts: list[str] = field(default_factory=list)
    # 출처 기사 제목(맥락 힌트). 원문이 아니라 제목뿐이다.
    source_titles: list[str] = field(default_factory=list)


class LlmProvider(Protocol):
    async def generate_quiz(self, title: str, paragraphs: list[str]) -> dict:
        """`{"quiz": [...]}` 형태의 원시 dict 를 반환. 검증은 호출부가 한다."""
        ...

    def stream_quiz(self, title: str, paragraphs: list[str]) -> AsyncIterator[dict]:
        """퀴즈 문항을 **완성되는 대로** 하나씩 흘려보낸다.

        `generate_quiz` 와 같은 1회 호출이고 결과도 같다. 다른 건 도착 시점뿐 —
        전체가 끝나기를 기다리지 않으므로 익스텐션이 첫 문항을 훨씬 일찍 받는다.
        원소 하나가 곧 `generate_quiz` 결과의 `quiz[i]` 다.
        """
        ...

    async def summarize_concepts(self, items: list[ConceptContext]) -> dict[str, str]:
        """진단된 개념 → 보충설명(재요약) 매핑. 명세 §4.4의 "개인화 요약 흡수".

        미이해·이해완료를 함께 받는다. 상태는 `ConceptContext.understood` 로 넘어오고
        설명의 방향(막힌 지점 짚기 / 발판 삼아 넓히기)만 갈린다.
        """
        ...

    async def explain_concepts(self, concepts: list[str]) -> str:
        """탐색 탭 — 고른 키워드 2~3개를 **묶어서** 2~3문장으로 설명한다.

        개별 정의의 나열이 아니라 개념들이 서로 어떻게 얽히는지를 말해야 의미가 있다.
        """
        ...


def get_llm_provider() -> LlmProvider:
    settings = get_settings()
    if settings.llm_provider == "claude":
        from app.domain.llm.claude import ClaudeProvider

        return ClaudeProvider()

    from app.domain.llm.mock import MockProvider

    return MockProvider()
