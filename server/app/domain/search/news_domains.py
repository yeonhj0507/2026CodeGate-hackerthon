"""뉴스로 인정할 도메인 목록.

`web_search` 를 그냥 돌리면 나무위키·백과사전·블로그가 상위에 올라온다. 추천 문구는
"읽을 만한 기사"인데 사전 항목이 뜨면 약속이 어긋난다. 그래서 **언론사 도메인만** 남긴다.

허용 목록(allowlist)을 쓴 이유: 차단 목록은 새 사전·위키가 생길 때마다 뚫린다.
반대로 허용 목록은 빠지는 언론사가 생길 수 있지만, 검색은 제휴 데이터셋이 모자랄 때만
쓰는 **보충 수단**이라 적게 나오는 쪽이 잘못 나오는 쪽보다 낫다.
"""

from urllib.parse import urlparse

# 주요 국내 언론사. 서브도메인은 접미사 일치로 함께 걸린다(biz.chosun.com 등).
NEWS_DOMAINS: tuple[str, ...] = (
    # 통신사
    "yna.co.kr",
    "yonhapnews.co.kr",
    "newsis.com",
    "news1.kr",
    # 종합일간
    "chosun.com",
    "joongang.co.kr",
    "donga.com",
    "hani.co.kr",
    "khan.co.kr",
    "hankookilbo.com",
    "seoul.co.kr",
    "kmib.co.kr",
    "munhwa.com",
    "segye.com",
    "hankyung.com",
    # 경제·산업
    "mk.co.kr",
    "sedaily.com",
    "edaily.co.kr",
    "mt.co.kr",
    "fnnews.com",
    "asiae.co.kr",
    "heraldcorp.com",
    "etnews.com",
    "businesspost.co.kr",
    "thebell.co.kr",
    "dt.co.kr",
    "inews24.com",
    "wowtv.co.kr",
    "sbsbiz.co.kr",
    "biz.heraldcorp.com",
    # 방송
    "ytn.co.kr",
    "kbs.co.kr",
    "imbc.com",
    "sbs.co.kr",
    "jtbc.co.kr",
    "mbn.co.kr",
    "channelA.io",
    # 기타 정론
    "ohmynews.com",
    "pressian.com",
    "mediatoday.co.kr",
    "hankyoreh.com",
    "bbc.com",
)

# Anthropic 크롤러(user agent)를 막아 둔 곳.
#
# 이 도메인이 `allowed_domains` 에 하나라도 들어가면 web_search 호출 자체가
# 400 으로 죽는다("The following domains are not accessible to our user agent").
# 일부만 걸러지는 게 아니라 **검색 전체가 실패**하므로 반드시 빼야 한다.
# 실호출 테스트(test_claude_live)로 확인한 목록이다.
#
# 다만 [is_news] 에서는 계속 뉴스로 인정한다 — 크롤링이 막혔을 뿐 언론사는 맞고,
# 제휴 데이터셋에 같은 도메인이 들어올 수 있다.
UNCRAWLABLE_DOMAINS: frozenset[str] = frozenset(
    {
        "bbc.com",
        "chosun.com",
        "donga.com",
        "hani.co.kr",
        "joongang.co.kr",
        "jtbc.co.kr",
        "kbs.co.kr",
        "mbn.co.kr",
        "mk.co.kr",
        "yna.co.kr",
        "yonhapnews.co.kr",
    }
)

# web_search 의 allowed_domains 에 넣을 목록 — 실제로 훑을 수 있는 곳만.
SEARCHABLE_NEWS_DOMAINS: tuple[str, ...] = tuple(
    d for d in NEWS_DOMAINS if d not in UNCRAWLABLE_DOMAINS
)


def host_of(url: str) -> str:
    """표시용 출처. 'https://www.hani.co.kr/...' → 'hani.co.kr'"""
    try:
        host = urlparse(url).netloc.lower()
    except Exception:  # noqa: BLE001
        return ""
    if host.startswith("www."):
        host = host[4:]
    # 포트가 붙어 오는 경우가 있다.
    return host.split(":")[0]


# 언론사가 기사가 아닌 것을 올려 두는 서브도메인.
#
# 서브도메인을 통째로 인정하면 여기까지 딸려 온다. 실제로 'dic.hankyung.com'
# (한경용어사전)이 검색 결과를 채운 적이 있다 — 도메인만 보면 언론사지만
# 내용은 용어사전이라, 바로 그 사전을 빼려던 목적이 무너진다.
NON_ARTICLE_SUBDOMAINS: frozenset[str] = frozenset(
    {
        "dic",
        "dict",
        "dictionary",
        "terms",
        "encyclopedia",
        "wiki",
        "blog",
        "blogs",
        "shop",
        "store",
        "market",
        "book",
        "books",
        "academy",
        "campus",
        "event",
        "ad",
        "ads",
    }
)


def is_news(url: str) -> bool:
    """언론사의 **기사** 주소인가.

    서브도메인(biz.chosun.com)은 인정하되, 사전·블로그·쇼핑 섹션은 뺀다.
    """
    host = host_of(url)
    if not host:
        return False

    matched = any(
        host == domain.lower() or host.endswith("." + domain.lower())
        for domain in NEWS_DOMAINS
    )
    if not matched:
        return False

    first_label = host.split(".", 1)[0]
    return first_label not in NON_ARTICLE_SUBDOMAINS
