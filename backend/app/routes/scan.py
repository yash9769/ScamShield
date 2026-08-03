import os
import uuid
import hashlib
import shutil
import logging
import asyncio
from typing import Dict, Any, List

from fastapi import APIRouter, UploadFile, File, BackgroundTasks, HTTPException, Depends
from fastapi.responses import JSONResponse
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select

from app.core.db import get_db
from app.models.schema import Scan, Report, APIUsage, ScanLog, current_time
from app.analyzers.apktool import APKToolAnalyzer
from app.analyzers.jadx import JADXAnalyzer
from app.analyzers.androguard_analyzer import AndroguardAnalyzer
from app.analyzers.yara_analyzer import YaraAnalyzer
from app.analyzers.secrets_analyzer import SecretsAnalyzer
from app.services.mobsf import MobSFService
from app.services.osint import OSINTService
from app.services.risk_engine import RiskEngine
from app.services.ai_explanation import AIExplanationService
from app.reports.generator import ReportGenerator
import app.services.progress as progress_svc # A new progress tracker
import re

logger = logging.getLogger(__name__)
router = APIRouter()

UPLOAD_DIR = "/app/uploads"
os.makedirs(UPLOAD_DIR, exist_ok=True)

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

MAX_FILE_SIZE = 200 * 1024 * 1024  # 200MB

@router.post("/scan")
async def upload_apk(file: UploadFile = File(...), db: AsyncSession = Depends(get_db)):
    if not file.filename.endswith('.apk'):
        raise HTTPException(status_code=400, detail="Only APK files are allowed.")
    
    # 1. Save File Securely
    report_id = str(uuid.uuid4())
    safe_filename = re.sub(r'[^a-zA-Z0-9_\-\.]', '_', file.filename)
    apk_path = os.path.join(UPLOAD_DIR, f"{report_id}.apk")
    
    scan_logs: List[ScanLog] = []

    async def run_with_log(analyzer_name, coro_or_func, *args, **kwargs):
        start_time = current_time()
        success = True
        error_msg = None
        res = None
        try:
            if asyncio.iscoroutinefunction(coro_or_func) or asyncio.iscoroutine(coro_or_func):
                res = await coro_or_func(*args, **kwargs)
            else:
                res = await asyncio.to_thread(coro_or_func, *args, **kwargs)
                
            if isinstance(res, dict) and res.get("status") == "error":
                success = False
                error_msg = res.get("reason", "Unknown error")
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
    
    try:
        with open(apk_path, "wb") as buffer:
            while chunk := await file.read(8192):
                file_size += len(chunk)
                if file_size > MAX_FILE_SIZE:
                    os.remove(apk_path)
                    raise HTTPException(status_code=413, detail="File too large")
                buffer.write(chunk)
                sha256_hash.update(chunk)
                
        apk_hash = sha256_hash.hexdigest()
        
        # Check if already scanned
        result = await db.execute(select(Scan).where(Scan.sha256 == apk_hash))
        existing_scan = result.scalars().first()
        if existing_scan and existing_scan.status == "completed":
            json_path = os.path.join("/app/reports", f"{existing_scan.id}.json")
            if os.path.exists(json_path):
                import json
                with open(json_path, 'r') as f:
                    return JSONResponse(content=json.load(f))
                    
        new_scan = Scan(id=report_id, sha256=apk_hash, package="Unknown", status="processing")
        db.add(new_scan)
        await db.commit()
        await db.refresh(new_scan)
        
        # 2. Run initial independent analyzers concurrently
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
        
        extracted_dirs = []
        if isinstance(apktool_res, dict) and apktool_res.get("status") == "success":
            extracted_dirs.append(apktool_res.get("output_dir"))
        if isinstance(jadx_res, dict) and jadx_res.get("status") == "success":
            extracted_dirs.append(jadx_res.get("output_dir"))
            
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
            "filename": file.filename,
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

        # 5. AI Explanation
        await progress_svc.update_progress(report_id, "Generating AI Summary", 90)
        ai_res = await ai_service.generate_explanation(risk_res, analysis_data)
        analysis_data["ai_explanation"] = ai_res
        
        # 6. Generate Reports
        await progress_svc.update_progress(report_id, "Generating Reports", 95)
        json_path = os.path.join("/app/reports", f"{report_id}.json")
        pdf_path = os.path.join("/app/reports", f"{report_id}.pdf")
        
        await asyncio.to_thread(report_gen.save_json, report_id, analysis_data)
        await asyncio.to_thread(report_gen.generate_pdf, report_id, analysis_data)
        
        # Update DB
        new_scan.package = andro_res.get("package", "Unknown") if isinstance(andro_res, dict) else "Unknown"
        new_scan.version = andro_res.get("version", "") if isinstance(andro_res, dict) else ""
        new_scan.risk_score = risk_res.get("score", 0.0)
        new_scan.severity = risk_res.get("severity", "LOW")
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
        
    except Exception as e:
        logger.error(f"Error processing upload: {e}")
        # Update DB status
        try:
            result = await db.execute(select(Scan).where(Scan.id == report_id))
            fail_scan = result.scalars().first()
            if fail_scan:
                fail_scan.status = "failed"
                await db.commit()
        except:
            pass
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/scan/{report_id}")
async def get_report(report_id: str, db: AsyncSession = Depends(get_db)):
    # Serve JSON from file or DB
    json_path = os.path.join("/app/reports", f"{report_id}.json")
    if os.path.exists(json_path):
        with open(json_path, 'r') as f:
            import json
            return JSONResponse(content=json.load(f))
    raise HTTPException(status_code=404, detail="Report not found")

@router.delete("/scan/{report_id}")
async def delete_report(report_id: str, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Scan).where(Scan.id == report_id))
    scan = result.scalars().first()
    if not scan:
        raise HTTPException(status_code=404, detail="Scan not found")
        
    # Delete from DB
    await db.delete(scan)
    await db.commit()
    
    # Delete files
    json_path = os.path.join("/app/reports", f"{report_id}.json")
    pdf_path = os.path.join("/app/reports", f"{report_id}.pdf")
    apk_path = os.path.join("/app/uploads", f"{report_id}.apk")
    for path in [json_path, pdf_path, apk_path]:
        if os.path.exists(path):
            os.remove(path)
            
    return {"status": "deleted"}

@router.get("/history")
async def get_history(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Scan).order_by(Scan.timestamp.desc()).limit(100))
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
async def scan_progress(report_id: str):
    """Server-Sent Events endpoint for real-time progress."""
    async def event_generator():
        pubsub = progress_svc.redis_client.pubsub()
        await pubsub.subscribe(f"scan_progress:{report_id}")
        
        # Yield the latest cached status immediately if exists
        latest = await progress_svc.redis_client.get(f"scan_status:{report_id}")
        if latest:
            yield f"data: {latest}\n\n"
            
        async for message in pubsub.listen():
            if message["type"] == "message":
                data = message["data"]
                yield f"data: {data}\n\n"
                if '"percentage": 100' in data or '"status": "failed"' in data:
                    break
                    
        await pubsub.unsubscribe()
        
    return StreamingResponse(event_generator(), media_type="text/event-stream")

@router.get("/health")
async def health_check():
    return {"status": "healthy"}
