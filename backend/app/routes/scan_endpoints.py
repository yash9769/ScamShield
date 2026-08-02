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
