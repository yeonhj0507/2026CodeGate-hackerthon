"""애플리케이션 설정. `.env` 에서 로드 (pydantic-settings)."""
from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore", case_sensitive=False)

    # --- Database ---
    database_url: str = "postgresql+asyncpg://postgres:postgres@localhost:5432/prober"

    # --- JWT ---
    jwt_secret: str = "dev-insecure-secret-change-me"
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 60 * 24  # 24h (데모 편의)

    # --- App ---
    app_name: str = "Prober Auth Service"


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
