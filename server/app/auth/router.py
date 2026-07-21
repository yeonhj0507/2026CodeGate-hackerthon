"""인증/계정 라우터. (명세 §4.1, API 표 §8)

엔드포인트:
  POST   /auth/signup   회원가입
  POST   /auth/login    로그인 → JWT
  GET    /auth/me       내 정보 (Bearer)
  DELETE /auth/me       탈퇴 즉시 파기 (Bearer)

/auth/refresh 는 데모 스코프에서 생략(설계 §3.3). 도입 시 refresh 화이트리스트 테이블 추가.
"""
from fastapi import APIRouter, Depends, Request, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import service
from app.auth.schemas import LoginIn, SignupIn, SignupOut, TokenOut, UserOut
from app.core.db import get_db
from app.core.deps import CurrentUser, get_current_user
from app.core.errors import AppError
from app.core.ratelimit import limiter
from app.core.security import create_access_token

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/signup", response_model=SignupOut, status_code=status.HTTP_201_CREATED)
@limiter.limit("10/minute")
async def signup(request: Request, body: SignupIn, db: AsyncSession = Depends(get_db)) -> SignupOut:
    user = await service.create_user(db, body.email, body.password, body.display_name)
    return SignupOut(user_id=user.id)


@router.post("/login", response_model=TokenOut)
@limiter.limit("10/minute")
async def login(request: Request, body: LoginIn, db: AsyncSession = Depends(get_db)) -> TokenOut:
    user = await service.authenticate(db, body.email, body.password)
    token, expires_in = create_access_token(user.id, body.client)
    return TokenOut(access_token=token, expires_in=expires_in, user_id=user.id)


@router.get("/me", response_model=UserOut)
async def me(
    current: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> UserOut:
    user = await service.get_user_by_id(db, current.user_id)
    if user is None:
        raise AppError(status_code=404, code="USER_NOT_FOUND", message="User not found")
    return user


@router.delete("/me", status_code=status.HTTP_204_NO_CONTENT)
async def delete_me(
    current: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> None:
    await service.delete_user(db, current.user_id)
