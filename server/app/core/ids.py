"""ID 생성기. 기획 §7 의 문자열 PK(cuid) 자리.

데모에서는 dependency-free 하게 uuid4 hex 를 사용한다.
운영에서 cuid/cuid2 로 바꾸려면 이 함수만 교체하면 된다.
"""
import uuid


def new_id() -> str:
    return uuid.uuid4().hex
