import os
import logging
from typing import Dict, Any, List
try:
    import yara
except ImportError:
    yara = None

from app.core.config import get_settings

logger = logging.getLogger(__name__)

class YaraAnalyzer:
    def __init__(self, rules_dir: str = ""):
        settings = get_settings()
        self.rules_dir = rules_dir or settings.YARA_RULES_DIR
        self.rules = self._compile_rules()

    def _compile_rules(self):
        if yara is None:
            return None
        
        filepaths = {}
        if os.path.exists(self.rules_dir):
            for file in os.listdir(self.rules_dir):
                if file.endswith(".yar") or file.endswith(".yara"):
                    filepaths[file] = os.path.join(self.rules_dir, file)
        
        if not filepaths:
            logger.warning("No YARA rules found.")
            return None
            
        try:
            return yara.compile(filepaths=filepaths)
        except Exception as e:
            logger.error(f"Failed to compile YARA rules: {e}")
            return None

    def analyze(self, apk_path: str, extracted_dirs: List[str] = None) -> Dict[str, Any]:
        logger.info(f"Running YARA analysis on {apk_path}")
        if self.rules is None:
            return {"status": "error", "error": "YARA rules not compiled or yara-python not installed"}
            
        matches = []
        try:
            # Scan the APK file itself
            apk_matches = self.rules.match(apk_path)
            for match in apk_matches:
                matches.append({"rule": match.rule, "tags": match.tags, "meta": match.meta, "target": "APK"})
                
            # Optionally scan extracted files (from apktool/jadx)
            if extracted_dirs:
                for directory in extracted_dirs:
                    if os.path.exists(directory):
                        for root, _, files in os.walk(directory):
                            for file in files:
                                file_path = os.path.join(root, file)
                                try:
                                    file_matches = self.rules.match(file_path)
                                    for match in file_matches:
                                        matches.append({"rule": match.rule, "tags": match.tags, "meta": match.meta, "target": file_path})
                                except Exception:
                                    pass # Skip files that can't be read

            # Deduplicate matches by rule name
            unique_matches = []
            seen_rules = set()
            for m in matches:
                if m["rule"] not in seen_rules:
                    seen_rules.add(m["rule"])
                    unique_matches.append(m)

            return {
                "status": "success",
                "matches": unique_matches,
                "match_count": len(unique_matches)
            }
        except Exception as e:
            logger.error(f"YARA analysis failed: {e}")
            return {
                "status": "error",
                "error": str(e)
            }
