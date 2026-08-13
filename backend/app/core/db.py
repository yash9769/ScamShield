from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from typing import AsyncGenerator
from app.core.config import get_settings

settings = get_settings()

db_url = settings.DATABASE_URL
try:
    engine = create_async_engine(db_url, echo=settings.DEBUG, future=True)
except Exception:
    db_url = "sqlite+aiosqlite:///scamshield.db"
    try:
        engine = create_async_engine(db_url, echo=settings.DEBUG, future=True)
    except Exception:
        db_url = "sqlite+aiosqlite:///:memory:"
        engine = create_async_engine(db_url, echo=settings.DEBUG, future=True)

async_session_maker = async_sessionmaker(
    engine, class_=AsyncSession, expire_on_commit=False
)

async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with async_session_maker() as session:
        yield session
