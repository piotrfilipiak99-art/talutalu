"""Engine/session setup. SQLite locally, Postgres on Render via DATABASE_URL."""
import os

from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, Session

DATABASE_URL = os.environ.get("DATABASE_URL", "sqlite:///./talutalu.db")
# Render provides postgres:// URLs; SQLAlchemy + psycopg3 wants postgresql+psycopg://
if DATABASE_URL.startswith("postgres://"):
    DATABASE_URL = DATABASE_URL.replace("postgres://", "postgresql+psycopg://", 1)
elif DATABASE_URL.startswith("postgresql://"):
    DATABASE_URL = DATABASE_URL.replace("postgresql://", "postgresql+psycopg://", 1)

# A hung/unreachable Postgres must fail fast, not hang forever: this engine
# is created and Base.metadata.create_all() runs at import time in main.py,
# before the FastAPI app object even exists - an unbounded connect here
# blocks every request (even /health) indefinitely instead of surfacing a
# crash Render can show in its logs and restart from.
connect_args = (
    {"check_same_thread": False}
    if DATABASE_URL.startswith("sqlite")
    else {"connect_timeout": 10}
)
engine = create_engine(DATABASE_URL, connect_args=connect_args)


class Base(DeclarativeBase):
    pass


def get_db():
    with Session(engine) as session:
        yield session
