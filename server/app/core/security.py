"""비밀번호 해시 + JWT 발급/검증. (명세 §3.3, §3.5)"""
from datetime import datetime, timedelta, timezone

import jwt
from passlib.context import CryptContext

from app.core.config import settings

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)


def create_access_token(user_id: str, client: str | None = None) -> tuple[str, int]:
    """access 토큰과 만료(초)를 반환.

    페이로드: { sub, client, iat, exp }.
    익스텐션·로컬 앱이 각자 로그인해 각자 토큰을 보유하며(토큰 비공유),
    서버는 sub 로 동일 계정을 식별하는 stateless 검증만 한다(명세 §3.3).
    client 는 감사/분석용 클레임일 뿐 권한 차이는 없다.
    """
    expires_in = settings.access_token_expire_minutes * 60
    now = datetime.now(timezone.utc)
    payload = {
        "sub": user_id,
        "client": client,
        "iat": now,
        "exp": now + timedelta(seconds=expires_in),
    }
    token = jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)
    return token, expires_in


def decode_token(token: str) -> dict:
    """서명·만료 검증. 실패 시 jwt 예외를 raise (호출부에서 401 로 변환)."""
    return jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
