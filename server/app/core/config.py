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

    # --- LLM (담당3: 퀴즈 생성·개념 재요약) ---
    # "mock" | "claude". 키 확보 전에는 mock 으로 전 파이프라인이 동작한다.
    llm_provider: str = "mock"
    anthropic_api_key: str = ""
    anthropic_model: str = "claude-sonnet-5"

    # --- 스크랩 버퍼 무한 누적 방지 (명세 §9) ---
    scrap_buffer_ttl_days: int = 7
    scrap_buffer_max_rows: int = 200


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
