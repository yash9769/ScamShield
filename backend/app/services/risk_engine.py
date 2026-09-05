import yaml
import os
import logging
from pathlib import Path
from typing import Dict, Any, List

logger = logging.getLogger(__name__)

_DEFAULT_CONFIG_PATH = str(Path(__file__).resolve().parent.parent / "config" / "risk_weights.yaml")

class RiskEngine:
    def __init__(self, config_path: str = _DEFAULT_CONFIG_PATH):
        self.weights = self._load_weights(config_path)

    def _load_weights(self, path: str) -> Dict[str, Any]:
        if not os.path.exists(path):
            logger.warning(f"Risk weights config not found at {path}. Using defaults.")
            return {"permissions": {}, "secrets": {}, "osint": {}, "certificate": {}, "thresholds": {"SAFE": 0, "LOW": 1, "MEDIUM": 30, "HIGH": 60, "CRITICAL": 80}}
        
        try:
            with open(path, 'r') as f:
                return yaml.safe_load(f)
        except Exception as e:
            logger.error(f"Failed to load risk weights: {e}")
            return {"permissions": {}, "secrets": {}, "osint": {}, "certificate": {}, "thresholds": {"SAFE": 0, "LOW": 1, "MEDIUM": 30, "HIGH": 60, "CRITICAL": 80}}

    def calculate_risk(self, analysis_data: Dict[str, Any]) -> Dict[str, Any]:
        score = 0
        details = []

        # 1. Permissions
        perm_weights = self.weights.get("permissions", {})
        permissions = analysis_data.get("androguard", {}).get("permissions", [])
        if not permissions:
            # Try to get from MobSF if Androguard failed
            permissions = list(analysis_data.get("mobsf", {}).get("report", {}).get("permissions", {}).keys())
            
        for perm in permissions:
            perm_name = perm.split(".")[-1]
            if perm_name in perm_weights:
                weight = perm_weights[perm_name]
                score += weight
                details.append(f"Dangerous permission: {perm_name} (+{weight})")

        # 2. Secrets
        sec_weights = self.weights.get("secrets", {})
        secrets_findings = analysis_data.get("secrets", {}).get("findings", {})
        for sec_type, findings in secrets_findings.items():
            if sec_type in sec_weights and findings:
                weight = sec_weights[sec_type]
                score += weight
                details.append(f"Hardcoded secret found: {sec_type} (+{weight})")

        # 3. OSINT
        osint_weights = self.weights.get("osint", {})
        vt_stats = analysis_data.get("osint", {}).get("virustotal", {})
        if vt_stats and vt_stats.get("status") != "not_found":
            malicious = vt_stats.get("malicious", 0)
            if malicious > 0:
                weight = osint_weights.get("malicious", 40)
                score += weight
                details.append(f"VirusTotal detected {malicious} malicious engines (+{weight})")
                
        # 4. YARA
        yara_matches = analysis_data.get("yara", {}).get("matches", [])
        for match in yara_matches:
            # Hardcode YARA match weight for now, or could add to YAML
            weight = 50 
            score += weight
            details.append(f"YARA rule matched: {match['rule']} (+{weight})")

        # Determine level
        thresholds = self.weights.get("thresholds", {})
        level = "SAFE"
        if score >= thresholds.get("CRITICAL", 80):
            level = "CRITICAL"
        elif score >= thresholds.get("HIGH", 60):
            level = "HIGH"
        elif score >= thresholds.get("MEDIUM", 30):
            level = "MEDIUM"
        elif score >= thresholds.get("LOW", 1):
            level = "LOW"

        return {
            "score": score,
            "level": level,
            "details": details
        }
