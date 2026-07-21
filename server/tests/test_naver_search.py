"""네이버 뉴스 검색 프로바이더 (네트워크·LLM 불필요).

HTTP 는 스텁으로 갈아 끼우고 **응답을 어떻게 해석하는지**만 본다.
검색은 부가 기능이라 어떤 실패도 동기화를 막으면 안 된다 — 그 계약도 함께 고정한다.
"""

import httpx
import pytest

from app.core.config import get_settings
from app.domain.search.naver_search import NaverSearchProvider, _plain

ITEM = {
    "title": "한은, <b>기준금리</b> 동결&hellip;물가와 성장 사이",
    "originallink": "https://www.hankyung.com/article/2026010112345",
    "link": "https://n.news.naver.com/mnews/article/015/0001",
    "description": "금통위가 <b>기준금리</b>를 연 3.50%로 묶었다.",
    "pubDate": "Mon, 01 Jan 2026 09:00:00 +0900",
}


@pytest.fixture(autouse=True)
def _configured(monkeypatch):
    """키가 설정된 상태를 만든다. get_settings 는 lru_cache 라 캐시를 비운다."""
    monkeypatch.setenv("NAVER_CLIENT_ID", "id")
    monkeypatch.setenv("NAVER_CLIENT_SECRET", "secret")
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def _stub(monkeypatch, *, items=None, raises=None, status=200, capture=None):
    async def fake_get(self, url, **kwargs):
        if capture is not None:
            capture.update(kwargs)
        if raises is not None:
            raise raises
        return httpx.Response(
            status,
            json={"items": items if items is not None else []},
            request=httpx.Request("GET", url),
        )

    monkeypatch.setattr(httpx.AsyncClient, "get", fake_get)


async def test_maps_an_item_to_the_contract(monkeypatch):
    _stub(monkeypatch, items=[ITEM])

    out = await NaverSearchProvider().search_articles(["기준금리"], 3)

    article = out[0]
    # 강조 태그와 HTML 엔티티가 벗겨져야 카드에 그대로 쓸 수 있다.
    assert article.title == "한은, 기준금리 동결…물가와 성장 사이"
    assert "<b>" not in article.summary
    # 네이버 링크가 아니라 실제 언론사 주소를 쓴다.
    assert article.url == ITEM["originallink"]
    assert article.publisher == "hankyung.com"


async def test_falls_back_to_naver_link_when_original_is_missing(monkeypatch):
    _stub(monkeypatch, items=[{**ITEM, "originallink": ""}])

    out = await NaverSearchProvider().search_articles(["기준금리"], 3)

    assert out[0].url == ITEM["link"]


async def test_respects_the_limit_and_drops_duplicates(monkeypatch):
    _stub(monkeypatch, items=[ITEM, ITEM, {**ITEM, "originallink": "https://a.co/1"}])

    out = await NaverSearchProvider().search_articles(["기준금리"], 2)

    assert len(out) == 2
    assert len({a.url for a in out}) == 2


async def test_skips_items_without_a_usable_url_or_title(monkeypatch):
    _stub(
        monkeypatch,
        items=[
            {**ITEM, "originallink": "", "link": ""},
            {**ITEM, "title": ""},
            ITEM,
        ],
    )

    out = await NaverSearchProvider().search_articles(["기준금리"], 5)

    assert [a.url for a in out] == [ITEM["originallink"]]


async def test_sends_the_concepts_as_one_query(monkeypatch):
    captured: dict = {}
    _stub(monkeypatch, items=[], capture=captured)

    await NaverSearchProvider().search_articles(["기준금리", "환율", "물가", "고용"], 3)

    # 개념이 많아도 질의가 산만해지지 않게 앞의 몇 개만 쓴다.
    assert captured["params"]["query"] == "기준금리 환율 물가"


async def test_network_failure_is_swallowed(monkeypatch):
    """추천은 부가 기능이다 — 검색이 죽어도 동기화는 계속돼야 한다."""
    _stub(monkeypatch, raises=httpx.ConnectError("boom"))

    assert await NaverSearchProvider().search_articles(["기준금리"], 3) == []


async def test_http_error_is_swallowed(monkeypatch):
    _stub(monkeypatch, status=429)

    assert await NaverSearchProvider().search_articles(["기준금리"], 3) == []


async def test_without_a_key_it_does_not_call_out(monkeypatch):
    """키가 없으면 조용히 넘어간다. 제휴 데이터셋만으로도 추천은 성립한다."""
    monkeypatch.setenv("NAVER_CLIENT_ID", "")
    monkeypatch.setenv("NAVER_CLIENT_SECRET", "")
    get_settings.cache_clear()

    called = False

    async def fail(self, url, **kwargs):
        nonlocal called
        called = True
        raise AssertionError("키가 없는데 호출했다")

    monkeypatch.setattr(httpx.AsyncClient, "get", fail)

    assert await NaverSearchProvider().search_articles(["기준금리"], 3) == []
    assert not called


async def test_empty_input_is_a_no_op(monkeypatch):
    _stub(monkeypatch, items=[ITEM])

    assert await NaverSearchProvider().search_articles([], 3) == []
    assert await NaverSearchProvider().search_articles(["기준금리"], 0) == []


def test_plain_strips_markup_and_entities():
    assert _plain("<b>금리</b>&amp;환율") == "금리&환율"
    assert _plain("") == ""
