"""/quiz — DB 불필요(서버는 퀴즈를 저장하지 않는다)."""

import pytest

from app.domain.quiz.service import split_paragraphs

ARTICLE_BODY = """\
한국은행이 기준금리를 연 3.50%로 동결했다. 시장의 예상과 대체로 부합하는 결정이었다.

동결 배경에는 물가와 성장 사이의 저울질이 있다. 소비자물가 상승률이 목표치에 근접했지만 내수 회복은 더디다는 판단이다.

환율도 변수다. 금리를 내리면 원화 약세가 심해져 수입물가를 통해 다시 물가를 자극할 수 있다.

시장은 다음 분기 인하 가능성에 무게를 두고 있다. 다만 국채금리는 이미 인하 기대를 상당 부분 반영했다는 분석도 나온다.
"""


def test_split_paragraphs_indexes_body():
    paragraphs = split_paragraphs(ARTICLE_BODY)
    assert len(paragraphs) == 4
    assert paragraphs[0].startswith("한국은행이 기준금리를")


def test_split_paragraphs_without_blank_lines():
    assert len(split_paragraphs("첫 문장이다. 두 번째 문장이다.")) == 2


@pytest.mark.asyncio
async def test_quiz_contract(client):
    res = await client.post(
        "/quiz", json={"articleTitle": "기준금리 동결", "articleBody": ARTICLE_BODY}
    )
    assert res.status_code == 200

    quiz = res.json()["quiz"]
    assert 2 <= len(quiz) <= 4

    paragraphs = split_paragraphs(ARTICLE_BODY)
    for item in quiz:
        assert {"claimId", "conceptTag", "anchorText", "paragraphIndex", "question",
                "options", "answerIndex", "explanation", "followups"} <= item.keys()
        assert 0 <= item["paragraphIndex"] < len(paragraphs)
        # anchorText 는 서버가 문단에서 직접 채운다 — 익스텐션 앵커 매칭의 보증.
        assert paragraphs[item["paragraphIndex"]].startswith(item["anchorText"])
        assert 0 <= item["answerIndex"] < len(item["options"])

        # 재질문은 최대 2단계.
        f1 = item["followups"]
        assert len(f1) <= 1
        if f1:
            assert f1[0]["level"] == 1
            f2 = f1[0]["followups"]
            assert len(f2) <= 1
            if f2:
                assert f2[0]["level"] == 2
                assert f2[0].get("followups", []) == []


@pytest.mark.asyncio
async def test_quiz_rejects_empty_body(client):
    res = await client.post("/quiz", json={"articleTitle": "빈 기사", "articleBody": "   "})
    assert res.status_code == 422
    assert res.json()["error"]["code"] == "EMPTY_ARTICLE"


def test_normalize_caps_the_number_of_items():
    """개수는 프롬프트로만 요청하고 있었다 — 모델이 더 내면 그대로 나갔다.

    strict 스키마가 maxItems 를 지원하지 않아(400) 서버가 잠근다.
    """
    from app.domain.quiz.service import MAX_QUIZ_ITEMS, _normalize

    paragraphs = split_paragraphs(ARTICLE_BODY)
    raw = {
        "quiz": [
            {
                "claimId": f"c{i}",
                "conceptTag": f"개념{i}",
                "paragraphIndex": 0,
                "question": "왜 그런가?",
                "options": ["가", "나", "다", "라"],
                "answerIndex": 0,
                "explanation": "설명",
                "followups": [],
            }
            for i in range(MAX_QUIZ_ITEMS + 3)
        ]
    }

    assert len(_normalize(raw, paragraphs).quiz) == MAX_QUIZ_ITEMS
