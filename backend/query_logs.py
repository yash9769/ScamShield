import asyncio
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from sqlalchemy import text
import os
from dotenv import load_dotenv

load_dotenv("docker/.env")
DB_URL = "postgresql+asyncpg://scamshield:securepassword@localhost:5433/scamshield_db"

async def main():
    engine = create_async_engine(DB_URL)
    async_session = sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)
    
    async with async_session() as session:
        result = await session.execute(text("SELECT COUNT(*) FROM scan_logs"))
        print(f"Number of scan_logs: {result.scalar()}")

asyncio.run(main())
