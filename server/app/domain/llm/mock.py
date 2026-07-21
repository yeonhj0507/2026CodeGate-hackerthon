"""결정론적 목 프로바이더.

Anthropic 키 없이도 `/quiz` → `/scrap` → `/thoughtmap/update` 전 구간이 돌아가게 한다.
같은 입력에는 항상 같은 출력을 내므로 테스트·데모에 그대로 쓸 수 있다.
"""

import hashlib
import re

from app.domain.llm.base import ConceptContext

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

    async def summarize_concepts(self, items: list[ConceptContext]) -> dict[str, str]:
        out: dict[str, str] = {}
        for item in items:
            # 실제 프롬프트와 같은 갈래: 미이해는 막힌 지점을, 이해완료는 발판을 짚는다.
            if item.understood:
                parts = [f"{item.concept}: 진단에서 맞힌 개념이다."]
                if item.parent_concepts:
                    parts.append(
                        f"이걸 발판으로 「{', '.join(item.parent_concepts)}」까지 볼 수 있다."
                    )
                if item.prereq_concepts:
                    parts.append(
                        f"「{', '.join(item.prereq_concepts)}」 위에 얹힌 개념이다."
                    )
                if item.is_prereq:
                    parts.append("선행 층을 잡아둔 셈이라 위쪽 갈래로 넘어가도 좋다.")
                if item.source_titles:
                    parts.append(
                        f"「{item.source_titles[0]}」 등 {len(item.source_titles)}개 기사에서 만났다."
                    )
                out[item.concept] = " ".join(parts)
                continue

            parts = [f"{item.concept}: 진단에서 막힌 개념이다."]
            if item.parent_concepts:
                parts.append(
                    f"이 개념을 몰라 「{', '.join(item.parent_concepts)}」의 인과가 끊겼다."
                )
            if item.prereq_concepts:
                parts.append(
                    f"먼저 「{', '.join(item.prereq_concepts)}」부터 짚으면 여기까지 이어진다."
                )
            if item.is_prereq:
                parts.append("더 얕은 층의 선행 개념이라 여기서부터 다시 쌓는 게 빠르다.")
            if item.source_titles:
                parts.append(
                    f"「{item.source_titles[0]}」 등 {len(item.source_titles)}개 기사에서 만났다."
                )
            out[item.concept] = " ".join(parts)
        return out

    async def explain_concepts(self, concepts: list[str]) -> str:
        if not concepts:
            return ""
        head = "、".join(concepts[:-1]) or concepts[0]
        tail = concepts[-1]
        joined = f"{head}과(와) {tail}" if len(concepts) > 1 else tail
        return (
            f"{joined}은(는) 한 갈래로 이어지는 개념들입니다. "
            f"{concepts[0]}에서 출발해 조건이 바뀔 때 무엇이 따라 움직이는지를 보면 "
            f"{tail}까지 자연스럽게 연결됩니다."
        )
