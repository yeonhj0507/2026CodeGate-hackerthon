"""설치 파일 다운로드 페이지.

`GET /download`      → 데스크톱 앱 설치 랜딩 페이지(HTML) 렌더.
`GET /download/win`  → 실제 설치 파일(.exe)로 302 리다이렉트.

실제 바이너리는 서버가 아니라 GitHub Releases 에 있다(Render 리눅스 컨테이너는 Windows
exe 를 만들 수도, 무료 플랜에서 영구 저장할 수도 없다). 리다이렉트 대상은
`settings.download_url` 로 주입 — 나중에 스토리지(R2 등)로 옮겨도 코드 변경이 없다.
"""
from fastapi import APIRouter
from fastapi.responses import HTMLResponse, RedirectResponse

from app.core.config import settings

router = APIRouter(tags=["download"])


@router.get("/download/win")
async def download_windows() -> RedirectResponse:
    """실제 설치 파일 위치로 리다이렉트(브라우저가 다운로드를 시작한다)."""
    # 302: 대상(릴리스 최신본)이 바뀔 수 있으므로 캐시 고정을 피한다.
    return RedirectResponse(url=settings.download_url, status_code=302)


_PAGE = """<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>Prober 다운로드</title>
<style>
  :root { color-scheme: light dark; }
  * { box-sizing: border-box; }
  body {
    margin: 0; min-height: 100vh; display: grid; place-items: center;
    font-family: -apple-system, "Segoe UI", Roboto, "Noto Sans KR", sans-serif;
    background: #0f1216; color: #e8ebf0;
    padding: 24px;
  }
  .card {
    width: 100%; max-width: 480px; text-align: center;
    background: #171b22; border: 1px solid #262c37; border-radius: 20px;
    padding: 40px 32px; box-shadow: 0 20px 60px rgba(0,0,0,.4);
  }
  .logo {
    width: 64px; height: 64px; margin: 0 auto 20px; border-radius: 16px;
    background: linear-gradient(135deg,#4f8cff,#8a5cff);
    display: grid; place-items: center; font-size: 32px; font-weight: 800; color: #fff;
  }
  h1 { margin: 0 0 8px; font-size: 24px; }
  .tagline { margin: 0 0 28px; color: #9aa4b2; font-size: 14px; line-height: 1.6; }
  .btn {
    display: inline-flex; align-items: center; gap: 10px; text-decoration: none;
    background: linear-gradient(135deg,#4f8cff,#6a7dff); color: #fff;
    font-size: 16px; font-weight: 700; padding: 15px 28px; border-radius: 12px;
    transition: transform .08s ease, box-shadow .2s ease;
    box-shadow: 0 8px 24px rgba(79,140,255,.35);
  }
  .btn:hover { transform: translateY(-1px); box-shadow: 0 10px 28px rgba(79,140,255,.45); }
  .btn:active { transform: translateY(0); }
  .meta { margin-top: 18px; color: #6d7684; font-size: 12.5px; line-height: 1.7; }
  .note {
    margin-top: 24px; padding: 14px 16px; text-align: left;
    background: #12161c; border: 1px solid #262c37; border-radius: 12px;
    color: #9aa4b2; font-size: 12.5px; line-height: 1.7;
  }
  .note b { color: #c7cfda; }
  #other { display: none; margin-top: 14px; color: #8a94a2; font-size: 12.5px; }
  code { background:#0d1013; padding:1px 6px; border-radius:6px; color:#c7cfda; }
</style>
</head>
<body>
  <main class="card">
    <div class="logo">P</div>
    <h1>Prober 데스크톱 앱</h1>
    <p class="tagline">기사를 읽으며 &ldquo;내가 무엇을 모르는지&rdquo;를 진단하고<br/>생각 지도로 쌓아주는 능동적 읽기 도우미</p>

    <a class="btn" href="/download/win" download>⬇ Windows용 다운로드</a>

    <p class="meta">Windows 10 / 11 (64-bit) · 설치 파일(.exe)</p>

    <p id="other">현재 Windows 전용입니다. Windows PC 에서 이 페이지를 다시 열어 주세요.</p>

    <div class="note">
      설치 시 <b>&ldquo;Windows의 PC 보호&rdquo;</b> 화면이 뜨면(미서명 설치기),
      <b>추가 정보 &rarr; 실행</b>을 눌러 진행하세요. 설치 후 시작 메뉴 또는 바탕화면의
      <code>Prober</code> 로 실행합니다.
    </div>
  </main>
  <script>
    // Windows 가 아니면 안내 문구를 노출한다(버튼은 그대로 두어 직접 받을 수도 있게).
    if (!/Windows|Win64|Win32/i.test(navigator.userAgent)) {
      document.getElementById('other').style.display = 'block';
    }
  </script>
</body>
</html>"""


@router.get("/download", response_class=HTMLResponse)
async def download_page() -> HTMLResponse:
    """설치 랜딩 페이지."""
    return HTMLResponse(content=_PAGE)
