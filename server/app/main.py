"""FastAPI 앱 진입점 — 담당2(인증)와 담당3(도메인)이 공유하는 하나의 앱."""
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from slowapi.errors import RateLimitExceeded

from app.auth.router import router as auth_router
from app.core.config import settings
from app.core.errors import register_error_handlers
from app.core.ratelimit import limiter

app = FastAPI(title=settings.app_name)

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
# 담당3 도메인 라우터는 여기에 추가:
# from app.domain.router import router as domain_router
# app.include_router(domain_router)


@app.get("/health", tags=["health"])
async def health() -> dict:
    return {"status": "ok"}
