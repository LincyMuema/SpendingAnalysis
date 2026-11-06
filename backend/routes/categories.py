"""
Category routes.

GET    /categories       - the standard categories plus the user's own
POST   /categories       - create a custom category for the logged-in user
DELETE /categories/{id}  - delete one of the user's own categories; its
                           transactions move to "Other"

Standard categories have user_id = NULL and are shared by everyone.
Custom categories belong to one user and are only visible to that user.
The models do not depend on category names (they use category-independent
features), so custom categories work in the analysis without retraining.
"""

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import text
from sqlalchemy.orm import Session

from database import get_db
from security import get_current_user_id

router = APIRouter()

MAX_NAME_LENGTH = 30


class CategoryRequest(BaseModel):
    name: str
    icon: Optional[str] = None


def _row_to_dict(row) -> dict:
    return {
        "category_id": row.category_id,
        "name": row.name,
        "icon": row.icon,
        "is_custom": row.user_id is not None,
    }


# GET /categories
@router.get("/")
def list_categories(
    db: Session = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id),
):
    rows = db.execute(
        text("""
            SELECT category_id, name, icon, user_id
            FROM categories
            WHERE user_id IS NULL OR user_id = :user_id
            ORDER BY (user_id IS NOT NULL), name
        """),
        {"user_id": current_user_id},
    ).fetchall()
    return {"categories": [_row_to_dict(r) for r in rows]}


# POST /categories
@router.post("/", status_code=status.HTTP_201_CREATED)
def create_category(
    request: CategoryRequest,
    db: Session = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id),
):
    name = " ".join(request.name.split())  # trim and collapse spaces
    if name.islower():
        name = name[0].upper() + name[1:]    # "church" -> "Church"
    if not name:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                            detail="Enter a category name")
    if len(name) > MAX_NAME_LENGTH:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                            detail=f"Category names can be at most {MAX_NAME_LENGTH} characters")

    existing = db.execute(
        text("""
            SELECT name, user_id FROM categories
            WHERE LOWER(name) = LOWER(:name)
              AND (user_id IS NULL OR user_id = :user_id)
        """),
        {"name": name, "user_id": current_user_id},
    ).fetchone()
    if existing:
        where = "a standard category" if existing.user_id is None else "one of your categories"
        raise HTTPException(status_code=status.HTTP_409_CONFLICT,
                            detail=f"{existing.name} is already {where}")

    row = db.execute(
        text("""
            INSERT INTO categories (name, icon, user_id)
            VALUES (:name, :icon, :user_id)
            RETURNING category_id, name, icon, user_id
        """),
        {"name": name, "icon": (request.icon or "📦")[:10], "user_id": current_user_id},
    ).fetchone()
    db.commit()
    return {"message": "Category created", "category": _row_to_dict(row)}


# DELETE /categories/{category_id}
@router.delete("/{category_id}")
def delete_category(
    category_id: int,
    db: Session = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id),
):
    category = db.execute(
        text("SELECT category_id, name FROM categories WHERE category_id = :id AND user_id = :user_id"),
        {"id": category_id, "user_id": current_user_id},
    ).fetchone()
    if not category:
        # Standard categories, and other users' categories, cannot be deleted
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND,
                            detail="Category not found, or it is a standard category")

    other_id = db.execute(
        text("SELECT category_id FROM categories WHERE name = 'Other' AND user_id IS NULL")
    ).scalar()
    if other_id is None:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                            detail="The standard 'Other' category is missing")

    moved = db.execute(
        text("UPDATE transactions SET category_id = :other WHERE category_id = :id AND user_id = :user_id"),
        {"other": other_id, "id": category_id, "user_id": current_user_id},
    ).rowcount
    db.execute(
        text("UPDATE merchant_rules SET category_id = :other WHERE category_id = :id AND user_id = :user_id"),
        {"other": other_id, "id": category_id, "user_id": current_user_id},
    )
    db.execute(text("DELETE FROM categories WHERE category_id = :id"), {"id": category_id})
    db.commit()

    return {
        "message": f"Deleted {category.name}. {moved} transaction(s) moved to Other.",
        "moved_count": moved,
    }
