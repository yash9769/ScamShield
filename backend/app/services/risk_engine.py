import yaml
import os
import logging
from typing import Dict, Any, List

from app.core.config import get_settings

logger = logging.getLogger(__name__)

DEFAULT_WEIGHTS = {
    "permissions": {},
    "secrets": {},
    "osint": {},
    "certificate": {},
    "thresholds": {"SAFE": 0, "LOW": 1, "MEDIUM": 30, "HIGH": 60, "CRITICAL": 80},
}


def _default_config_path() -> str:
    """Resolve the risk-weights file without assuming a fixed /app path.

    Precedence:
    1. RISK_WEIGHTS_PATH setting (explicit operator override)
    2. Package-local config dir (works for local dev + Docker when the app dir
       is copied into the image)
    """
    settings = get_settings()
    if settings.RISK_WEIGHTS_PATH:
        return settings.RISK_WEIGHTS_PATH
    package_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    candidate = os.path.join(package_dir, "config", "risk_weights.yaml")
    if os.path.exists(candidate):
        return candidate
    return os.path.join(os.getcwd(), "app", "config", "risk_weights.yaml")


class RiskEngine:
    def __init__(self, config_path: str = ""):
        self.weights = self._load_weights(config_path or _default_config_path())

    def _load_weights(self, path: str) -> Dict[str, Any]:
        if not os.path.exists(path):
            logger.warning("Risk weights config not found at %s. Using defaults.", path)
            return dict(DEFAULT_WEIGHTS)

        try:
            with open(path, 'r') as f:
                loaded = yaml.safe_load(f) or {}
            for key, default in DEFAULT_WEIGHTS.items():
                loaded.setdefault(key, default)
            return loaded
        except Exception as e:
            logger.error("Failed to load risk weights: %s", e)
            return dict(DEFAULT_WEIGHTS)

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
        yara_weight = self.weights.get("yara", {}).get("match", 50)
        for match in yara_matches:
            score += yara_weight
            details.append(f"YARA rule matched: {match['rule']} (+{yara_weight})")

        # 5. Certificate
        cert_weights = self.weights.get("certificate", {})
        certs = analysis_data.get("androguard", {}).get("certificates", []) or []
        debug_cert = False
        for cert in certs:
            subject = str(cert.get("subject", ""))
            issuer = str(cert.get("issuer", ""))
            if "androiddebugkey" in subject.lower() or "androiddebugkey" in issuer.lower():
                debug_cert = True
                break
        if debug_cert:
            weight = cert_weights.get("debug", 10)
            score += weight
            details.append(f"Debug-signed certificate detected (+{weight})")

        signing = analysis_data.get("androguard", {})
        if (
            signing.get("is_signed") is True
            and signing.get("is_signed_v1") is True
            and not (signing.get("is_signed_v2") or signing.get("is_signed_v3"))
        ):
            weight = cert_weights.get("v1_only", 5)
            score += weight
            details.append(f"APK uses legacy v1-only signing scheme (+{weight})")

        # 6. Potential capability indicators (structural feature fingerprint).
        # Terminology matters: a string reference inside DEX bytes is an
        # indicator that a capability *may* exist — not proof it executes.
        api_weights = self.weights.get("dangerous_apis", {})
        indicators = analysis_data.get("androguard", {}).get("capability_indicators", []) or []
        # Backward-compat: read the old key too if present.
        if not indicators:
            indicators = analysis_data.get("androguard", {}).get("dangerous_apis", []) or []
        for api in indicators:
            weight = api_weights.get(api, 15)
            score += weight
            details.append(f"Potential capability indicator: {api} (+{weight})")

        # Clamp to the documented 0-100 scale. The score is a sum of weighted
        # evidence, not a probability, so it must never exceed the UI's scale.
        score = max(0, min(100, score))

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
            # "level" is the canonical key; "severity" is provided as an alias
            # for any consumer that uses the DB column name directly.
            "level": level,
            "severity": level,
            "details": details,
        }
