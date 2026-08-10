import subprocess
import os
import shutil
import logging
from typing import Dict, Any

logger = logging.getLogger(__name__)

class APKToolAnalyzer:
    def __init__(self, output_base_dir: str = "/tmp/scamshield/apktool"):
        self.output_base_dir = output_base_dir
        os.makedirs(self.output_base_dir, exist_ok=True)

    def analyze(self, apk_path: str, apk_hash: str) -> Dict[str, Any]:
        logger.info(f"Running APKTool on {apk_path}")
        output_dir = os.path.join(self.output_base_dir, apk_hash)
        
        try:
            # -s: do not decode sources, just resources (faster if JADX is handling sources)
            # -f: force overwrite
            cmd = ["apktool", "d", "-s", "-f", apk_path, "-o", output_dir]
            result = subprocess.run(cmd, capture_output=True, text=True, check=True, timeout=60)
            logger.info("APKTool finished successfully.")
            
            # Check what got extracted
            extracted_items = os.listdir(output_dir) if os.path.exists(output_dir) else []
            
            return {
                "status": "success",
                "output_dir": output_dir,
                "extracted_items": extracted_items,
                "manifest_found": "AndroidManifest.xml" in extracted_items
            }
        except subprocess.TimeoutExpired as e:
            logger.error("APKTool timed out after 60 seconds.")
            return {
                "status": "error",
                "error": "APKTool analysis timed out."
            }
        except subprocess.CalledProcessError as e:
            logger.error(f"APKTool failed: {e.stderr}")
            return {
                "status": "error",
                "error": e.stderr
            }
        finally:
            if os.path.exists(output_dir):
                try:
                    shutil.rmtree(output_dir)
                except Exception as ex:
                    logger.warning(f"Failed to clean up APKTool temp directory: {ex}")
