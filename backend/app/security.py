"""Revocable, opaque, expiring bearer sessions. Never persist browser tokens."""

import hashlib
import hmac
import secrets
from datetime import timedelta
from collections import defaultdict, deque
from time import monotonic
from fastapi import Depends, HTTPException, Request
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from app.db.database import Session
from app.models import User, LoginSession, now

bearer = HTTPBearer(auto_error=False)
_attempts = defaultdict(deque)


def password_hash(password: str) -> str:
    salt = secrets.token_hex(16)
    digest = hashlib.pbkdf2_hmac(
        "sha256", password.encode(), salt.encode(), 600000
    ).hex()
    return f"pbkdf2_sha256$600000${salt}${digest}"


def verify_password(password: str, stored: str) -> bool:
    try:
        method, rounds, salt, digest = stored.split("$")
        if method != "pbkdf2_sha256" or int(rounds) != 600000:
            return False
        return hmac.compare_digest(
            hashlib.pbkdf2_hmac(
                "sha256", password.encode(), salt.encode(), int(rounds)
            ).hex(),
            digest,
        )
    except (ValueError, TypeError):
        return False


# One constant-cost check for unknown users as well as existing accounts.
_dummy = password_hash(secrets.token_urlsafe(32))


def login_limit(request: Request):
    key = request.client.host if request.client else "unknown"
    current = monotonic()
    # Bound memory and expire stale entries. Proxy identity must be configured by the operator.
    for address in list(_attempts):
        q = _attempts[address]
        while q and q[0] < current - 900:
            q.popleft()
        if not q:
            del _attempts[address]
    q = _attempts[key]
    if len(q) >= 10 or len(_attempts) > 10000:
        raise HTTPException(
            429,
            "Too many attempts. Try again in 15 minutes.",
            headers={"Retry-After": "900"},
        )
    q.append(current)


def token_hash(token):
    return hashlib.sha256(token.encode()).hexdigest()


async def db():
    async with Session() as session:
        yield session


async def current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
    session=Depends(db),
):
    if not credentials:
        raise HTTPException(
            401, "Sign in required", headers={"WWW-Authenticate": "Bearer"}
        )
    login = await session.get(LoginSession, token_hash(credentials.credentials))
    if not login or login.expires_at <= now():
        raise HTTPException(
            401, "Session expired or invalid", headers={"WWW-Authenticate": "Bearer"}
        )
    user = await session.get(User, login.user_id)
    if not user or not user.active:
        raise HTTPException(401, "Account unavailable")
    return user


async def issue_session(session, user):
    token = secrets.token_urlsafe(32)
    session.add(
        LoginSession(
            token_hash=token_hash(token),
            user_id=user.id,
            expires_at=now() + timedelta(hours=8),
        )
    )
    await session.commit()
    return token


def public_user(user):
    return {
        "id": user.id,
        "name": user.name,
        "email": user.email,
        "role": user.role,
        "level": user.level,
    }
