"""애플리케이션 설정. `.env` 에서 로드 (pydantic-settings)."""
from functools import lru_cache
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore", case_sensitive=False)

    # --- Database ---
    database_url: str = "postgresql+asyncpg://postgres:postgres@localhost:5432/prober"

    @field_validator("database_url")
    @classmethod
    def _normalize_db_url(cls, v: str) -> str:
        """매니지드 Postgres(Render 등)가 주는 URL 을 asyncpg 용으로 정규화한다.

        - `postgres://` · `postgresql://` (드라이버 미지정) → `postgresql+asyncpg://`.
          Render/Heroku 는 이 형태로 DATABASE_URL 을 준다.
        - libpq 전용 쿼리(`sslmode`·`channel_binding`) 제거 — asyncpg 는 이 파라미터를
          모르며, SSL 은 db.py 의 async_engine_options 가 connect_args 로 처리한다
          (Supabase 호스트 자동 감지 또는 DB_REQUIRE_SSL=1).
        """
        if v.startswith("postgres://"):
            v = "postgresql://" + v[len("postgres://"):]
        if v.startswith("postgresql://"):
            v = "postgresql+asyncpg://" + v[len("postgresql://"):]
        if v.startswith("postgresql+asyncpg://"):
            parts = urlsplit(v)
            if parts.query:
                kept = [(k, val) for k, val in parse_qsl(parts.query)
                        if k not in ("sslmode", "channel_binding")]
                v = urlunsplit((parts.scheme, parts.netloc, parts.path,
                                urlencode(kept), parts.fragment))
        return v

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
    anthropic_model: str = "claude-opus-4-8"

    # --- 기사 검색 (네이버 뉴스 검색 API) ---
    #
    # 원래 Claude 의 web_search 로 찾았는데 호출당 9분·입력 1만9천 토큰까지 늘어나
    # 동기화 응답 시간과 비용을 혼자 지배했다. 뉴스 검색은 전용 API 가 훨씬 빠르고
    # 싸다(무료 할당 일 25,000회). 키가 없으면 검색 없이 제휴 데이터셋만 쓴다 —
    # 추천 기사는 부가 기능이라 없어도 동기화는 성립한다.
    naver_client_id: str = ""
    naver_client_secret: str = ""

    # --- 스크랩 버퍼 무한 누적 방지 (명세 §9) ---
    scrap_buffer_ttl_days: int = 7
    scrap_buffer_max_rows: int = 200


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
