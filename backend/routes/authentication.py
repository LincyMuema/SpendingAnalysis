"""
Authentication routes — register and login.
POST /auth/register — create a new user account
POST /auth/login — authenticate and return a token
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import text
from pydantic import BaseModel, EmailStr
from passlib.context import CryptContext
from jose import jwt
from datetime import datetime, timedelta
from database import get_db
from dotenv import load_dotenv
import os

load_dotenv()

router = APIRouter()

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

SECRET_KEY                = os.getenv("SECRET_KEY")
ALGORITHM                 = os.getenv("ALGORITHM")
ACCESS_TOKEN_EXPIRE_MINUTES = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", 30))

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

def create_token(user_id: int) -> str:
    expire = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    payload = {
        "sub" : str(user_id),
        "exp" : expire
    }
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)

# POST /auth/register 
@router.post("/register", response_model=AuthResponse)
def register(request: RegisterRequest, db: Session = Depends(get_db)):
    existing = db.execute(
        text("SELECT user_id FROM users WHERE email = :email"),
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

    user = db.execute(
        text("""
            SELECT user_id, full_name, password_hash
            FROM users
            WHERE email = :email
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