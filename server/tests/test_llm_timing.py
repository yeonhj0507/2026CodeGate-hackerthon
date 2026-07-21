"""LLM 호출 계측 로그 (API 키 불필요).

이 경로는 실제 Claude 호출에서만 지나가므로 평소 테스트에 안 잡힌다. 포맷 문자열이
깨지면 그때 가서 요청이 500 으로 죽으므로, 값이 비어 있는 경우까지 여기서 눌러 둔다.
"""

import logging

from app.domain.llm.claude import _log_timing


class _Usage:
    def __init__(self, **kw):
        self.__dict__.update(kw)


class _Message:
    def __init__(self, usage=None):
        self.usage = usage


def test_logs_tokens_and_rate(caplog):
    message = _Message(_Usage(input_tokens=1200, output_tokens=6000, cache_read_input_tokens=0))

    with caplog.at_level(logging.INFO):
        _log_timing("quiz", message, 60.0, {"quiz": ["…"]})

    line = caplog.text
    assert "quiz" in line
    assert "in=1200" in line
    assert "out=6000" in line
    assert "100 tok/s" in line  # 6000 / 60s


def test_survives_missing_usage(caplog):
    """usage 가 없거나 필드가 None 이어도 요청을 죽이면 안 된다."""
    with caplog.at_level(logging.INFO):
        _log_timing("explore", _Message(), 0.0)
        _log_timing("search", _Message(_Usage(input_tokens=None, output_tokens=None)), 1.0)

    assert "in=0 out=0" in caplog.text


def test_payload_chars_counts_korean_unescaped(caplog):
    """ensure_ascii=False 여야 한국어가 \\uXXXX 로 부풀지 않는다 — out 과 견줄 값이다."""
    with caplog.at_level(logging.INFO):
        _log_timing("quiz", _Message(_Usage(output_tokens=10)), 1.0, {"a": "기준금리"})

    # {"a": "기준금리"} = 13 글자. 이스케이프됐다면 30 글자가 넘는다.
    assert "payload_chars=13" in caplog.text
