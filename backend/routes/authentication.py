"""
Authentication routes — register and login.
POST /authentication/register - create a new user account and return a token
POST /authentication/login    - authenticate and return a token
GET  /authentication/me       - the logged-in user's profile (also checks a saved token)
PATCH /authentication/me      - update name, email or phone
POST /authentication/change-password - change password (current password required)

The token is sent by the app with every other request
(Authorization: Bearer <token>) and checked in security.py.
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import text
import re
from typing import Optional
from pydantic import BaseModel
from passlib.context import CryptContext
from database import get_db
from security import create_token, get_current_user_id

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
    user_id   : int
    full_name : str
    token     : str

def hash_password(password: str) -> str:
    return pwd_context.hash(password)

def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)

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

    user = db.execute(
        text("""
            SELECT user_id, full_name, password_hash
            FROM users
            WHERE LOWER(email) = :email
        """),
        {"email": request.email}
    ).fetchone()

    if not user or not verify_password(request.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password"
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
            SELECT user_id, full_name, email, phone, created_at
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