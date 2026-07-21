"""통일 에러 포맷 + 예외 핸들러. (담당2·담당3 공유, 명세 §8 에러 포맷)

모든 에러 응답: {"error": {"code": "...", "message": "..."}}
"""
from fastapi import FastAPI, Request
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException


class AppError(Exception):
    """도메인/인증 로직에서 raise 하는 통일 에러. 담당3도 그대로 사용."""

    def __init__(self, status_code: int, code: str, message: str):
        self.status_code = status_code
        self.code = code
        self.message = message


def _body(code: str, message: str, **extra) -> dict:
    err = {"code": code, "message": message}
    err.update(extra)
    return {"error": err}


async def _app_error_handler(request: Request, exc: AppError) -> JSONResponse:
    return JSONResponse(status_code=exc.status_code, content=_body(exc.code, exc.message))


async def _http_exception_handler(request: Request, exc: StarletteHTTPException) -> JSONResponse:
    # HTTPBearer(auto_error=True) 의 401 등 표준 HTTP 예외도 통일 포맷으로.
    return JSONResponse(status_code=exc.status_code, content=_body("HTTP_ERROR", str(exc.detail)))


async def _validation_exception_handler(request: Request, exc: RequestValidationError) -> JSONResponse:
    return JSONResponse(
        status_code=422,
        content=_body("VALIDATION_ERROR", "Request validation failed", details=jsonable_encoder(exc.errors())),
    )


def register_error_handlers(app: FastAPI) -> None:
    app.add_exception_handler(AppError, _app_error_handler)
    app.add_exception_handler(StarletteHTTPException, _http_exception_handler)
    app.add_exception_handler(RequestValidationError, _validation_exception_handler)
