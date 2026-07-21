"""검색 결과에서 뉴스만 남기는 규칙 (네트워크·LLM 불필요).

`web_search` 를 그냥 돌리면 나무위키·네이버 지식백과·블로그가 상위에 올라온다.
추천 문구는 "읽을 만한 기사"인데 사전 항목이 뜨면 약속이 어긋난다.

도구에 `allowed_domains` 를 주기는 하지만 그건 힌트일 뿐이라, 결과를 한 번 더
거르는 이 함수가 최종 방어선이다.
"""

import pytest

from app.domain.search.claude_search import WEB_SEARCH_TOOL
from app.domain.search.news_domains import UNCRAWLABLE_DOMAINS, host_of, is_news


@pytest.mark.parametrize(
    "url",
    [
        "https://www.hani.co.kr/arti/economy/123.html",
        "https://biz.chosun.com/policy/123/",  # 서브도메인
        "https://n.yna.co.kr/view/AKR2026",
        "http://www.mk.co.kr/news/economy/1",
        "https://sedaily.com/NewsView/ABC",
    ],
)
def test_accepts_news_outlets(url: str):
    assert is_news(url)


@pytest.mark.parametrize(
    "url",
    [
        "https://namu.wiki/w/기준금리",
        "https://ko.wikipedia.org/wiki/환율",
        "https://terms.naver.com/entry.naver?docId=1",  # 지식백과
        "https://dict.naver.com/hanja",
        "https://blog.naver.com/someone/123",
        "https://brunch.co.kr/@x/1",
        "https://www.coupang.com/vp/products/1",
        "https://www.youtube.com/watch?v=1",
        "https://eiec.kdi.re.kr/material/1",  # 연구기관 자료
        "https://www.mofe.go.kr/1",  # 정부 부처
    ],
)
def test_rejects_everything_that_is_not_an_outlet(url: str):
    assert not is_news(url)


@pytest.mark.parametrize(
    "url",
    [
        "https://dic.hankyung.com/economy/view/?seq=1",  # 한경용어사전
        "https://terms.mk.co.kr/view.php?no=1",
        "https://blog.donga.com/x/1",
        "https://shop.chosun.com/item/1",
    ],
)
def test_rejects_non_article_sections_of_news_sites(url: str):
    """도메인은 언론사인데 내용은 사전·블로그·쇼핑인 경우.

    서브도메인을 통째로 인정했더니 실제 검색 결과가 한경용어사전으로 채워졌다.
    바로 그 사전을 빼려던 목적이 무너지므로 섹션 단위로 한 번 더 본다.
    """
    assert not is_news(url)


def test_still_accepts_real_news_subdomains():
    assert is_news("https://biz.chosun.com/policy/1")
    assert is_news("https://n.news.mk.co.kr/1")


def test_rejects_domains_that_merely_end_with_a_news_name():
    """'chosun.com.evil.kr' 처럼 접미사만 흉내 낸 주소에 속지 않는다."""
    assert not is_news("https://chosun.com.evil.kr/a")
    assert not is_news("https://notchosun.com/a")


def test_rejects_garbage():
    assert not is_news("")
    assert not is_news("not a url")


def test_host_is_trimmed_for_display():
    assert host_of("https://www.hani.co.kr/arti/1") == "hani.co.kr"
    assert host_of("https://biz.chosun.com/a") == "biz.chosun.com"


def test_tool_is_pointed_at_news_only():
    """도구 힌트와 사후 필터가 어긋나지 않아야 한다."""
    allowed = WEB_SEARCH_TOOL["allowed_domains"]
    assert allowed, "allowed_domains 가 비면 검색이 아무 데나 훑는다"
    assert all(is_news(f"https://{d}/x") for d in allowed)


def test_tool_never_asks_for_domains_that_block_the_crawler():
    """크롤러 차단 도메인이 하나라도 끼면 web_search 호출 전체가 400 으로 죽는다.

    일부만 걸러지는 게 아니라 검색이 통째로 실패한다. 실호출에서만 드러나는
    종류라 목록 수준에서 고정해 둔다.
    """
    allowed = set(WEB_SEARCH_TOOL["allowed_domains"])
    assert not (allowed & UNCRAWLABLE_DOMAINS)


def test_blocked_outlets_are_still_news():
    """크롤링이 막혔을 뿐 언론사는 맞다 — 제휴 데이터셋에 같은 도메인이 올 수 있다."""
    assert is_news("https://www.chosun.com/economy/1")
    assert is_news("https://www.yna.co.kr/view/1")
