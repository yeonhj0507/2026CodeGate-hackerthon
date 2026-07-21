"""서버 전역 설정. `.env` 또는 환경변수에서 로드한다."""

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "postgresql+asyncpg://prober:prober@localhost:5432/prober"

    # "mock" | "claude". 키 확보 전에는 mock 으로 전 파이프라인이 동작한다.
    llm_provider: str = "mock"
    anthropic_api_key: str = ""
    anthropic_model: str = "claude-sonnet-5"

    # 스크랩 버퍼 무한 누적 방지 (명세 §9)
    scrap_buffer_ttl_days: int = 7
    scrap_buffer_max_rows: int = 200


@lru_cache
def get_settings() -> Settings:
    return Settings()
