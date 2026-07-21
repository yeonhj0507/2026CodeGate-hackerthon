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


def is_news(url: str) -> bool:
    """언론사 도메인인가. 서브도메인(biz.chosun.com)도 인정한다."""
    host = host_of(url)
    if not host:
        return False
    return any(
        host == domain.lower() or host.endswith("." + domain.lower())
        for domain in NEWS_DOMAINS
    )
