"""인증 의존성 — **개발용 스텁**.

담당2(구현계획② §3.4)가 JWT 검증 구현을 넣을 자리다. 도메인 라우트는 이미
`Depends(get_current_user)` 로 붙어 있으므로 이 함수 본문만 교체하면 된다.

개발 중에는 `X-User-Id` 헤더로 계정을 흉내 낸다. 헤더가 없으면 "dev-user".
"""

from fastapi import Header
from pydantic import BaseModel


class CurrentUser(BaseModel):
    user_id: str
    client: str | None = None


async def get_current_user(
    x_user_id: str = Header(default="dev-user", alias="X-User-Id"),
    x_client: str | None = Header(default=None, alias="X-Client"),
) -> CurrentUser:
    # TODO(담당2): HTTPBearer + decode_token 으로 교체. 반환 타입은 유지한다.
    return CurrentUser(user_id=x_user_id, client=x_client)
