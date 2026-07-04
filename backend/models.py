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
