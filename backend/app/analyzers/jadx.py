import subprocess
import os
import logging
from typing import Dict, Any, List
import re

logger = logging.getLogger(__name__)

class JADXAnalyzer:
    def __init__(self, output_base_dir: str = "/tmp/scamshield/jadx"):
        self.output_base_dir = output_base_dir
        os.makedirs(self.output_base_dir, exist_ok=True)

    def analyze(self, apk_path: str, apk_hash: str) -> Dict[str, Any]:
        logger.info(f"Running JADX on {apk_path}")
        output_dir = os.path.join(self.output_base_dir, apk_hash)
        
        try:
            # -d: output directory
            # --no-res: do not decode resources (APKTool handles this)
            cmd = ["jadx", "-d", output_dir, "--no-res", apk_path]
            subprocess.run(cmd, capture_output=True, text=True, check=True)
            logger.info("JADX finished successfully.")
            
            # Basic static analysis on decompiled sources
            findings = self._scan_sources(output_dir)
            
            return {
                "status": "success",
                "output_dir": output_dir,
                "findings": findings
            }
        except subprocess.CalledProcessError as e:
            logger.error(f"JADX failed: {e.stderr}")
            return {
                "status": "error",
                "error": e.stderr
            }

    def _scan_sources(self, output_dir: str) -> Dict[str, List[str]]:
        findings = {
            "reflection": [],
            "runtime_exec": [],
            "process_builder": [],
            "dex_class_loader": [],
            "accessibility_service": [],
            "add_javascript_interface": [],
            "crypto_cipher": [],
        }
        
        # Walk through the output directory and scan java files
        for root, _, files in os.walk(output_dir):
            for file in files:
                if file.endswith(".java"):
                    filepath = os.path.join(root, file)
                    try:
                        with open(filepath, 'r', encoding='utf-8') as f:
                            content = f.read()
                            
                            if "java.lang.reflect" in content:
                                findings["reflection"].append(filepath)
                            if "Runtime.getRuntime().exec" in content:
                                findings["runtime_exec"].append(filepath)
                            if "ProcessBuilder" in content:
                                findings["process_builder"].append(filepath)
                            if "DexClassLoader" in content:
                                findings["dex_class_loader"].append(filepath)
                            if "AccessibilityService" in content:
                                findings["accessibility_service"].append(filepath)
                            if "addJavascriptInterface" in content:
                                findings["add_javascript_interface"].append(filepath)
                            if "javax.crypto.Cipher" in content:
                                findings["crypto_cipher"].append(filepath)
                    except Exception as e:
                        logger.warning(f"Failed to read {filepath}: {e}")
                        
        return findings
