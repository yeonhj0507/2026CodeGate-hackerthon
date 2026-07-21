"""불완전한 JSON 에서 완성된 배열 원소만 꺼내는 증분 스캐너.

Claude 의 tool use 응답은 `input_json_delta` 로 조각조각 도착한다. 조각을 이어붙인
중간 상태는 `{"quiz": [{...}, {...` 처럼 **문법적으로 깨진 JSON** 이라 json.loads 가
통째로 실패한다. 그래서 배열 원소 하나가 닫히는 순간을 직접 찾아 그 구간만 파싱한다.

퀴즈 스트리밍의 정확도가 여기에 달려 있다. 문자열 안의 중괄호(`"a}b"`)나 이스케이프된
따옴표(`"a\\"b"`)를 깊이 계산에 넣으면 원소 경계가 어긋나 문항이 깨져 나간다 —
그래서 문자열/이스케이프 상태를 따로 들고 간다.
"""

import json
from typing import Iterator


class JsonArrayScanner:
    """`{"<key>": [ ... ]}` 형태에서 완성된 원소를 도착 순서대로 방출한다.

    사용법: 도착한 조각마다 [feed] 를 부르면, 그 조각으로 **새로 완성된** 원소들이
    나온다. 아직 닫히지 않은 원소는 버퍼에 남아 다음 호출에서 이어진다.
    """

    def __init__(self, key: str) -> None:
        self._needle = f'"{key}"'
        self._buf = ""
        self._cursor = 0  # 아직 훑지 않은 위치
        self._armed = False  # 배열 시작 '[' 을 찾았는가
        self._depth = 0
        self._elem_start: int | None = None
        self._in_string = False
        self._escaped = False
        self._closed = False  # 배열이 ']' 로 끝났는가

    @property
    def closed(self) -> bool:
        return self._closed

    def feed(self, chunk: str) -> Iterator[dict]:
        if self._closed or not chunk:
            return
        self._buf += chunk

        if not self._armed and not self._arm():
            return

        yield from self._scan()

    def _arm(self) -> bool:
        """`"quiz"` 뒤의 여는 대괄호를 찾아 스캔 시작점을 잡는다."""
        at = self._buf.find(self._needle)
        if at < 0:
            return False
        bracket = self._buf.find("[", at + len(self._needle))
        if bracket < 0:
            return False
        self._armed = True
        self._cursor = bracket + 1
        return True

    def _scan(self) -> Iterator[dict]:
        i = self._cursor
        while i < len(self._buf):
            ch = self._buf[i]

            if self._in_string:
                if self._escaped:
                    self._escaped = False
                elif ch == "\\":
                    self._escaped = True
                elif ch == '"':
                    self._in_string = False
                i += 1
                continue

            if ch == '"':
                self._in_string = True
            elif ch == "{":
                if self._depth == 0:
                    self._elem_start = i
                self._depth += 1
            elif ch == "}":
                self._depth -= 1
                if self._depth == 0 and self._elem_start is not None:
                    raw = self._buf[self._elem_start : i + 1]
                    self._elem_start = None
                    try:
                        parsed = json.loads(raw)
                    except json.JSONDecodeError:
                        # 경계 판정이 어긋난 경우. 조용히 버리면 문항이 통째로 사라지므로
                        # 스캔을 멈춘다 — 호출부가 최종 응답으로 복구한다.
                        self._closed = True
                        return
                    if isinstance(parsed, dict):
                        yield parsed
            elif ch == "]" and self._depth == 0:
                self._closed = True
                self._cursor = i + 1
                return

            i += 1

        self._cursor = i
