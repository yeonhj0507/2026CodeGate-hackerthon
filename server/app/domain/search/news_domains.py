"""검색 결과 표시용 출처 이름.

한때 이 파일에는 언론사 허용목록(42곳)과 크롤러 차단 목록이 있었다. Claude 의
`web_search` 로 기사를 찾던 시절, 나무위키·용어사전·블로그가 상위를 채우는 걸 막으려고
`allowed_domains` 로 도메인을 좁혔던 잔재다.

그 접근은 두 번 물렸다.

1. 차단 도메인이 목록에 하나라도 들어가면 web_search 호출 **전체가 400** 으로 죽었다.
2. 도메인을 좁힐수록 모델이 검색을 반복해 느려지고 비싸졌다(59초 → 533초, 입력 1만9천 토큰).

지금은 뉴스 검색 엔진(NAVER API HUB)을 쓴다. 애초에 뉴스만 돌려주므로 필터가 필요 없다.
남은 건 표시용 호스트 추출뿐이다.
"""

from urllib.parse import urlparse


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
