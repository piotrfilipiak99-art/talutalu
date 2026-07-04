import json

from email_validator import EmailNotValidError, validate_email
from fastapi import Depends, FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from auth import create_token, get_current_user, hash_password, verify_password
from database import Base, engine, get_db
from models import (
    ConversationRow,
    DeckRow,
    FlashcardRow,
    TextRow,
    User,
    UserData,
)

Base.metadata.create_all(engine)

app = FastAPI(title="Talutalu API")

# The Flutter web demo runs on other origins (GitHub Pages, Render, localhost).
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Schemas ──────────────────────────────────────────────────────────────────


class Credentials(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)


class AuthResponse(BaseModel):
    token: str
    user_id: int
    email: str


class SyncItem(BaseModel):
    value: object  # any JSON value
    updatedAt: int


class SyncPush(BaseModel):
    items: dict[str, SyncItem]


class CollectionItem(BaseModel):
    id: str = Field(max_length=64)
    payload: object | None = None  # full item JSON; None for deletions
    updatedAt: int
    deleted: bool = False


class CollectionPush(BaseModel):
    items: list[CollectionItem]


# ── Routes ───────────────────────────────────────────────────────────────────


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/auth/register", response_model=AuthResponse, status_code=201)
def register(body: Credentials, db: Session = Depends(get_db)):
    email = body.email.lower()
    # Pydantic already validated the syntax; this DNS lookup verifies the
    # domain actually accepts mail (has MX/A records), so typos like
    # "gmial.com" or made-up domains are rejected at signup.
    try:
        validate_email(email, check_deliverability=True)
    except EmailNotValidError:
        raise HTTPException(
            status_code=400,
            detail="This email domain does not exist or cannot receive mail",
        )
    if db.scalar(select(User).where(User.email == email)):
        raise HTTPException(status_code=409, detail="Account already exists")
    user = User(email=email, password_hash=hash_password(body.password))
    db.add(user)
    db.commit()
    return AuthResponse(token=create_token(user.id), user_id=user.id, email=user.email)


@app.post("/auth/login", response_model=AuthResponse)
def login(body: Credentials, db: Session = Depends(get_db)):
    user = db.scalar(select(User).where(User.email == body.email.lower()))
    if user is None or not verify_password(body.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Wrong email or password")
    return AuthResponse(token=create_token(user.id), user_id=user.id, email=user.email)


@app.get("/me")
def me(user: User = Depends(get_current_user)):
    return {"user_id": user.id, "email": user.email}


def _state(db: Session, user_id: int) -> dict:
    rows = db.scalars(select(UserData).where(UserData.user_id == user_id)).all()
    return {
        "items": {
            r.key: {"value": json.loads(r.value), "updatedAt": r.updated_at}
            for r in rows
        }
    }


@app.get("/sync")
def sync_pull(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    return _state(db, user.id)


# ── Per-item collection sync (flashcards, decks) ────────────────────────────
#
# Same last-write-wins idea as /sync, but one timestamp per item instead of
# per whole list, so two devices editing different cards no longer clobber
# each other. Deletions are tombstoned, not erased, so they propagate.


def _merge_collection(db: Session, model, user_id: int, items, set_columns):
    for item in items:
        row = db.get(model, (user_id, item.id))
        if row is None:
            row = model(user_id=user_id, id=item.id, updated_at=item.updatedAt)
            db.add(row)
        elif item.updatedAt < row.updated_at:
            continue  # the server already has something newer
        row.updated_at = item.updatedAt
        row.deleted = item.deleted
        if not item.deleted and item.payload is not None:
            row.payload = json.dumps(item.payload)
            set_columns(row, item.payload)
    db.commit()
    rows = db.scalars(select(model).where(model.user_id == user_id)).all()
    return {
        "items": [
            {
                "id": r.id,
                "payload": json.loads(r.payload) if not r.deleted else None,
                "updatedAt": r.updated_at,
                "deleted": r.deleted,
            }
            for r in rows
        ]
    }


@app.put("/sync/flashcards")
def sync_flashcards(
    body: CollectionPush,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    def set_columns(row, p):
        row.course_id = str(p.get("courseId", ""))[:64]
        row.word = str(p.get("word", ""))[:256]
        row.translation = str(p.get("translation", ""))[:256]
        row.mastery_level = int(p.get("masteryLevel", 0))

    return _merge_collection(db, FlashcardRow, user.id, body.items, set_columns)


@app.put("/sync/decks")
def sync_decks(
    body: CollectionPush,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    def set_columns(row, p):
        row.course_id = str(p.get("courseId", ""))[:64]
        row.name = str(p.get("name", ""))[:128]

    return _merge_collection(db, DeckRow, user.id, body.items, set_columns)


@app.put("/sync/texts")
def sync_texts(
    body: CollectionPush,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    def set_columns(row, p):
        row.course_id = str(p.get("courseId", ""))[:64]
        row.title = str(p.get("title", ""))[:256]
        row.level = str(p.get("level", ""))[:32]

    return _merge_collection(db, TextRow, user.id, body.items, set_columns)


@app.put("/sync/conversations")
def sync_conversations(
    body: CollectionPush,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    def set_columns(row, p):
        row.course_id = str(p.get("courseId", ""))[:64]
        row.title = str(p.get("title") or "")[:256]
        row.starred = bool(p.get("starred", False))

    return _merge_collection(db, ConversationRow, user.id, body.items, set_columns)


@app.put("/sync")
def sync_push(
    body: SyncPush,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Per-key last-write-wins: newer client timestamps overwrite, older lose."""
    for key, item in body.items.items():
        row = db.get(UserData, (user.id, key))
        if row is None:
            db.add(UserData(
                user_id=user.id, key=key,
                value=json.dumps(item.value), updated_at=item.updatedAt,
            ))
        elif item.updatedAt >= row.updated_at:
            row.value = json.dumps(item.value)
            row.updated_at = item.updatedAt
    db.commit()
    return _state(db, user.id)
