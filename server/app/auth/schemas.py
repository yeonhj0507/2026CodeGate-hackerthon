"""Pydantic v2 스키마. 응답은 camelCase alias 로 직렬화(FastAPI 기본 by_alias)."""
from pydantic import BaseModel, ConfigDict, EmailStr, Field


class SignupIn(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    display_name: str | None = Field(default=None, max_length=50)


class SignupOut(BaseModel):
    user_id: str = Field(serialization_alias="userId")


class LoginIn(BaseModel):
    email: EmailStr
    password: str
    client: str | None = None  # "extension" | "local" (감사/분석용, 권한 차이 없음)


class TokenOut(BaseModel):
    access_token: str = Field(serialization_alias="accessToken")
    expires_in: int = Field(serialization_alias="expiresIn")
    user_id: str = Field(serialization_alias="userId")


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    user_id: str = Field(validation_alias="id", serialization_alias="userId")
    email: EmailStr
    display_name: str | None = Field(default=None, serialization_alias="displayName")
