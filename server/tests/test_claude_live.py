"""실제 Anthropic API 를 호출하는 검증 — **기본 실행에서는 건너뛴다**.

과금·지연·비결정성이 있으므로 명시적으로 켤 때만 돈다:

    PROBER_LIVE_LLM=1 pytest -m live

conftest 가 프로세스 전역 LLM_PROVIDER 를 mock 으로 고정하므로, 여기서는
프로바이더를 직접 만들어 쓴다(다른 테스트에 영향을 주지 않는다).
"""

import os

import pytest

pytestmark = pytest.mark.live

ARTICLE_TITLE = "한국은행, 기준금리 연 3.50% 동결"
PARAGRAPHS = [
    "한국은행 금융통화위원회가 기준금리를 연 3.50%로 동결했다. 여섯 차례 연속 동결이다.",
    "동결 배경에는 물가와 성장 사이의 저울질이 있다. 소비자물가 상승률은 목표치에 근접했지만 "
    "내수 회복 속도는 여전히 더디다는 판단이 작용했다.",
    "환율도 결정을 제약한 변수다. 금리를 내리면 원화 약세가 심해지고, 수입물가를 통해 국내 "
    "물가를 다시 자극할 수 있기 때문이다.",
    "시장은 다음 분기 인하 가능성에 무게를 싣는다. 다만 국채금리에는 인하 기대가 이미 상당 "
    "부분 반영됐다는 분석도 나온다.",
]


@pytest.fixture(autouse=True)
def _requires_optin():
    if os.getenv("PROBER_LIVE_LLM") != "1":
        pytest.skip("실호출 테스트는 PROBER_LIVE_LLM=1 일 때만 실행한다 (과금 발생)")
    if not os.getenv("ANTHROPIC_API_KEY") and "ANTHROPIC_API_KEY" not in _dotenv():
        pytest.skip("ANTHROPIC_API_KEY 미설정")


def _dotenv() -> str:
    from pathlib import Path

    path = Path(__file__).resolve().parents[1] / ".env"
    return path.read_text(encoding="utf-8") if path.exists() else ""


def _provider():
    # conftest 가 LLM_PROVIDER 를 mock 으로 고정했으므로 직접 인스턴스화한다.
    from app.domain.llm.claude import ClaudeProvider

    return ClaudeProvider()


async def test_live_quiz_matches_contract():
    """모델 원출력이 아니라 **서버가 정규화한 결과**를 단언한다.

    처음엔 원출력에 대고 `followups <= 1` 을 단언했다가 한 번 실패하고 재실행에서
    통과했다 — 모델이 가끔 2개를 낸다. 그건 계약 위반이 아니다. 서버
    (`_clamp_followups`)가 깎아 내보내는 게 설계이므로, 익스텐션이 실제로 받는
    모양을 검사하는 게 맞다. 모델 변덕으로 흔들리지도 않는다.
    """
    from app.domain.quiz.service import MAX_QUIZ_ITEMS, _normalize

    raw = await _provider().generate_quiz(ARTICLE_TITLE, PARAGRAPHS)
    quiz = _normalize(raw, PARAGRAPHS).quiz

    # 하한은 단언하지 않는다. "2~4개"는 프롬프트로 요청할 뿐 서버가 만들어 낼 수는
    # 없고, 실제로 1문항만 온 적이 있다(모델 변덕). 상한은 서버가 잠근다.
    assert 1 <= len(quiz) <= MAX_QUIZ_ITEMS

    for item in quiz:
        assert 0 <= item.paragraphIndex < len(PARAGRAPHS)
        assert len(item.options) == 4
        assert 0 <= item.answerIndex < 4
        assert item.conceptTag and item.conceptTag != ARTICLE_TITLE
        # anchorText 는 LLM 을 믿지 않고 서버가 문단에서 채운다.
        assert PARAGRAPHS[item.paragraphIndex].startswith(item.anchorText[:10])
        # 한국어 출력 계약.
        assert any("가" <= ch <= "힣" for ch in item.question)

        assert len(item.followups) <= 1
        if item.followups:
            f1 = item.followups[0]
            assert f1.level == 1
            assert len(f1.options) == 4
            assert len(f1.followups) <= 1
            if f1.followups:
                assert f1.followups[0].level == 2


async def test_live_explore_explains_concepts_together():
    """탐색 탭의 존재 이유는 **묶어서** 보는 것이다 — 개별 정의 나열이면 의미가 없다."""
    concepts = ["기준금리", "환율", "수입물가"]
    text = await _provider().explain_concepts(concepts)

    assert len(text) > 30
    assert any("가" <= ch <= "힣" for ch in text)
    # 고른 개념이 최소한 언급은 돼야 한다.
    assert sum(1 for c in concepts if c in text) >= 2
    # 마크다운을 쓰지 말라고 지시했다(로컬앱이 평문으로 그린다).
    assert "##" not in text and "**" not in text


async def test_live_search_returns_news_only():
    """나무위키·지식백과가 올라오던 문제. allowed_domains + 사후 필터가 실제로 통하는지."""
    from app.domain.search.claude_search import ClaudeSearchProvider
    from app.domain.search.news_domains import is_news

    found = await ClaudeSearchProvider().search_articles(["기준금리", "환율"], 3)

    assert found, "언론사로 좁혀도 결과가 나와야 한다 (0건이면 목록이 너무 좁다는 뜻)"
    for item in found:
        assert item.url.startswith("http")
        assert is_news(item.url), f"뉴스가 아닌 결과가 통과했다: {item.url}"
        assert item.title


async def test_live_search_survives_a_topic_with_no_news():
    """검색이 빈손이어도 예외를 던지지 않아야 한다 — 추천 실패가 동기화를 막으면 안 된다."""
    from app.domain.search.claude_search import ClaudeSearchProvider

    found = await ClaudeSearchProvider().search_articles(["ㅁㄴㅇㄹ존재하지않는개념ㅋㅋ"], 2)

    assert isinstance(found, list)


async def test_live_summaries_use_graph_context_only():
    from app.domain.llm.base import ConceptContext

    items = [
        ConceptContext(
            concept="환율 전가",
            is_prereq=True,
            parent_concepts=["기준금리"],
            prereq_concepts=["수입물가"],
            source_titles=[ARTICLE_TITLE],
        )
    ]
    out = await _provider().summarize_concepts(items)

    assert "환율 전가" in out
    text = out["환율 전가"]
    assert len(text) > 20
    assert any("가" <= ch <= "힣" for ch in text)
