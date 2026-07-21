# domain/ — 담당3 소관 (퀴즈 / 스크랩 / 생각지도)

이 디렉터리는 담당3(도메인 로직: `/quiz`, `/scrap`, `/thoughtmap/update`)의 공간입니다.
담당2(인증)는 여기 파일을 만들지 않습니다.

## 담당2가 제공하는 공유 자산 (그대로 재사용하세요)

- **DB Base / 세션**: `app.core.db` 의 `Base`(선언적 베이스), `get_db`(AsyncSession 의존성).
  도메인 모델도 **반드시 이 `Base`를 상속**해야 같은 Alembic 마이그레이션 체인을 공유합니다.
- **인증 의존성**: `app.core.deps.get_current_user` → `CurrentUser(user_id, client)`.
  모든 도메인 라우트에 `Depends(get_current_user)` 를 붙이고, **항상 `current_user.user_id` 기준으로만**
  조회/쓰기 하세요(계정 단위 격리, 명세 §4.5 보안).
- **에러 포맷**: `app.core.errors.AppError(status_code, code, message)` 를 raise 하면
  `{"error": {"code": ..., "message": ...}}` 형태로 통일 응답됩니다.

## 도메인 모델 추가 시 체크리스트

1. `app/domain/models.py` 에 모델 작성 (`from app.core.db import Base` 상속).
2. `server/alembic/env.py` 에 모델 import 한 줄 추가 (주석 위치 참고) → autogenerate 인식.
3. `alembic revision --autogenerate -m "..."` 로 마이그레이션 생성.
4. 라우터를 `app/main.py` 에 `include_router` 로 등록.

## 협의 필요 (담당2 ↔ 담당3)

- 회원 탈퇴(`DELETE /auth/me`) 시 남은 `TempScrap` 등 도메인 데이터 삭제 훅/cascade 규약.
