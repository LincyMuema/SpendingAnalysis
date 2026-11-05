"""
Authentication routes — register and login.
POST /authentication/register - create a new user account and return a token
POST /authentication/login    - authenticate and return a token

The token is sent by the app with every other request
(Authorization: Bearer <token>) and checked in security.py.
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import text
from pydantic import BaseModel, EmailStr
from passlib.context import CryptContext
from database import get_db
from security import create_token

router = APIRouter()

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# Request and response shapes
class RegisterRequest(BaseModel):
    full_name : str
    email     : str
    phone     : str
    password  : str

class LoginRequest(BaseModel):
    email    : str
    password : str

class AuthResponse(BaseModel):
    message   : str
    user_id   : int
    full_name : str
    token     : str

def hash_password(password: str) -> str:
    return pwd_context.hash(password)

def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)

# POST /auth/register 
@router.post("/register", response_model=AuthResponse)
def register(request: RegisterRequest, db: Session = Depends(get_db)):
    request.email = request.email.strip().lower()
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

    token = create_token(user.user_id)

    return AuthResponse(
        message   = "Login successful",
        user_id   = user.user_id,
        full_name = user.full_name,
        token     = token
    )