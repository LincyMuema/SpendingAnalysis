"""
Authentication routes — register and login.
POST /authentication/register - create a new user account and return a token
POST /authentication/login    - authenticate and return a token
GET  /authentication/me       - the logged-in user's profile (also checks a saved token)
PATCH /authentication/me      - update name, email or phone
POST /authentication/change-password - change password (current password required)
POST /authentication/forgot-password - email a code for resetting the password
POST /authentication/reset-password  - set a new password using the emailed code
POST /authentication/verify-login    - finish signing in with the emailed code (two-step sign-in)
PUT  /authentication/two-factor      - turn two-step sign-in on or off (password required)

The token is sent by the app with every other request
(Authorization: Bearer <token>) and checked in security.py.
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import text
import hashlib
import hmac
import os
import re
import secrets
from typing import Optional
from pydantic import BaseModel
from passlib.context import CryptContext
from database import get_db
from security import create_token, get_current_user_id
from email_service import send_code_email

router = APIRouter()

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# Request and response shapes
class RegisterRequest(BaseModel):
    full_name : str
    email     : str
    phone     : str
    password  : str

class LoginRequest(BaseModel):
    email       : str
    password    : str
    remember_me : bool = False   # longer-lasting token when "Remember device" is ticked

class ProfileUpdateRequest(BaseModel):
    full_name : Optional[str] = None
    email     : Optional[str] = None
    phone     : Optional[str] = None

class ChangePasswordRequest(BaseModel):
    current_password : str
    new_password     : str

class AuthResponse(BaseModel):
    message   : str
    user_id   : Optional[int] = None
    full_name : Optional[str] = None
    token     : Optional[str] = None
    # Two-step sign-in: the password was right, but a code has been emailed
    # and must be entered (POST /authentication/verify-login) to get the token
    two_factor_required : bool = False
    email_hint          : Optional[str] = None

class ForgotPasswordRequest(BaseModel):
    email : str

class ResetPasswordRequest(BaseModel):
    email        : str
    code         : str
    new_password : str

class VerifyLoginRequest(BaseModel):
    email       : str
    code        : str
    remember_me : bool = False

class TwoFactorRequest(BaseModel):
    enabled  : bool
    password : str

def hash_password(password: str) -> str:
    return pwd_context.hash(password)

def verify_password(plain: str, hashed: Optional[str]) -> bool:
    if not hashed:      # e.g. an account created with Google sign-in has no password
        return False
    return pwd_context.verify(plain, hashed)


# ── One-time email codes ────────────────────────────────────────────────────
CODE_MINUTES = 10        # a code is valid for 10 minutes
CODE_MAX_ATTEMPTS = 5    # wrong guesses allowed before a new code is needed
CODE_RESEND_SECONDS = 60 # minimum time between two codes for the same purpose


def _hash_code(code: str) -> str:
    """Codes are stored hashed (keyed with the server's secret), never as plain text."""
    key = (os.getenv("SECRET_KEY") or "").encode()
    return hmac.new(key, code.encode(), hashlib.sha256).hexdigest()


def _mask_email(email: str) -> str:
    """jane.doe@gmail.com -> j*******@gmail.com"""
    name, _, domain = email.partition("@")
    return f"{name[:1]}{'*' * max(len(name) - 1, 1)}@{domain}"


def _issue_code(db: Session, user, purpose: str) -> None:
    """Create a new 6-digit code for this purpose and email it to the user."""
    recent = db.execute(
        text("""
            SELECT 1 FROM auth_codes
            WHERE user_id = :id AND purpose = :purpose
              AND created_at > NOW() - make_interval(secs => :secs)
        """),
        {"id": user.user_id, "purpose": purpose, "secs": CODE_RESEND_SECONDS},
    ).fetchone()
    if recent:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="A code was sent less than a minute ago. Check your email, or wait a minute and try again.",
        )

    code = f"{secrets.randbelow(1_000_000):06d}"
    # Only the newest code for each purpose is kept
    db.execute(text("DELETE FROM auth_codes WHERE user_id = :id AND purpose = :purpose"),
               {"id": user.user_id, "purpose": purpose})
    db.execute(
        text("""
            INSERT INTO auth_codes (user_id, purpose, code_hash, expires_at)
            VALUES (:id, :purpose, :hash, NOW() + make_interval(mins => :mins))
        """),
        {"id": user.user_id, "purpose": purpose, "hash": _hash_code(code), "mins": CODE_MINUTES},
    )
    db.commit()

    if not send_code_email(user.email, user.full_name, code, purpose, CODE_MINUTES):
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="We could not send the email right now. Please try again in a few minutes.",
        )


def _check_code(db: Session, user_id: int, purpose: str, code: str) -> None:
    """Accept the code (and delete it) or raise a clear error."""
    row = db.execute(
        text("""
            SELECT code_id, code_hash, attempts, expires_at > NOW() AS valid
            FROM auth_codes
            WHERE user_id = :id AND purpose = :purpose
            ORDER BY created_at DESC LIMIT 1
        """),
        {"id": user_id, "purpose": purpose},
    ).fetchone()

    if not row or not row.valid:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="This code has expired. Please request a new one.")
    if row.attempts >= CODE_MAX_ATTEMPTS:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="Too many incorrect attempts. Please request a new code.")

    if not hmac.compare_digest(row.code_hash, _hash_code(code.strip())):
        db.execute(text("UPDATE auth_codes SET attempts = attempts + 1 WHERE code_id = :c"),
                   {"c": row.code_id})
        db.commit()
        left = CODE_MAX_ATTEMPTS - row.attempts - 1
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Incorrect code. {left} attempt{'s' if left != 1 else ''} left." if left
                   else "Incorrect code. Please request a new one.",
        )

    db.execute(text("DELETE FROM auth_codes WHERE user_id = :id AND purpose = :purpose"),
               {"id": user_id, "purpose": purpose})
    db.commit()


def _user_by_email(db: Session, email: str):
    return db.execute(
        text("""
            SELECT user_id, full_name, email, password_hash, two_factor_enabled
            FROM users WHERE LOWER(email) = :email
        """),
        {"email": email.strip().lower()},
    ).fetchone()

def password_problems(password: str) -> list[str]:
    """List what a password is missing. An empty list means it is strong enough."""
    problems = []
    if len(password) < 8:
        problems.append("at least 8 characters")
    if not re.search(r"[A-Z]", password):
        problems.append("an uppercase letter")
    if not re.search(r"[a-z]", password):
        problems.append("a lowercase letter")
    if not re.search(r"[0-9]", password):
        problems.append("a number")
    if not re.search(r"[^A-Za-z0-9]", password):
        problems.append("a symbol (e.g. ! @ # $)")
    return problems

# POST /auth/register 
@router.post("/register", response_model=AuthResponse)
def register(request: RegisterRequest, db: Session = Depends(get_db)):
    request.email = request.email.strip().lower()
    request.full_name = request.full_name.strip()

    if not request.full_name or "@" not in request.email:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Enter your full name and a valid email address",
        )

    missing = password_problems(request.password)
    if missing:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Password needs " + ", ".join(missing),
        )
    existing = db.execute(
        text("SELECT user_id FROM users WHERE LOWER(email) = :email"),
        {"email": request.email}
    ).fetchone()

    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="An account with this email already exists"
        )
    hashed = hash_password(request.password)
    result = db.execute(
        text("""
            INSERT INTO users (full_name, email, phone, password_hash)
            VALUES (:full_name, :email, :phone, :password_hash)
            RETURNING user_id
        """),
        {
            "full_name"     : request.full_name,
            "email"         : request.email,
            "phone"         : request.phone,
            "password_hash" : hashed
        }
    )
    db.commit()

    user_id = result.fetchone()[0]

    token = create_token(user_id)

    return AuthResponse(
        message   = "Account created successfully",
        user_id   = user_id,
        full_name = request.full_name,
        token     = token
    )

# POST /auth/login
@router.post("/login", response_model=AuthResponse)
def login(request: LoginRequest, db: Session = Depends(get_db)):
    """
    Authenticate an existing user.
    """
    request.email = request.email.strip().lower()

    user = _user_by_email(db, request.email)

    if not user or not verify_password(request.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password"
        )

    # Two-step sign-in: the password is right, now a code is emailed.
    # The token is only given out by /verify-login once the code is entered.
    if user.two_factor_enabled:
        _issue_code(db, user, "login_2fa")
        return AuthResponse(
            message             = "Enter the code we emailed you",
            two_factor_required = True,
            email_hint          = _mask_email(user.email),
        )

    token = create_token(user.user_id, remember=request.remember_me)

    return AuthResponse(
        message   = "Login successful",
        user_id   = user.user_id,
        full_name = user.full_name,
        token     = token
    )

# Profile ───────────────────────────────────────────────────────────────────

def _profile(user_id: int, db: Session) -> dict:
    user = db.execute(
        text("""
            SELECT user_id, full_name, email, phone, created_at, two_factor_enabled
            FROM users WHERE user_id = :id
        """),
        {"id": user_id},
    ).fetchone()
    if not user:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Account no longer exists")
    return {
        "user_id"     : user.user_id,
        "full_name"   : user.full_name,
        "email"       : user.email,
        "phone"       : user.phone,
        "member_since": user.created_at.date().isoformat() if user.created_at else None,
        "two_factor_enabled": bool(user.two_factor_enabled),
    }


# GET /authentication/me
@router.get("/me")
def me(
    db: Session = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id),
):
    """
    Return the logged-in user's profile. The app also calls this when it
    opens, to check that a saved ("Remember device") token is still valid.
    """
    return _profile(current_user_id, db)


# PATCH /authentication/me
@router.patch("/me")
def update_profile(
    request: ProfileUpdateRequest,
    db: Session = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id),
):
    """Update the user's name, email and/or phone. Only fields sent are changed."""
    updates = {}

    if request.full_name is not None:
        name = " ".join(request.full_name.split())
        if not name:
            raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                                detail="Full name cannot be empty")
        if len(name) > 100:
            raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                                detail="Full name is too long")
        updates["full_name"] = name

    if request.email is not None:
        email = request.email.strip().lower()
        if not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", email):
            raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                                detail="Enter a valid email address")
        taken = db.execute(
            text("SELECT 1 FROM users WHERE LOWER(email) = :email AND user_id <> :id"),
            {"email": email, "id": current_user_id},
        ).fetchone()
        if taken:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                                detail="Another account already uses this email")
        updates["email"] = email

    if request.phone is not None:
        phone = request.phone.strip()
        if phone and not re.fullmatch(r"\+?[0-9][0-9 -]{7,18}", phone):
            raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                                detail="Enter a valid phone number, e.g. +254 712 345 678")
        updates["phone"] = phone

    if updates:
        sets = ", ".join(f"{field} = :{field}" for field in updates)  # field names are fixed above
        db.execute(text(f"UPDATE users SET {sets} WHERE user_id = :id"),
                   {**updates, "id": current_user_id})
        db.commit()

    return {"message": "Profile updated", "profile": _profile(current_user_id, db)}


# POST /authentication/change-password
@router.post("/change-password")
def change_password(
    request: ChangePasswordRequest,
    db: Session = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id),
):
    user = db.execute(
        text("SELECT password_hash FROM users WHERE user_id = :id"),
        {"id": current_user_id},
    ).fetchone()
    if not user or not verify_password(request.current_password, user.password_hash):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="Your current password is incorrect")

    missing = password_problems(request.new_password)
    if missing:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                            detail="New password needs " + ", ".join(missing))
    if verify_password(request.new_password, user.password_hash):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="Choose a password different from your current one")

    db.execute(
        text("UPDATE users SET password_hash = :h WHERE user_id = :id"),
        {"h": hash_password(request.new_password), "id": current_user_id},
    )
    db.commit()
    return {"message": "Password changed"}


# Password reset ────────────────────────────────────────────────────────────

# POST /authentication/forgot-password
@router.post("/forgot-password")
def forgot_password(request: ForgotPasswordRequest, db: Session = Depends(get_db)):
    """
    Email a 6-digit code for resetting the password. The reply is the same
    whether or not the email has an account, so the endpoint cannot be used
    to find out who is registered.
    """
    reply = {"message": "If an account exists for this email, a reset code has been sent. It expires in "
                        f"{CODE_MINUTES} minutes."}
    user = _user_by_email(db, request.email)
    if user:
        try:
            _issue_code(db, user, "password_reset")
        except HTTPException as e:
            if e.status_code != status.HTTP_429_TOO_MANY_REQUESTS:
                raise
            # A code was sent moments ago: give the same reply, so the
            # endpoint still does not reveal whether the account exists
    return reply


# POST /authentication/reset-password
@router.post("/reset-password")
def reset_password(request: ResetPasswordRequest, db: Session = Depends(get_db)):
    """Set a new password after checking the emailed code."""
    user = _user_by_email(db, request.email)
    if not user:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="This code has expired. Please request a new one.")

    missing = password_problems(request.new_password)
    if missing:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                            detail="New password needs " + ", ".join(missing))

    _check_code(db, user.user_id, "password_reset", request.code)

    db.execute(
        text("UPDATE users SET password_hash = :h WHERE user_id = :id"),
        {"h": hash_password(request.new_password), "id": user.user_id},
    )
    db.commit()
    return {"message": "Password reset. You can now sign in with your new password."}


# Two-step sign-in ──────────────────────────────────────────────────────────

# POST /authentication/verify-login
@router.post("/verify-login", response_model=AuthResponse)
def verify_login(request: VerifyLoginRequest, db: Session = Depends(get_db)):
    """Second step of signing in: check the emailed code and return the token."""
    user = _user_by_email(db, request.email)
    if not user:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="This code has expired. Please sign in again.")

    _check_code(db, user.user_id, "login_2fa", request.code)

    return AuthResponse(
        message   = "Login successful",
        user_id   = user.user_id,
        full_name = user.full_name,
        token     = create_token(user.user_id, remember=request.remember_me),
    )


# PUT /authentication/two-factor
@router.put("/two-factor")
def set_two_factor(
    request: TwoFactorRequest,
    db: Session = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id),
):
    """Turn two-step sign-in on or off. The current password is required."""
    user = db.execute(
        text("SELECT password_hash FROM users WHERE user_id = :id"),
        {"id": current_user_id},
    ).fetchone()
    if not user or not verify_password(request.password, user.password_hash):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="Your password is incorrect")

    db.execute(
        text("UPDATE users SET two_factor_enabled = :on WHERE user_id = :id"),
        {"on": request.enabled, "id": current_user_id},
    )
    db.commit()
    return {
        "message": "Two-step sign-in turned on" if request.enabled else "Two-step sign-in turned off",
        "two_factor_enabled": request.enabled,
    }