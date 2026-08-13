import os
import uuid
import hashlib
import shutil
import logging
import asyncio
import zipfile
from typing import Dict, Any, List, Optional

from fastapi import APIRouter, UploadFile, File, BackgroundTasks, HTTPException, Depends
from fastapi.responses import JSONResponse
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select

from app.core.config import get_settings
from app.core.db import get_db
from app.models.schema import Scan, Report, APIUsage, ScanLog, current_time
from app.analyzers.apktool import APKToolAnalyzer
from app.analyzers.jadx import JADXAnalyzer
from app.analyzers.androguard_analyzer import AndroguardAnalyzer
from app.analyzers.yara_analyzer import YaraAnalyzer
from app.analyzers.secrets_analyzer import SecretsAnalyzer
from app.middleware.api_auth import get_api_client
from app.services.mobsf import MobSFService
from app.services.osint import OSINTService
from app.services.risk_engine import RiskEngine
from app.services.ai_explanation import AIExplanationService
from app.services.audit import log_audit_event
from app.reports.generator import ReportGenerator
import app.services.progress as progress_svc # A new progress tracker
import re

logger = logging.getLogger(__name__)
router = APIRouter()

_settings = get_settings()
UPLOAD_DIR = _settings.UPLOAD_DIR
REPORTS_DIR = _settings.REPORTS_DIR
os.makedirs(UPLOAD_DIR, exist_ok=True)
os.makedirs(REPORTS_DIR, exist_ok=True)

# Initialize stateless services
apktool = APKToolAnalyzer()
jadx = JADXAnalyzer()
androguard = AndroguardAnalyzer()
yara_analyzer = YaraAnalyzer()
secrets = SecretsAnalyzer()
mobsf = MobSFService()
risk_engine = RiskEngine()
ai_service = AIExplanationService()
report_gen = ReportGenerator()

# ── Resource-exhaustion guards (P0 hardening) ────────────────────────────────
MAX_FILE_SIZE = 200 * 1024 * 1024  # 200MB on-the-wire limit
MAX_ZIP_ENTRIES = 5_000            # hard cap on APK/ZIP member count
MAX_UNCOMPRESSED_BYTES = 1_500 * 1024 * 1024  # 1.5GB expansion quota
MAX_COMPRESSION_RATIO = 250        # zip-bomb guard (uncompressed / compressed)
MAX_CONCURRENT_SCANS = 2           # heavy analysis is expensive; serialize it
SCAN_TIMEOUT_SECONDS = 900         # total per-scan wall-clock budget

_scan_slots = asyncio.Semaphore(MAX_CONCURRENT_SCANS)


class ScanBusy(Exception):
    """Raised when the scan concurrency cap is reached."""


def _validate_archive(path: str) -> None:
    """Reject ZIP bombs before any heavy analysis runs.

    Checks, in order: total uncompressed size, member count, and per-member
    compression ratio. Raises HTTPException on violation.
    """
    try:
        with zipfile.ZipFile(path) as zf:
            infos = zf.infolist()
            if len(infos) > MAX_ZIP_ENTRIES:
                raise HTTPException(
                    status_code=413,
                    detail=f"APK contains too many entries ({len(infos)} > {MAX_ZIP_ENTRIES})",
                )
            total_uncompressed = 0
            for info in infos:
                total_uncompressed += info.file_size
                if total_uncompressed > MAX_UNCOMPRESSED_BYTES:
                    raise HTTPException(
                        status_code=413,
                        detail="APK expands beyond the allowed uncompressed size limit",
                    )
                if info.compress_size > 0 and info.file_size > 0:
                    ratio = info.file_size / info.compress_size
                    if ratio > MAX_COMPRESSION_RATIO:
                        raise HTTPException(
                            status_code=413,
                            detail=f"APK member '{info.filename}' has an implausible "
                                   f"compression ratio ({ratio:.0f}:1) — possible ZIP bomb",
                        )
    except HTTPException:
        raise
    except zipfile.BadZipFile:
        raise HTTPException(status_code=400, detail="File is not a valid APK (bad ZIP archive)")
    except Exception as exc:
        logger.warning("Archive validation error: %s", exc)
        raise HTTPException(status_code=400, detail="File could not be validated as an APK")


def _cleanup(*paths: Optional[str]) -> None:
    """Best-effort removal of uploaded/extracted files (never raises)."""
    for p in paths:
        if not p:
            continue
        try:
            if os.path.isdir(p):
                shutil.rmtree(p, ignore_errors=True)
            elif os.path.exists(p):
                os.remove(p)
        except Exception as exc:
            logger.warning("Cleanup failed for %s: %s", p, exc)


async def _acquire_scan_slot() -> None:
    try:
        await asyncio.wait_for(_scan_slots.acquire(), timeout=1.0)
    except asyncio.TimeoutError:
        raise ScanBusy()


@router.post("/scan")
async def upload_apk(file: UploadFile = File(...), db: AsyncSession = Depends(get_db), client: str | None = Depends(get_api_client)):
    if not file.filename.endswith('.apk'):
        raise HTTPException(status_code=400, detail="Only APK files are allowed.")

    try:
        await _acquire_scan_slot()
    except ScanBusy:
        raise HTTPException(
            status_code=429,
            detail="Scan queue full — too many concurrent scans. Please retry shortly.",
        )

    report_id = str(uuid.uuid4())
    safe_filename = re.sub(r'[^a-zA-Z0-9_\-\\.]', '_', file.filename)
    apk_path = os.path.join(UPLOAD_DIR, f"{report_id}.apk")
    extracted_dirs: List[str] = []

    try:
        return await _run_scan_pipeline(
            file=file,
            db=db,
            client=client,
            report_id=report_id,
            safe_filename=safe_filename,
            apk_path=apk_path,
            extracted_dirs=extracted_dirs,
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error processing upload: {e}")
        try:
            result = await db.execute(select(Scan).where(Scan.id == report_id))
            fail_scan = result.scalars().first()
            if fail_scan:
                fail_scan.status = "failed"
                await db.commit()
        except Exception:
            pass
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        # Release the concurrency slot and clean up uploaded/extracted files.
        _scan_slots.release()
        if apk_path and os.path.exists(apk_path):
            _cleanup(apk_path, *extracted_dirs)


async def _run_scan_pipeline(
    *,
    file: UploadFile,
    db: AsyncSession,
    client: Optional[str],
    report_id: str,
    safe_filename: str,
    apk_path: str,
    extracted_dirs: List[str],
) -> JSONResponse:
    """The full APK analysis pipeline, guarded by timeouts + cleanup."""
    scan_logs: List[ScanLog] = []

    async def run_with_log(analyzer_name, coro_or_func, *args, **kwargs):
        start_time = current_time()
        success = True
        error_msg = None
        res = None
        try:
            coro = asyncio.ensure_future(
                coro_or_func(*args, **kwargs)
                if asyncio.iscoroutinefunction(coro_or_func)
                else asyncio.to_thread(coro_or_func, *args, **kwargs)
            )
            res = await asyncio.wait_for(coro, timeout=SCAN_TIMEOUT_SECONDS)

            if isinstance(res, dict) and res.get("status") == "error":
                success = False
                error_msg = res.get("reason", "Unknown error")
        except asyncio.TimeoutError:
            success = False
            error_msg = f"{analyzer_name} exceeded the {SCAN_TIMEOUT_SECONDS}s timeout"
            res = {"status": "error", "reason": error_msg}
            logger.warning(f"{analyzer_name} timed out for scan {report_id}")
        except Exception as e:
            success = False
            error_msg = str(e)
            res = {"status": "error", "reason": str(e)}
            logger.error(f"{analyzer_name} error: {e}")

        end_time = current_time()
        scan_logs.append(ScanLog(
            scan_id=report_id,
            analyzer_name=analyzer_name,
            start_time=start_time,
            end_time=end_time,
            success=success,
            error_message=error_msg
        ))
        return res

    file_size = 0
    sha256_hash = hashlib.sha256()

    # 0. Stream upload to disk with a hard size cap.
    with open(apk_path, "wb") as buffer:
        while chunk := await file.read(8192):
            file_size += len(chunk)
            if file_size > MAX_FILE_SIZE:
                raise HTTPException(status_code=413, detail="File too large")
            buffer.write(chunk)
            sha256_hash.update(chunk)

    apk_hash = sha256_hash.hexdigest()

    # 1. Reject ZIP bombs before any heavy tooling runs.
    _validate_archive(apk_path)

    # Check if already scanned (dedup)
    result = await db.execute(select(Scan).where(Scan.sha256 == apk_hash))
    existing_scan = result.scalars().first()
    if existing_scan and existing_scan.status == "completed":
        json_path = os.path.join(REPORTS_DIR, f"{existing_scan.id}.json")
        if os.path.exists(json_path):
            import json
            with open(json_path, 'r') as f:
                return JSONResponse(content=json.load(f))

    new_scan = Scan(id=report_id, sha256=apk_hash, package="Unknown", status="processing", owner=client)
    db.add(new_scan)
    await db.commit()
    await db.refresh(new_scan)

    # 2. Run initial independent analyzers concurrently (each with a timeout)
    await progress_svc.update_progress(report_id, "Running static and dynamic analyzers", 20)

    andro_task = asyncio.create_task(run_with_log("Androguard", androguard.analyze, apk_path))
    apktool_task = asyncio.create_task(run_with_log("APKTool", apktool.analyze, apk_path, apk_hash))
    jadx_task = asyncio.create_task(run_with_log("JADX", jadx.analyze, apk_path, apk_hash))
    mobsf_task = asyncio.create_task(run_with_log("MobSF", mobsf.analyze, apk_path))
    osint_svc = OSINTService(db)
    osint_task = asyncio.create_task(run_with_log("OSINT", osint_svc.analyze_hash, apk_hash))

    andro_res, apktool_res, jadx_res, mobsf_res, osint_res = await asyncio.gather(
        andro_task, apktool_task, jadx_task, mobsf_task, osint_task, return_exceptions=True
    )

    # Clean up exceptions if they slipped through
    andro_res = andro_res if not isinstance(andro_res, Exception) else {"status": "error"}
    apktool_res = apktool_res if not isinstance(apktool_res, Exception) else {"status": "error"}
    jadx_res = jadx_res if not isinstance(jadx_res, Exception) else {"status": "error"}
    mobsf_res = mobsf_res if not isinstance(mobsf_res, Exception) else {"status": "error"}
    osint_res = osint_res if not isinstance(osint_res, Exception) else {"virustotal": {"status": "error"}}

    await progress_svc.update_progress(report_id, "Running YARA and Secrets analyzers", 50)

    if isinstance(apktool_res, dict) and apktool_res.get("status") == "success":
        out = apktool_res.get("output_dir")
        if out:
            extracted_dirs.append(out)
    if isinstance(jadx_res, dict) and jadx_res.get("status") == "success":
        out = jadx_res.get("output_dir")
        if out:
            extracted_dirs.append(out)

    async def secrets_wrapper():
        if isinstance(jadx_res, dict) and jadx_res.get("status") == "success":
            return await asyncio.to_thread(secrets.analyze, jadx_res["output_dir"])
        return {"status": "skipped"}

    yara_task = asyncio.create_task(run_with_log("YARA", yara_analyzer.analyze, apk_path, extracted_dirs))
    secrets_task = asyncio.create_task(run_with_log("Secrets", secrets_wrapper))

    yara_res, secrets_res = await asyncio.gather(yara_task, secrets_task, return_exceptions=True)
    yara_res = yara_res if not isinstance(yara_res, Exception) else {"status": "error"}
    secrets_res = secrets_res if not isinstance(secrets_res, Exception) else {"status": "error"}

    # 3. Aggregate data
    analysis_data = {
        "report_id": report_id,
        "filename": safe_filename,
        "hash": apk_hash,
        "status": "completed",
        "androguard": andro_res,
        "apktool": apktool_res,
        "jadx": jadx_res,
        "yara": yara_res,
        "secrets": secrets_res,
        "osint": osint_res,
        "mobsf": mobsf_res
    }

    await progress_svc.update_progress(report_id, "Calculating Risk", 80)

    # 4. Risk Engine
    risk_res = risk_engine.calculate_risk(analysis_data)
    analysis_data["risk"] = risk_res

    log_audit_event(
        event_type="scan",
        target=safe_filename,
        risk_score=int(risk_res.get("score", 0)),
        risk_level=str(risk_res.get("level", "LOW")),
    )

    # 5. AI Explanation
    await progress_svc.update_progress(report_id, "Generating AI Summary", 90)
    ai_res = await ai_service.generate_explanation(risk_res, analysis_data)
    analysis_data["ai_explanation"] = ai_res

    # 6. Generate Reports
    await progress_svc.update_progress(report_id, "Generating Reports", 95)
    json_path = os.path.join(REPORTS_DIR, f"{report_id}.json")
    pdf_path = os.path.join(REPORTS_DIR, f"{report_id}.pdf")

    await asyncio.to_thread(report_gen.save_json, report_id, analysis_data)
    await asyncio.to_thread(report_gen.generate_pdf, report_id, analysis_data)

    # Update DB
    new_scan.package = andro_res.get("package", "Unknown") if isinstance(andro_res, dict) else "Unknown"
    new_scan.version = andro_res.get("version", "") if isinstance(andro_res, dict) else ""
    new_scan.risk_score = risk_res.get("score", 0.0)
    # risk_engine.calculate_risk() returns the key as "level"; "severity" is the DB column name.
    new_scan.severity = risk_res.get("level", "LOW")
    new_scan.mobsf_scan_id = apk_hash
    new_scan.status = "completed"

    report_record = Report(scan_id=report_id, json_path=json_path, pdf_path=pdf_path)
    db.add(report_record)

    # Save scan logs
    if scan_logs:
        db.add_all(scan_logs)

    await db.commit()

    await progress_svc.update_progress(report_id, "Completed", 100)
    return JSONResponse(content=analysis_data)


async def _scan_owned_by(scan: Optional[Scan], client: Optional[str]) -> bool:
    """A scan is visible to the caller if it has no owner (legacy/trusted-net)
    or the caller's credential fingerprint matches its owner."""
    if scan is None:
        return False
    if client is None or scan.owner is None:
        return True
    return scan.owner == client


@router.get("/scan/{report_id}")
async def get_report(report_id: str, db: AsyncSession = Depends(get_db), client: str | None = Depends(get_api_client)):
    # Serve JSON from file or DB — only if the caller owns this scan.
    result = await db.execute(select(Scan).where(Scan.id == report_id))
    scan = result.scalars().first()
    if not await _scan_owned_by(scan, client):
        raise HTTPException(status_code=404, detail="Report not found")

    json_path = os.path.join(REPORTS_DIR, f"{report_id}.json")
    if os.path.exists(json_path):
        with open(json_path, 'r') as f:
            import json
            return JSONResponse(content=json.load(f))
    raise HTTPException(status_code=404, detail="Report not found")


@router.delete("/scan/{report_id}")
async def delete_report(report_id: str, db: AsyncSession = Depends(get_db), client: str | None = Depends(get_api_client)):
    result = await db.execute(select(Scan).where(Scan.id == report_id))
    scan = result.scalars().first()
    if not await _scan_owned_by(scan, client):
        raise HTTPException(status_code=404, detail="Scan not found")

    # Delete from DB
    await db.delete(scan)
    await db.commit()

    # Delete files
    json_path = os.path.join(REPORTS_DIR, f"{report_id}.json")
    pdf_path = os.path.join(REPORTS_DIR, f"{report_id}.pdf")
    apk_path = os.path.join(UPLOAD_DIR, f"{report_id}.apk")
    for path in [json_path, pdf_path, apk_path]:
        if os.path.exists(path):
            os.remove(path)

    return {"status": "deleted"}


@router.get("/history")
async def get_history(db: AsyncSession = Depends(get_db), client: str | None = Depends(get_api_client)):
    # Only return scans owned by this caller (when auth is on).
    stmt = select(Scan)
    if client is not None:
        stmt = stmt.where(Scan.owner == client)
    stmt = stmt.order_by(Scan.timestamp.desc()).limit(100)
    result = await db.execute(stmt)
    scans = result.scalars().all()
    history = []
    for s in scans:
        history.append({
            "id": s.id,
            "package": s.package,
            "version": s.version,
            "risk_score": s.risk_score,
            "severity": s.severity,
            "status": s.status,
            "timestamp": s.timestamp.isoformat() if s.timestamp else None
        })
    return {"history": history}


from fastapi.responses import StreamingResponse

@router.get("/scan/{report_id}/progress")
async def scan_progress(report_id: str, db: AsyncSession = Depends(get_db), client: str | None = Depends(get_api_client)):
    """Server-Sent Events endpoint for real-time progress."""
    result = await db.execute(select(Scan).where(Scan.id == report_id))
    scan = result.scalars().first()
    if not await _scan_owned_by(scan, client):
        raise HTTPException(status_code=404, detail="Scan not found")

    async def event_generator():
        client = progress_svc.redis_client
        if client is None:
            # Redis is not configured/reachable: live progress cannot be
            # streamed. Say so explicitly instead of failing silently — the
            # scan itself still completes and its result is returned normally.
            yield (
                'data: {"message": "Live progress unavailable (Redis is not '
                'configured on this server). The result will appear when '
                'analysis completes.", "percentage": null}\n\n'
            )
            return

        pubsub = client.pubsub()
        await pubsub.subscribe(f"scan_progress:{report_id}")

        # Yield the latest cached status immediately if exists
        latest = await client.get(f"scan_status:{report_id}")
        if latest:
            yield f"data: {latest}\n\n"

        try:
            async for message in pubsub.listen():
                if message["type"] == "message":
                    data = message["data"]
                    yield f"data: {data}\n\n"
                    if '"percentage": 100' in data or '"status": "failed"' in data:
                        break
        finally:
            await pubsub.unsubscribe()

    return StreamingResponse(event_generator(), media_type="text/event-stream")


@router.get("/health")
async def health_check():
    return {"status": "healthy"}
