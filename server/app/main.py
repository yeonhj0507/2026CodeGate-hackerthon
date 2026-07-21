"""프로버 백엔드 서버.

담당2(계정/인증)와 **같은 FastAPI 앱**을 공유한다. auth 라우터가 준비되면
아래 include_router 에 한 줄 추가하면 된다.
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.errors import register_error_handlers
from app.domain.quiz.router import router as quiz_router
from app.domain.scrap.router import router as scrap_router
from app.domain.thoughtmap.router import router as thoughtmap_router

app = FastAPI(title="Prober API", version="0.1.0")

# 크롬 익스텐션(content script)·로컬앱에서 직접 호출한다.
app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=".*",
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

register_error_handlers(app)

app.include_router(quiz_router)
app.include_router(scrap_router)
app.include_router(thoughtmap_router)
# TODO(담당2): app.include_router(auth_router)


@app.get("/health", tags=["meta"])
async def health() -> dict:
    return {"status": "ok"}
