"""계정 서비스 로직 (DB 접근 캡슐화)."""
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.models import User
from app.core.errors import AppError
from app.core.security import hash_password, verify_password
# 탈퇴 시 도메인 잔여 버퍼까지 파기하기 위한 참조. domain 은 auth 를 import 하지
# 않으므로 순환은 생기지 않는다.
from app.domain.models import TempScrap


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

    학습 데이터의 원본은 로컬 소유라 서버 파기 대상은 User + 잔여 TempScrap 이다.
    `temp_scraps.user_id` 는 FK 가 아니라 문자열이라 DB cascade 가 걸리지 않으므로,
    계정과 **같은 트랜잭션에서** 직접 지운다. 이걸 빠뜨리면 탈퇴 후에도 기사 원문과
    답변 기록이 버퍼 TTL(기본 7일) 동안 서버에 남는다.

    도메인 테이블이 늘어나면 여기에 함께 추가해야 한다(담당2 ↔ 담당3 규약).
    """
    user = await get_user_by_id(db, user_id)
    if user is None:
        raise AppError(status_code=404, code="USER_NOT_FOUND", message="User not found")

    await db.execute(delete(TempScrap).where(TempScrap.user_id == user_id))
    await db.delete(user)
    await db.commit()
