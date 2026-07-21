"""퀴즈 스트리밍 (DB 불필요, LLM 은 mock).

스트리밍은 "같은 결과를 더 일찍 준다"가 전부다. 그래서 배치와 **결과가 같은지**를
가장 먼저 못 박는다 — 여기가 갈라지면 사용자는 기사마다 다른 퀴즈를 받게 된다.
"""

import pytest

from app.core.errors import AppError
from app.domain.llm.mock import MockProvider
from app.domain.quiz import service

TITLE = "한은, 기준금리 3.5% 동결"
BODY = """한국은행 금융통화위원회가 기준금리를 연 3.5%로 동결했다. 아홉 차례 연속 같은 결정이다.

금통위는 물가 상승률이 목표에 수렴하고 있다면서도 환율 변동성과 가계부채를 함께 고려했다고 밝혔다.

원·달러 환율은 1,390원대에서 등락하고 있다. 금리를 내리면 내외 금리차가 벌어져 자본 유출 압력이 생긴다.

가계부채도 변수다. 지난달 주택담보대출은 한 달 만에 5조원 넘게 늘었다.

실질금리는 명목금리에서 물가상승률을 뺀 값이다. 물가가 떨어지면 동결해도 긴축 효과가 커진다."""


async def collect(title=TITLE, body=BODY, llm=None):
    return [item async for item in service.stream_quiz(title, body, llm or MockProvider())]


@pytest.mark.asyncio
async def test_stream_matches_batch():
    """스트리밍과 배치가 같은 문항을 같은 순서로 낸다."""
    service._cache.clear()
    streamed = await collect()

    service._cache.clear()
    batched = await service.generate_quiz(TITLE, BODY, MockProvider())

    assert [i.model_dump() for i in streamed] == [i.model_dump() for i in batched.quiz]


@pytest.mark.asyncio
async def test_yields_before_finishing():
    """핵심 목적 — 마지막 문항을 기다리지 않고 첫 문항이 나와야 한다."""
    service._cache.clear()
    agen = service.stream_quiz(TITLE, BODY, MockProvider())

    first = await agen.__anext__()

    assert first.question
    assert first.anchorText  # 서버가 문단에서 직접 채운 앵커
    await agen.aclose()


@pytest.mark.asyncio
async def test_each_item_is_normalized():
    """배치와 같은 정규화를 원소 단위로 태운다(앵커 주입·범위 클램프·깊이 제한)."""
    service._cache.clear()
    items = await collect()

    assert items
    for item in items:
        assert 0 <= item.answerIndex < len(item.options)
        assert item.paragraphIndex >= 0
        for f1 in item.followups:
            assert f1.level == 1
            for f2 in f1.followups:
                assert f2.level == 2
                assert f2.followups == []  # 깊이 2 에서 끊긴다


@pytest.mark.asyncio
async def test_second_call_is_served_from_cache():
    service._cache.clear()
    first = await collect()
    second = await collect()

    assert [i.model_dump() for i in second] == [i.model_dump() for i in first]


@pytest.mark.asyncio
async def test_empty_article_raises_before_any_item():
    service._cache.clear()
    with pytest.raises(AppError) as err:
        await collect(body="   ")
    assert err.value.code == "EMPTY_ARTICLE"


@pytest.mark.asyncio
async def test_partial_stream_is_not_cached():
    """중간에 끊긴 결과를 캐시에 남기면 다음 독자가 반쪽 퀴즈를 받는다."""
    service._cache.clear()

    agen = service.stream_quiz(TITLE, BODY, MockProvider())
    await agen.__anext__()
    await agen.aclose()  # 첫 문항만 받고 이탈

    assert service._cache == {}
