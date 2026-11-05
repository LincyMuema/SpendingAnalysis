"""
Transaction routes.

POST /transactions — a new transaction
GET  /transactions/{user_id}   — get all transactions for a user
PATCH /transactions/{id}/category — update a transaction category
PATCH /transactions/{id}/dismiss-anomaly — mark a flagged transaction as normal

Every endpoint requires a login token. The user is taken from the token,
so a user can only read or change their own transactions.
"""

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session
from sqlalchemy import text
from pydantic import BaseModel, Field
from typing import Optional
from database import get_db
from security import get_current_user_id, require_same_user

router = APIRouter()

# Request and response shapes 

class TransactionRequest(BaseModel):
    user_id          : Optional[int] = None   # ignored; the user comes from the login token
    amount           : float = Field(gt=0)
    date             : str
    transaction_type : Optional[str] = None
    source           : Optional[str] = None
    counterparty     : Optional[str] = None
    category_name    : Optional[str] = "Other"
    is_manual        : Optional[bool] = False
    reference        : Optional[str] = None   # M-Pesa / Airtel code, used to avoid duplicates

class CategoryUpdateRequest(BaseModel):
    category_name : str
    apply_to_all  : Optional[bool] = False

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
    db: Session = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id),
):
    """
    Save a new transaction to the database.

    Called by Flutter when:
    - A new M-Pesa or bank card SMS is parsed
    - The user manually adds a cash or wallet transaction
    """
    request.user_id = current_user_id

    user = db.execute(
        text("SELECT user_id FROM users WHERE user_id = :user_id"),
        {"user_id": request.user_id}
    ).fetchone()

    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"User {request.user_id} not found"
        )

    # Skip SMS transactions that were already imported
    if request.reference:
        existing = db.execute(
            text("""
                SELECT transaction_id FROM transactions
                WHERE user_id = :user_id AND reference = :reference
            """),
            {"user_id": request.user_id, "reference": request.reference}
        ).fetchone()
        if existing:
            return JSONResponse(
                status_code=status.HTTP_200_OK,
                content={
                    "message"        : "Duplicate transaction ignored",
                    "duplicate"      : True,
                    "transaction_id" : existing[0]
                }
            )

    category_id = get_or_create_category(request.category_name, db)

    # For SMS imports, use the category the user chose before for this merchant/person
    if not request.is_manual and request.counterparty:
        rule = db.execute(
            text("""
                SELECT category_id FROM merchant_rules
                WHERE user_id = :user_id
                  AND counterparty = UPPER(TRIM(:counterparty))
            """),
            {"user_id": request.user_id, "counterparty": request.counterparty}
        ).fetchone()
        if rule:
            category_id = rule[0]

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
                is_manual,
                reference
            )
            VALUES (
                :user_id,
                :amount,
                :date,
                :transaction_type,
                :source,
                :counterparty,
                :category_id,
                :is_manual,
                :reference
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
            "is_manual"        : request.is_manual,
            "reference"        : request.reference
        }
    )
    db.commit()

    transaction_id = result.fetchone()[0]

    return {
        "message"        : "Transaction saved successfully",
        "transaction_id" : transaction_id,
        "category_id"    : category_id,
        "category_name"  : request.category_name,
        "duplicate"      : False
    }

# GET /transactions/{user_id} 
@router.get("/{user_id}")
def get_transactions(
    user_id: int,
    db: Session = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id),
):
    """
    Get all transactions for a specific user.
    Returns transactions ordered by date, most recent first.
    """
    require_same_user(user_id, current_user_id)

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
            ORDER BY t.date DESC, t.transaction_id DESC
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
    db: Session = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id),
):
    """
    Update the category of a transaction.

    If apply_to_all is true, every transaction from the same merchant/person
    is updated and the choice is remembered for future SMS imports.
    """

    transaction = db.execute(
        text("""
            SELECT transaction_id, user_id, counterparty
            FROM transactions
            WHERE transaction_id = :id AND user_id = :user_id
        """),
        {"id": transaction_id, "user_id": current_user_id}
    ).fetchone()

    if not transaction:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Transaction {transaction_id} not found"
        )

    category_id = get_or_create_category(request.category_name, db)
    counterparty = (transaction.counterparty or "").strip().upper()

    if request.apply_to_all and counterparty:
        result = db.execute(
            text("""
                UPDATE transactions
                SET category_id = :category_id
                WHERE user_id = :user_id
                  AND UPPER(TRIM(counterparty)) = :counterparty
            """),
            {
                "category_id"  : category_id,
                "user_id"      : transaction.user_id,
                "counterparty" : counterparty
            }
        )
        updated_count = result.rowcount

        # Remember the choice for future imports
        db.execute(
            text("""
                INSERT INTO merchant_rules (user_id, counterparty, category_id)
                VALUES (:user_id, :counterparty, :category_id)
                ON CONFLICT (user_id, counterparty)
                DO UPDATE SET category_id = EXCLUDED.category_id
            """),
            {
                "user_id"      : transaction.user_id,
                "counterparty" : counterparty,
                "category_id"  : category_id
            }
        )
    else:
        db.execute(
            text("""
                UPDATE transactions
                SET category_id = :category_id
                WHERE transaction_id = :transaction_id AND user_id = :user_id
            """),
            {
                "category_id"    : category_id,
                "transaction_id" : transaction_id,
                "user_id"        : current_user_id
            }
        )
        updated_count = 1

    db.commit()

    return {
        "message"        : "Category updated successfully",
        "transaction_id" : transaction_id,
        "new_category"   : request.category_name,
        "category_id"    : category_id,
        "updated_count"  : updated_count
    }

# PATCH /transactions/{id}/dismiss-anomaly
@router.patch("/{transaction_id}/dismiss-anomaly")
def dismiss_anomaly(
    transaction_id: int,
    db: Session = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id),
):
    """
    The user confirms a flagged transaction is normal.
    It will no longer appear in the anomaly list. The stored feedback can
    also be used as labelled data when the model is retrained.
    """
    transaction = db.execute(
        text("SELECT transaction_id FROM transactions WHERE transaction_id = :id AND user_id = :user_id"),
        {"id": transaction_id, "user_id": current_user_id}
    ).fetchone()

    if not transaction:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Transaction {transaction_id} not found"
        )

    db.execute(
        text("""
            UPDATE transactions
            SET anomaly_dismissed = TRUE
            WHERE transaction_id = :id AND user_id = :user_id
        """),
        {"id": transaction_id, "user_id": current_user_id}
    )
    db.commit()

    return {
        "message"        : "Transaction marked as not unusual",
        "transaction_id" : transaction_id
    }