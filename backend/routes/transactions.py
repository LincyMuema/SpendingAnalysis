"""
Transaction routes.

POST /transactions — a new transaction
GET  /transactions/{user_id}   — get all transactions for a user
PATCH /transactions/{id}/category — update a transaction category
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import text
from pydantic import BaseModel
from typing import Optional
from database import get_db

router = APIRouter()

# Request and response shapes 

class TransactionRequest(BaseModel):
    user_id          : int
    amount           : float
    date             : str
    transaction_type : Optional[str] = None
    source           : Optional[str] = None
    counterparty     : Optional[str] = None
    category_name    : Optional[str] = "Other"
    is_manual        : Optional[bool] = False

class CategoryUpdateRequest(BaseModel):
    category_name : str

def get_or_create_category(category_name: str, db: Session) -> int:

    result = db.execute(
        text("SELECT category_id FROM categories WHERE name = :name"),
        {"name": category_name}
    ).fetchone()

    if result:
        return result[0]

    new_cat = db.execute(
        text("""
            INSERT INTO categories (name, icon)
            VALUES (:name, :icon)
            RETURNING category_id
        """),
        {"name": category_name, "icon": "📦"}
    )
    db.commit()
    return new_cat.fetchone()[0]

# POST /transactions 
@router.post("/", status_code=status.HTTP_201_CREATED)
def create_transaction(
    request: TransactionRequest,
    db: Session = Depends(get_db)
):
    """
    Save a new transaction to the database.

    Called by Flutter when:
    - A new M-Pesa or bank card SMS is parsed
    - The user manually adds a cash or wallet transaction
    """
    user = db.execute(
        text("SELECT user_id FROM users WHERE user_id = :user_id"),
        {"user_id": request.user_id}
    ).fetchone()

    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"User {request.user_id} not found"
        )

    category_id = get_or_create_category(request.category_name, db)

    result = db.execute(
        text("""
            INSERT INTO transactions (
                user_id,
                amount,
                date,
                transaction_type,
                source,
                counterparty,
                category_id,
                is_manual
            )
            VALUES (
                :user_id,
                :amount,
                :date,
                :transaction_type,
                :source,
                :counterparty,
                :category_id,
                :is_manual
            )
            RETURNING transaction_id
        """),
        {
            "user_id"          : request.user_id,
            "amount"           : request.amount,
            "date"             : request.date,
            "transaction_type" : request.transaction_type,
            "source"           : request.source,
            "counterparty"     : request.counterparty,
            "category_id"      : category_id,
            "is_manual"        : request.is_manual
        }
    )
    db.commit()

    transaction_id = result.fetchone()[0]

    return {
        "message"        : "Transaction saved successfully",
        "transaction_id" : transaction_id,
        "category_id"    : category_id,
        "category_name"  : request.category_name
    }
