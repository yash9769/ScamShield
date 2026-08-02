import os
import time
import logging
import httpx
from typing import Dict, Any

logger = logging.getLogger(__name__)

class MobSFService:
    def __init__(self):
        self.url = os.getenv("MOBSF_URL", "http://mobsf:8000")
        self.api_key = os.getenv("MOBSF_API_KEY", "mobsf_api_key_123")
        self.headers = {"Authorization": self.api_key}

    async def analyze(self, apk_path: str) -> Dict[str, Any]:
        """Uploads APK to MobSF, waits for analysis, and returns the report."""
        logger.info(f"Starting MobSF analysis for {apk_path}")
        
        try:
            # 1. Upload APK
            async with httpx.AsyncClient(timeout=60.0) as client:
                with open(apk_path, "rb") as f:
                    files = {"file": (os.path.basename(apk_path), f, "application/vnd.android.package-archive")}
                    response = await client.post(f"{self.url}/api/v1/upload", headers=self.headers, files=files)
                
                if response.status_code != 200:
                    logger.error(f"MobSF upload failed: {response.text}")
                    return {"status": "error", "error": "MobSF upload failed"}
                
                upload_data = response.json()
                hash_val = upload_data.get("hash")
                scan_type = upload_data.get("scan_type", "apk")
                file_name = upload_data.get("file_name")

            # 2. Trigger Scan
            async with httpx.AsyncClient(timeout=300.0) as client: # Scan can take a while
                scan_data = {"hash": hash_val, "scan_type": scan_type, "file_name": file_name}
                response = await client.post(f"{self.url}/api/v1/scan", headers=self.headers, data=scan_data)
                
                if response.status_code != 200:
                    logger.error(f"MobSF scan failed: {response.text}")
                    return {"status": "error", "error": "MobSF scan failed"}

            # 3. Fetch JSON Report
            async with httpx.AsyncClient(timeout=60.0) as client:
                report_data = {"hash": hash_val}
                response = await client.post(f"{self.url}/api/v1/report_json", headers=self.headers, data=report_data)
                
                if response.status_code != 200:
                    logger.error(f"MobSF report fetch failed: {response.text}")
                    return {"status": "error", "error": "MobSF report fetch failed"}
                
                report = response.json()
                
            return {
                "status": "success",
                "report": report
            }
            
        except Exception as e:
            logger.error(f"MobSF Service error: {e}")
            return {"status": "error", "error": str(e)}
