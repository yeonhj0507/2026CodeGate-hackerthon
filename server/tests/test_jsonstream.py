"""증분 JSON 스캐너 (DB·LLM 불필요).

퀴즈 스트리밍의 정확도가 통째로 여기 달려 있다. 조각이 **어디서 잘려 도착하든**
같은 결과가 나와야 하므로, 경계를 한 글자씩 옮겨 가며 전부 확인한다.
"""

import json

from app.domain.llm.jsonstream import JsonArrayScanner

PAYLOAD = {
    "quiz": [
        {"claimId": "c1", "question": "왜 동결했나?", "options": ["가", "나"]},
        # 문자열 안의 중괄호·이스케이프된 따옴표 — 깊이 계산을 망가뜨리는 입력.
        {"claimId": "c2", "question": '보기 {가} 와 "나" 중', "options": ["}", "\\"]},
        {"claimId": "c3", "question": "줄바꿈\n포함", "options": []},
    ]
}
TEXT = json.dumps(PAYLOAD, ensure_ascii=False)


def drain(chunks) -> list[dict]:
    scanner = JsonArrayScanner("quiz")
    out = []
    for chunk in chunks:
        out.extend(scanner.feed(chunk))
    return out


def test_whole_payload_at_once():
    assert drain([TEXT]) == PAYLOAD["quiz"]


def test_char_by_char():
    """1글자씩 도착해도 결과가 같아야 한다 — 가장 잔인한 분할."""
    assert drain(list(TEXT)) == PAYLOAD["quiz"]


def test_every_possible_split_point():
    """어디서 잘려도 동일. 경계 버그는 특정 분할에서만 드러나므로 전부 훑는다."""
    for cut in range(len(TEXT) + 1):
        assert drain([TEXT[:cut], TEXT[cut:]]) == PAYLOAD["quiz"], f"cut={cut}"


def test_emits_incrementally_not_all_at_end():
    """핵심 목적 — 배열이 닫히기 전에 완성된 원소가 먼저 나와야 한다."""
    head = TEXT[: TEXT.index('{"claimId": "c2"')]
    scanner = JsonArrayScanner("quiz")

    first = list(scanner.feed(head))

    assert len(first) == 1
    assert first[0]["claimId"] == "c1"
    assert not scanner.closed


def test_braces_inside_strings_do_not_split_elements():
    got = drain([TEXT])
    assert got[1]["question"] == '보기 {가} 와 "나" 중'
    assert got[1]["options"] == ["}", "\\"]


def test_closes_at_array_end():
    scanner = JsonArrayScanner("quiz")
    list(scanner.feed(TEXT))
    assert scanner.closed
    # 닫힌 뒤 들어온 조각은 무시한다(뒤따르는 "}" 등).
    assert list(scanner.feed('{"claimId": "c9"}')) == []


def test_ignores_other_keys_before_the_array():
    text = json.dumps({"note": "[{}]", "quiz": [{"claimId": "c1"}]}, ensure_ascii=False)
    assert drain([text]) == [{"claimId": "c1"}]


def test_empty_array():
    assert drain(['{"quiz": []}']) == []


def test_nested_objects_are_not_emitted_separately():
    """followups 같은 중첩 객체는 부모가 닫힐 때 한 번만 나와야 한다."""
    text = json.dumps(
        {"quiz": [{"claimId": "c1", "followups": [{"level": 1, "followups": []}]}]},
        ensure_ascii=False,
    )
    got = drain([text])
    assert len(got) == 1
    assert got[0]["followups"][0]["level"] == 1
