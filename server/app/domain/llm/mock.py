"""결정론적 목 프로바이더.

Anthropic 키 없이도 `/quiz` → `/scrap` → `/thoughtmap/update` 전 구간이 돌아가게 한다.
같은 입력에는 항상 같은 출력을 내므로 테스트·데모에 그대로 쓸 수 있다.
"""

import hashlib
import re

# 개념어 후보로 쓰기 나쁜 흔한 조사·기능어. 목 전용 휴리스틱이다.
_STOPWORDS = {
    "그리고", "하지만", "그러나", "이번", "지난", "관련", "대한", "위해", "통해",
    "이라고", "따르면", "밝혔다", "말했다", "있다", "없다", "것으로", "때문에",
}


def _stable_index(seed: str, modulo: int) -> int:
    digest = hashlib.sha256(seed.encode("utf-8")).hexdigest()
    return int(digest[:8], 16) % modulo


def _concept_from(text: str, fallback: str) -> str:
    """문단에서 개념어처럼 보이는 토큰 하나를 결정론적으로 고른다."""
    tokens = [
        t
        for t in re.findall(r"[가-힣A-Za-z][가-힣A-Za-z0-9]{1,}", text)
        if len(t) >= 2 and t not in _STOPWORDS
    ]
    if not tokens:
        return fallback
    # 긴 토큰일수록 개념어일 확률이 높다. 동률은 등장 순서로 고정.
    tokens.sort(key=lambda t: (-len(t), text.index(t)))
    return tokens[0]


def _mcq(concept: str, stem: str, seed: str) -> dict:
    """정답 위치까지 결정론적인 4지선다를 만든다."""
    correct = f"{concept}이(가) 원인으로 작용해 결과가 달라졌기 때문"
    distractors = [
        f"{concept}과(와) 무관하게 우연히 발생한 일이기 때문",
        f"{concept}의 정의가 기사에서 바뀌었기 때문",
        f"{concept}이(가) 결과가 나온 뒤에 뒤따라 생긴 현상이기 때문",
    ]
    answer_index = _stable_index(seed, 4)
    options = distractors[:]
    options.insert(answer_index, correct)
    return {
        "question": stem,
        "options": options,
        "answerIndex": answer_index,
        "explanation": (
            f"{concept}은(는) 이 대목의 인과를 이해하는 열쇠다. "
            f"{concept}이(가) 어떤 조건에서 어떤 결과로 이어지는지를 잡으면 나머지 서술이 따라온다."
        ),
    }


class MockProvider:
    async def generate_quiz(self, title: str, paragraphs: list[str]) -> dict:
        if not paragraphs:
            return {"quiz": []}

        # 정보량이 많은 문단부터 2~4개. 인덱스 순서를 보존해 읽기 흐름과 맞춘다.
        ranked = sorted(range(len(paragraphs)), key=lambda i: -len(paragraphs[i]))
        count = max(2, min(4, len(paragraphs)))
        chosen = sorted(ranked[:count])

        quiz = []
        for n, idx in enumerate(chosen, start=1):
            para = paragraphs[idx]
            concept = _concept_from(para, fallback=_concept_from(title, f"핵심개념{n}"))
            prereq1 = f"{concept}의 작동 원리"
            prereq2 = f"{concept} 기본 용어"

            item = {
                "claimId": f"c{n}",
                "conceptTag": concept,
                "paragraphIndex": idx,
                **_mcq(concept, f"이 문단에서 '{concept}'이(가) 결론으로 이어지는 이유는?", f"{title}|{idx}"),
                "followups": [
                    {
                        "level": 1,
                        "prereqConceptTag": prereq1,
                        **_mcq(prereq1, f"'{prereq1}'을(를) 가장 잘 설명한 것은?", f"{title}|{idx}|1"),
                        "followups": [
                            {
                                "level": 2,
                                "prereqConceptTag": prereq2,
                                **_mcq(
                                    prereq2,
                                    f"'{prereq2}'의 의미로 알맞은 것은?",
                                    f"{title}|{idx}|2",
                                ),
                            }
                        ],
                    }
                ],
            }
            quiz.append(item)

        return {"quiz": quiz}

    async def summarize_concepts(
        self, concepts: list[str], article_titles: dict[str, list[str]]
    ) -> dict[str, str]:
        out: dict[str, str] = {}
        for concept in concepts:
            sources = article_titles.get(concept) or []
            where = f" 「{sources[0]}」 등 {len(sources)}개 기사에서 등장했다." if sources else ""
            out[concept] = (
                f"{concept}: 이 개념은 관련 서술의 인과를 잇는 고리다. "
                f"정의와 전제 조건을 먼저 잡고, 어떤 결과로 이어지는지를 확인하면 이해가 열린다.{where}"
            )
        return out
