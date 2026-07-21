"""로그인/회원가입 브루트포스 방지용 rate limiter. (명세 §3.5, Day2)

main.py 가 app.state.limiter 로 등록하고, 라우트에서 @limiter.limit(...) 로 사용.
"""
from slowapi import Limiter
from slowapi.util import get_remote_address

limiter = Limiter(key_func=get_remote_address)
