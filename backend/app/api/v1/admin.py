"""
backend/app/api/v1/admin.py
Admin-only dashboard and audit-log endpoints.

Every route here is guarded by ``verify_admin_auth`` (Authorization: Bearer
<ADMIN_API_KEY> or X-Admin-Key). The dashboard HTML is self-contained and asks
the operator for the admin key — it ships without any hardcoded default.
"""

from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import FileResponse

from app.core.config import get_settings
from app.core.logging import get_logger
from app.middleware.api_auth import verify_admin_auth
from app.services.audit import audit_stats, fetch_audit_logs
from app.services.llm_cache import cache_stats

logger = get_logger(__name__)
router = APIRouter(tags=["admin"])

# Resolve to backend/app/static/dashboard.html. The router lives in
# app/api/v1/, so it takes three parents to reach the package root, not two
# (parent.parent would land in app/api/static/, which does not exist).
_STATIC_DIR = Path(__file__).resolve().parent.parent.parent / "static"
_DASHBOARD_PATH = _STATIC_DIR / "dashboard.html"


@router.get(
    "/dashboard",
    response_class=FileResponse,
    dependencies=[Depends(verify_admin_auth)],
    summary="Admin dashboard UI",
)
async def dashboard() -> FileResponse:
    if not _DASHBOARD_PATH.is_file():
        raise HTTPException(status_code=404, detail="Dashboard asset not found")
    return FileResponse(_DASHBOARD_PATH, media_type="text/html")


@router.get(
    "/api/audit-logs",
    dependencies=[Depends(verify_admin_auth)],
    summary="Recent audit log entries",
)
async def audit_logs(limit: int = Query(50, ge=1, le=100)) -> list[dict]:
    return fetch_audit_logs(limit=limit)


@router.get(
    "/api/stats",
    dependencies=[Depends(verify_admin_auth)],
    summary="Operational stats for the dashboard",
)
async def stats() -> dict:
    settings = get_settings()
    return {
        "status": "ok",
        "app": settings.APP_NAME,
        "version": settings.VERSION,
        **audit_stats(),
        **cache_stats(),
    }
