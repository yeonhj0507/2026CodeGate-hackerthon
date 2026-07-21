"""공유 인증 의존성 — 담당3의 모든 도메인 라우트가 Depends(get_current_user) 로 재사용.

명세 §3.4, §4.1: 익스텐션·로컬 앱이 각자 독립 로그인하되(토큰 비공유),
서버는 토큰의 sub 로 동일 계정을 stateless 하게 식별한다(DB 조회 없음).
"""
from dataclasses import dataclass

import jwt
from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.core.errors import AppError
from app.core.security import decode_token

bearer_scheme = HTTPBearer(auto_error=True)


@dataclass
class CurrentUser:
    user_id: str
    client: str | None = None


async def get_current_user(
    cred: HTTPAuthorizationCredentials = Depends(bearer_scheme),
) -> CurrentUser:
    try:
        payload = decode_token(cred.credentials)
    except jwt.ExpiredSignatureError:
        raise AppError(status_code=401, code="TOKEN_EXPIRED", message="Access token expired")
    except jwt.PyJWTError:
        raise AppError(status_code=401, code="INVALID_TOKEN", message="Invalid access token")

    user_id = payload.get("sub")
    if not user_id:
        raise AppError(status_code=401, code="INVALID_TOKEN", message="Token missing subject")

    return CurrentUser(user_id=user_id, client=payload.get("client"))
