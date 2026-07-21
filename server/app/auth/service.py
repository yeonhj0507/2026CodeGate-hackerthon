"""계정 서비스 로직 (DB 접근 캡슐화)."""
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.models import User
from app.core.errors import AppError
from app.core.security import hash_password, verify_password


async def get_user_by_email(db: AsyncSession, email: str) -> User | None:
    result = await db.execute(select(User).where(User.email == email))
    return result.scalar_one_or_none()


async def get_user_by_id(db: AsyncSession, user_id: str) -> User | None:
    return await db.get(User, user_id)


async def create_user(db: AsyncSession, email: str, password: str, display_name: str | None) -> User:
    if await get_user_by_email(db, email) is not None:
        raise AppError(status_code=409, code="EMAIL_TAKEN", message="Email already registered")
    user = User(email=email, password_hash=hash_password(password), display_name=display_name)
    db.add(user)
    await db.commit()
    await db.refresh(user)
    return user


async def authenticate(db: AsyncSession, email: str, password: str) -> User:
    user = await get_user_by_email(db, email)
    # 이메일 존재 여부를 노출하지 않도록 동일 에러로 처리.
    if user is None or not verify_password(password, user.password_hash):
        raise AppError(status_code=401, code="INVALID_CREDENTIALS", message="Invalid email or password")
    return user


async def delete_user(db: AsyncSession, user_id: str) -> None:
    """계정 즉시 파기(기획서 §6 '탈퇴 시 즉시 파기').

    학습 데이터는 로컬 소유라 서버 파기 대상은 User(+잔여 TempScrap).
    TempScrap cascade 는 담당3 모델 확정 시 협의(§domain/README).
    """
    user = await get_user_by_id(db, user_id)
    if user is None:
        raise AppError(status_code=404, code="USER_NOT_FOUND", message="User not found")
    await db.delete(user)
    await db.commit()
