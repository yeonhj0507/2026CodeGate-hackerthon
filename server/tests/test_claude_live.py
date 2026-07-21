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
    raw = await _provider().generate_quiz(ARTICLE_TITLE, PARAGRAPHS)

    quiz = raw["quiz"]
    assert 2 <= len(quiz) <= 4

    for item in quiz:
        assert 0 <= item["paragraphIndex"] < len(PARAGRAPHS)
        assert len(item["options"]) == 4
        assert 0 <= item["answerIndex"] < 4
        assert item["conceptTag"] and item["conceptTag"] != ARTICLE_TITLE
        # 한국어 출력 계약.
        assert any("가" <= ch <= "힣" for ch in item["question"])

        followups = item["followups"]
        assert len(followups) <= 1
        if followups:
            f1 = followups[0]
            assert f1["level"] == 1
            assert len(f1["options"]) == 4
            assert len(f1["followups"]) <= 1
            if f1["followups"]:
                assert f1["followups"][0]["level"] == 2


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
