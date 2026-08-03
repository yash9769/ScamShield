from sqlalchemy import Column, Integer, String, Float, DateTime, JSON, ForeignKey, Boolean
from sqlalchemy.orm import relationship
from datetime import datetime, timezone
import uuid

from app.models.base import Base

def generate_uuid():
    return str(uuid.uuid4())

def current_time():
    return datetime.now(timezone.utc).replace(tzinfo=None)

class User(Base):
    __tablename__ = "users"
    
    id = Column(String, primary_key=True, default=generate_uuid)
    username = Column(String, unique=True, index=True)
    created_at = Column(DateTime(timezone=True), default=current_time)
    
    scans = relationship("Scan", back_populates="user")

class Scan(Base):
    __tablename__ = "scans"
    
    id = Column(String, primary_key=True, default=generate_uuid)
    user_id = Column(String, ForeignKey("users.id"), nullable=True)
    sha256 = Column(String, index=True, nullable=False)
    package = Column(String, index=True)
    version = Column(String)
    risk_score = Column(Float)
    severity = Column(String)
    timestamp = Column(DateTime(timezone=True), default=current_time)
    
    # Store results as JSON or references
    mobsf_scan_id = Column(String)
    osint_results = Column(JSON)
    status = Column(String, default="pending")
    
    user = relationship("User", back_populates="scans")
    reports = relationship("Report", back_populates="scan", cascade="all, delete-orphan")
    scan_logs = relationship("ScanLog", back_populates="scan", cascade="all, delete-orphan")

class Report(Base):
    __tablename__ = "reports"
    
    id = Column(String, primary_key=True, default=generate_uuid)
    scan_id = Column(String, ForeignKey("scans.id"), unique=True)
    generated_at = Column(DateTime(timezone=True), default=current_time)
    json_path = Column(String)
    pdf_path = Column(String)
    
    scan = relationship("Scan", back_populates="reports")

class CachedOSINT(Base):
    __tablename__ = "cached_osint"
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    ioc_type = Column(String, index=True) # "hash", "url", "ip"
    ioc_value = Column(String, index=True)
    provider = Column(String) # "virustotal", "safebrowsing"
    data = Column(JSON)
    created_at = Column(DateTime(timezone=True), default=current_time)
    expires_at = Column(DateTime(timezone=True))

class APIUsage(Base):
    __tablename__ = "api_usage"
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    provider = Column(String, index=True)
    timestamp = Column(DateTime(timezone=True), default=current_time)
    status_code = Column(Integer)
    response_time_ms = Column(Integer)
    success = Column(Boolean)

class ScanLog(Base):
    __tablename__ = "scan_logs"
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    scan_id = Column(String, ForeignKey("scans.id"))
    analyzer_name = Column(String)
    start_time = Column(DateTime(timezone=True), default=current_time)
    end_time = Column(DateTime(timezone=True), nullable=True)
    success = Column(Boolean)
    error_message = Column(String, nullable=True)
    
    scan = relationship("Scan", back_populates="scan_logs")
