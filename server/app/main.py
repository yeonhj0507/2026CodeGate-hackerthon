"""FastAPI 앱 진입점 — 담당2(인증)와 담당3(도메인)이 공유하는 하나의 앱."""
import logging

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from slowapi.errors import RateLimitExceeded

from app.auth.router import router as auth_router
from app.core.config import settings
from app.core.errors import register_error_handlers
from app.core.ratelimit import limiter
from app.download.router import router as download_router
from app.domain.explore.router import router as explore_router
from app.domain.quiz.router import router as quiz_router
from app.domain.scrap.router import router as scrap_router
from app.domain.thoughtmap.router import router as thoughtmap_router

# uvicorn 은 자기 로거만 설정하고 앱 로거는 손대지 않는다. 루트 기본값이 WARNING 이라
# 이게 없으면 app.* 의 logger.info(LLM 호출 계측 등)가 통째로 사라진다.
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)

app = FastAPI(title=settings.app_name)

# 크롬 익스텐션(content script)·로컬 앱이 브라우저/데스크톱에서 직접 호출한다.
app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=".*",
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- rate limiter 등록 ---
app.state.limiter = limiter


async def _rate_limit_handler(request: Request, exc: RateLimitExceeded) -> JSONResponse:
    # 통일 에러 포맷으로 429 반환.
    return JSONResponse(status_code=429, content={"error": {"code": "RATE_LIMITED", "message": "Too many requests"}})


app.add_exception_handler(RateLimitExceeded, _rate_limit_handler)

# --- 통일 에러 핸들러 (AppError / HTTPException / ValidationError) ---
register_error_handlers(app)

# --- 라우터 등록 ---
app.include_router(auth_router)
app.include_router(quiz_router)
app.include_router(scrap_router)
app.include_router(thoughtmap_router)
app.include_router(explore_router)
app.include_router(download_router)


@app.get("/health", tags=["health"])
async def health() -> dict:
    return {"status": "ok"}
