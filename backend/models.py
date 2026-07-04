import time

from sqlalchemy import BigInteger, ForeignKey, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from database import Base


def now_ms() -> int:
    return int(time.time() * 1000)


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(String(320), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(128))
    created_at: Mapped[int] = mapped_column(BigInteger, default=now_ms)


class FlashcardRow(Base):
    """One row per flashcard. The client's full card JSON lives in [payload];
    the extracted columns exist so the server can query cards (e.g. "weakest
    words for this user") without parsing blobs. Deleted cards stay as
    tombstones so the deletion reaches the user's other devices.
    """

    __tablename__ = "flashcards"

    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    course_id: Mapped[str] = mapped_column(String(64), default="", index=True)
    word: Mapped[str] = mapped_column(String(256), default="")
    translation: Mapped[str] = mapped_column(String(256), default="")
    mastery_level: Mapped[int] = mapped_column(default=0)
    payload: Mapped[str] = mapped_column(Text, default="null")
    updated_at: Mapped[int] = mapped_column(BigInteger)
    deleted: Mapped[bool] = mapped_column(default=False)


class DeckRow(Base):
    __tablename__ = "decks"

    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    course_id: Mapped[str] = mapped_column(String(64), default="", index=True)
    name: Mapped[str] = mapped_column(String(128), default="")
    payload: Mapped[str] = mapped_column(Text, default="null")
    updated_at: Mapped[int] = mapped_column(BigInteger)
    deleted: Mapped[bool] = mapped_column(default=False)


class TextRow(Base):
    """A generated/pasted reading text. Tokens, sentences and the aligned
    translation live in [payload]; columns cover what the server may need
    to query (per-course listing, difficulty filtering)."""

    __tablename__ = "texts"

    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    course_id: Mapped[str] = mapped_column(String(64), default="", index=True)
    title: Mapped[str] = mapped_column(String(256), default="")
    level: Mapped[str] = mapped_column(String(32), default="")
    payload: Mapped[str] = mapped_column(Text, default="null")
    updated_at: Mapped[int] = mapped_column(BigInteger)
    deleted: Mapped[bool] = mapped_column(default=False)


class ConversationRow(Base):
    """A Converse thread; messages ride inside [payload]. Granularity is the
    whole conversation — users edit one thread at a time, so per-thread
    last-write-wins is enough (messages would get own rows if two devices
    ever need to append to the same thread concurrently)."""

    __tablename__ = "conversations"

    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    course_id: Mapped[str] = mapped_column(String(64), default="", index=True)
    title: Mapped[str] = mapped_column(String(256), default="")
    starred: Mapped[bool] = mapped_column(default=False)
    payload: Mapped[str] = mapped_column(Text, default="null")
    updated_at: Mapped[int] = mapped_column(BigInteger)
    deleted: Mapped[bool] = mapped_column(default=False)


class UserData(Base):
    """One row per (user, AppStorage key). Value is raw JSON text.

    updated_at is the client-side wall clock in ms — last write wins.
    """

    __tablename__ = "user_data"

    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    key: Mapped[str] = mapped_column(String(64), primary_key=True)
    value: Mapped[str] = mapped_column(Text)
    updated_at: Mapped[int] = mapped_column(BigInteger)
