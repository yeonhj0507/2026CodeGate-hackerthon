"""프로바이더가 프로토콜 표면을 실제로 갖췄는지 확인한다.

`LlmProvider`/`SearchProvider` 는 Protocol 이라 런타임 검사가 없다. 테스트는 전부
mock 프로바이더로 돌기 때문에, claude 쪽에만 메서드가 빠져 있어도 실호출 전까지
아무도 모른다 — 실제로 `explain_concepts` 가 클래스 밖(모듈 함수 꼬리)에 붙어
`AttributeError` 로 500 이 난 적이 있다. 그 구멍을 여기서 막는다.

`inspect.getattr_static` 을 쓰는 이유: `__getattr__` 로 아무 이름이나 받아 주는
객체에 속지 않고 **클래스에 실제로 정의된 것**만 인정하기 위해서다.
"""

import inspect

import pytest

from app.domain.llm.base import LlmProvider
from app.domain.llm.claude import ClaudeProvider
from app.domain.llm.mock import MockProvider
from app.domain.search.base import SearchProvider
from app.domain.search.claude_search import ClaudeSearchProvider
from app.domain.search.mock import MockSearchProvider


def _protocol_methods(protocol: type) -> list[str]:
    return sorted(
        name
        for name in protocol.__dict__
        if not name.startswith("_") and callable(protocol.__dict__[name])
    )


@pytest.mark.parametrize(
    ("protocol", "implementation"),
    [
        (LlmProvider, MockProvider),
        (LlmProvider, ClaudeProvider),
        (SearchProvider, MockSearchProvider),
        (SearchProvider, ClaudeSearchProvider),
    ],
    ids=lambda v: getattr(v, "__name__", str(v)),
)
def test_implements_every_protocol_method(protocol: type, implementation: type) -> None:
    for name in _protocol_methods(protocol):
        member = inspect.getattr_static(implementation, name, None)
        assert member is not None, (
            f"{implementation.__name__} 에 {name} 이(가) 없다. "
            "클래스 바깥에 잘못 붙어 있지는 않은지 확인하라."
        )
        assert callable(member), f"{implementation.__name__}.{name} 이 호출 가능하지 않다"


@pytest.mark.parametrize(
    ("protocol", "implementation"),
    [
        (LlmProvider, MockProvider),
        (LlmProvider, ClaudeProvider),
        (SearchProvider, MockSearchProvider),
        (SearchProvider, ClaudeSearchProvider),
    ],
    ids=lambda v: getattr(v, "__name__", str(v)),
)
def test_signatures_match_protocol(protocol: type, implementation: type) -> None:
    """이름만 같고 인자가 어긋나도 실호출에서야 터진다. 시그니처까지 맞춘다."""
    for name in _protocol_methods(protocol):
        expected = inspect.signature(protocol.__dict__[name])
        actual = inspect.signature(inspect.getattr_static(implementation, name))
        assert list(actual.parameters) == list(expected.parameters), (
            f"{implementation.__name__}.{name} 인자가 프로토콜과 다르다: "
            f"{list(actual.parameters)} != {list(expected.parameters)}"
        )
