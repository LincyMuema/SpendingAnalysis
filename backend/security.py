"""
Login tokens (JWT).

create_token()        - issued at registration and login
get_current_user_id() - used by every protected endpoint; reads the
                        "Authorization: Bearer <token>" header and returns
                        the user ID stored inside the token.
"""

import os
from datetime import datetime, timedelta, timezone

from dotenv import load_dotenv
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt

load_dotenv()

SECRET_KEY = os.getenv("SECRET_KEY")
ALGORITHM = os.getenv("ALGORITHM", "HS256")
ACCESS_TOKEN_EXPIRE_MINUTES = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", 1440))
# Used when the user ticks "Remember device" at login
REMEMBER_ME_DAYS = int(os.getenv("REMEMBER_ME_DAYS", 30))

if not SECRET_KEY:
    raise RuntimeError("SECRET_KEY not set. Add it to the .env file (or Render environment).")

# auto_error=False so we can return our own clear 401 message
bearer_scheme = HTTPBearer(auto_error=False)


def create_token(user_id: int, remember: bool = False) -> str:
    lifetime = timedelta(days=REMEMBER_ME_DAYS) if remember else timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    expire = datetime.now(timezone.utc) + lifetime
    payload = {"sub": str(user_id), "exp": expire}
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


def get_current_user_id(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
) -> int:
    """Return the user ID from a valid token, or reject the request with 401."""
    unauthorised = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Not logged in or session expired. Please log in again.",
        headers={"WWW-Authenticate": "Bearer"},
    )
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise unauthorised
    try:
        payload = jwt.decode(credentials.credentials, SECRET_KEY, algorithms=[ALGORITHM])
        return int(payload["sub"])
    except (JWTError, KeyError, ValueError):
        raise unauthorised


def require_same_user(path_user_id: int, current_user_id: int) -> None:
    """Stop a logged-in user from reading another user's data."""
    if path_user_id != current_user_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You can only access your own data.",
        )
