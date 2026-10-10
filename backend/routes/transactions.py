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

# GET /transactions/{user_id} 
@router.get("/{user_id}")
def get_transactions(
    user_id: int,
    db: Session = Depends(get_db)
):
    """
    Get all transactions for a specific user.
    Returns transactions ordered by date, most recent first.
    """

    user = db.execute(
        text("SELECT user_id FROM users WHERE user_id = :user_id"),
        {"user_id": user_id}
    ).fetchone()

    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"User {user_id} not found"
        )

    transactions = db.execute(
        text("""
            SELECT
                t.transaction_id,
                t.amount,
                t.date,
                t.transaction_type,
                t.source,
                t.counterparty,
                t.is_manual,
                t.created_at,
                c.name AS category_name,
                c.category_id
            FROM transactions t
            LEFT JOIN categories c ON t.category_id = c.category_id
            WHERE t.user_id = :user_id
            ORDER BY t.date DESC
        """),
        {"user_id": user_id}
    ).fetchall()

    return {
        "user_id"         : user_id,
        "transaction_count": len(transactions),
        "transactions"    : [
            {
                "transaction_id"  : t.transaction_id,
                "amount"          : t.amount,
                "date"            : str(t.date),
                "transaction_type": t.transaction_type,
                "source"          : t.source,
                "counterparty"    : t.counterparty,
                "category_name"   : t.category_name,
                "category_id"     : t.category_id,
                "is_manual"       : t.is_manual,
                "created_at"      : str(t.created_at)
            }
            for t in transactions
        ]
    }

# PATCH /transactions/{id}/category 
@router.patch("/{transaction_id}/category")
def update_category(
    transaction_id: int,
    request: CategoryUpdateRequest,
    db: Session = Depends(get_db)
):
    """
    Update the category of a specific transaction.

    """

    transaction = db.execute(
        text("SELECT transaction_id FROM transactions WHERE transaction_id = :id"),
        {"id": transaction_id}
    ).fetchone()

    if not transaction:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Transaction {transaction_id} not found"
        )

    category_id = get_or_create_category(request.category_name, db)

    db.execute(
        text("""
            UPDATE transactions
            SET category_id = :category_id
            WHERE transaction_id = :transaction_id
        """),
        {
            "category_id"    : category_id,
            "transaction_id" : transaction_id
        }
    )
    db.commit()

    return {
        "message"        : "Category updated successfully",
        "transaction_id" : transaction_id,
        "new_category"   : request.category_name,
        "category_id"    : category_id
    }
