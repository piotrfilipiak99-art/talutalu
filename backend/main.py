import json

from email_validator import EmailNotValidError, validate_email
from fastapi import Depends, FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from auth import create_token, get_current_user, hash_password, verify_password
from database import Base, engine, get_db
from models import User, UserData

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
