"""Claude 프롬프트 · tool use JSON 스키마.

퀴즈 트리를 **한 번의 호출로** 완결 생성한다(명세 §3.2: 실행 중 추가 서버 호출 없음).
"""

QUIZ_SYSTEM = """\
당신은 뉴스 기사를 읽는 독자의 이해도를 진단하는 출제자다.

원칙:
- 기사에서 핵심 주장 2~4개를 고른다. 사실 나열이 아니라 "왜/그래서"를 묻을 수 있는 주장이어야 한다.
- 각 주장마다 인과·추론형 객관식 4지선다 1문항을 만든다. 단순 암기·숫자 확인 문제는 금지.
- 각 문항에는 그 주장이 등장한 문단 번호(paragraphIndex)를 반드시 지정한다.
- 각 문항에는 선행개념 재질문을 2단계까지 만든다.
  level 1은 그 개념을 이해하는 데 먼저 알아야 할 개념,
  level 2는 level 1을 이해하는 데 먼저 알아야 할 더 얕은 개념이다.
- conceptTag/prereqConceptTag 는 일반명사 형태의 짧은 개념어로 쓴다(예: "기준금리", "환율 전가").
  기사 제목을 그대로 넣지 말 것. 다른 기사에서 같은 개념이 나오면 같은 표기가 되도록 보편적인 용어를 쓴다.
- explanation 은 오답자에게 보여줄 설명이다. 정답 번호를 언급하지 말고 개념 자체를 풀어 쓴다.
- 모든 출력은 한국어.
"""

QUIZ_USER_TEMPLATE = """\
[기사 제목]
{title}

[문단 목록] (번호가 paragraphIndex 다)
{paragraphs}

위 기사로 퀴즈 트리를 생성하라.
"""

FOLLOWUP_SCHEMA_L2 = {
    "type": "object",
    "properties": {
        "level": {"type": "integer", "enum": [2]},
        "prereqConceptTag": {"type": "string"},
        "question": {"type": "string"},
        "options": {"type": "array", "items": {"type": "string"}, "minItems": 4, "maxItems": 4},
        "answerIndex": {"type": "integer", "minimum": 0, "maximum": 3},
        "explanation": {"type": "string"},
    },
    "required": [
        "level",
        "prereqConceptTag",
        "question",
        "options",
        "answerIndex",
        "explanation",
    ],
}

FOLLOWUP_SCHEMA_L1 = {
    "type": "object",
    "properties": {
        "level": {"type": "integer", "enum": [1]},
        "prereqConceptTag": {"type": "string"},
        "question": {"type": "string"},
        "options": {"type": "array", "items": {"type": "string"}, "minItems": 4, "maxItems": 4},
        "answerIndex": {"type": "integer", "minimum": 0, "maximum": 3},
        "explanation": {"type": "string"},
        "followups": {"type": "array", "items": FOLLOWUP_SCHEMA_L2, "maxItems": 1},
    },
    "required": [
        "level",
        "prereqConceptTag",
        "question",
        "options",
        "answerIndex",
        "explanation",
        "followups",
    ],
}

QUIZ_TOOL = {
    "name": "emit_quiz_tree",
    "description": "생성한 퀴즈 트리를 제출한다.",
    "input_schema": {
        "type": "object",
        "properties": {
            "quiz": {
                "type": "array",
                "minItems": 2,
                "maxItems": 4,
                "items": {
                    "type": "object",
                    "properties": {
                        "claimId": {"type": "string", "description": "c1, c2 … 형태"},
                        "conceptTag": {"type": "string"},
                        "paragraphIndex": {"type": "integer", "minimum": 0},
                        "question": {"type": "string"},
                        "options": {
                            "type": "array",
                            "items": {"type": "string"},
                            "minItems": 4,
                            "maxItems": 4,
                        },
                        "answerIndex": {"type": "integer", "minimum": 0, "maximum": 3},
                        "explanation": {"type": "string"},
                        "followups": {
                            "type": "array",
                            "items": FOLLOWUP_SCHEMA_L1,
                            "maxItems": 1,
                        },
                    },
                    "required": [
                        "claimId",
                        "conceptTag",
                        "paragraphIndex",
                        "question",
                        "options",
                        "answerIndex",
                        "explanation",
                        "followups",
                    ],
                },
            }
        },
        "required": ["quiz"],
    },
}

# anchorText 는 LLM 에게 요구하지 않는다. 서버가 paragraphIndex 로 직접 채운다
# (담당1의 앵커 매칭 리스크를 서버가 보증 — 구현계획① §3.3).

SUMMARY_SYSTEM = """\
당신은 학습자가 이해하지 못한 개념을 짧게 다시 설명해 주는 튜터다.

원칙:
- 개념 하나당 2~3문장. 정의 → 왜 중요한지 순서.
- 학습자가 그 개념을 만난 기사 맥락을 반영하되, 기사 요약이 아니라 개념 설명을 한다.
- 전문용어를 쓸 때는 즉시 풀어 쓴다. 한국어로 답한다.
"""

SUMMARY_TOOL = {
    "name": "emit_concept_summaries",
    "description": "개념별 보충설명을 제출한다.",
    "input_schema": {
        "type": "object",
        "properties": {
            "summaries": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "concept": {"type": "string"},
                        "summary": {"type": "string"},
                    },
                    "required": ["concept", "summary"],
                },
            }
        },
        "required": ["summaries"],
    },
}
