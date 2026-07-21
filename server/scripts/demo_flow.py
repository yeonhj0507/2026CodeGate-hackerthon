"""데모용 엔드투엔드 시나리오 (흐름 A → 흐름 B).

서버가 떠 있는 상태에서 실행한다.

    uvicorn app.main:app --reload      # 다른 터미널
    python scripts/demo_flow.py
"""

import asyncio
import json
import sys
import uuid

import httpx

BASE_URL = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8000"
USER = f"demo-{uuid.uuid4().hex[:8]}"

ARTICLE_TITLE = "한국은행, 기준금리 연 3.50% 동결"
ARTICLE_BODY = """\
한국은행 금융통화위원회가 기준금리를 연 3.50%로 동결했다. 여섯 차례 연속 동결이다.

동결 배경에는 물가와 성장 사이의 저울질이 있다. 소비자물가 상승률은 목표치에 근접했지만 내수 회복 속도는 여전히 더디다는 판단이 작용했다.

환율도 결정을 제약한 변수다. 금리를 내리면 원화 약세가 심해지고, 수입물가를 통해 국내 물가를 다시 자극할 수 있기 때문이다.

시장은 다음 분기 인하 가능성에 무게를 싣는다. 다만 국채금리에는 인하 기대가 이미 상당 부분 반영됐다는 분석도 나온다.
"""


def show(title: str, obj) -> None:
    print(f"\n=== {title} ===")
    print(json.dumps(obj, ensure_ascii=False, indent=2)[:2000])


async def main() -> None:
    async with httpx.AsyncClient(base_url=BASE_URL, timeout=60) as client:
        # 계정 생성 + 로그인 (담당2 /auth/*). 익스텐션·로컬앱은 각자 독립 로그인하지만
        # 데모에서는 하나의 토큰으로 두 흐름을 이어서 보여 준다.
        email, password = f"{USER}@example.com", "demo-password-1234"
        await client.post("/auth/signup", json={"email": email, "password": password})
        login = await client.post(
            "/auth/login", json={"email": email, "password": password, "client": "extension"}
        )
        login.raise_for_status()
        client.headers["Authorization"] = f"Bearer {login.json()['accessToken']}"
        print(f"로그인 완료: {email}")

        # 흐름 A-2: 퀴즈 생성
        quiz = (
            await client.post(
                "/quiz", json={"articleTitle": ARTICLE_TITLE, "articleBody": ARTICLE_BODY}
            )
        ).json()
        show("POST /quiz", quiz)

        # 흐름 A-3~4: 익스텐션이 채점한 결과를 스크랩으로 전송.
        # 첫 문항은 오답 → 선행개념 재질문까지 내려간 상황을 흉내 낸다.
        results = []
        for i, item in enumerate(quiz["quiz"]):
            correct = i != 0
            results.append(
                {
                    "conceptTag": item["conceptTag"],
                    "parentConcept": None,
                    "level": 0,
                    "correct": correct,
                }
            )
            if not correct and item["followups"]:
                f1 = item["followups"][0]
                results.append(
                    {
                        "conceptTag": f1["prereqConceptTag"],
                        "parentConcept": item["conceptTag"],
                        "level": 1,
                        "correct": False,
                    }
                )
                if f1["followups"]:
                    f2 = f1["followups"][0]
                    results.append(
                        {
                            "conceptTag": f2["prereqConceptTag"],
                            "parentConcept": f1["prereqConceptTag"],
                            "level": 2,
                            "correct": True,
                        }
                    )

        scrap = (
            await client.post(
                "/scrap",
                json={
                    "articleTitle": ARTICLE_TITLE,
                    "articleBody": ARTICLE_BODY,
                    "results": results,
                },
            )
        ).json()
        show("POST /scrap", scrap)

        # 흐름 B: 로컬앱 동기화 (빈 그래프에서 시작)
        sync = (
            await client.post(
                "/thoughtmap/update",
                json={
                    "graph": {"nodes": [], "edges": []},
                    "userContext": {
                        "preferredCategories": ["경제"],
                        "preferredKeywords": ["환율", "인플레이션"],
                    },
                },
            )
        ).json()
        show("POST /thoughtmap/update", sync)

        # 재동기화: 버퍼가 비었으므로 consumedScraps == 0
        again = (
            await client.post("/thoughtmap/update", json={"graph": sync["graph"]})
        ).json()
        print(f"\n두 번째 동기화 consumedScraps = {again['consumedScraps']} (0이어야 정상)")


if __name__ == "__main__":
    asyncio.run(main())
