import logging
from typing import Dict, Any, List
try:
    from androguard.core.apk import APK
except ImportError:
    APK = None

logger = logging.getLogger(__name__)

class AndroguardAnalyzer:
    def analyze(self, apk_path: str) -> Dict[str, Any]:
        logger.info(f"Running Androguard on {apk_path}")
        if APK is None:
            logger.error("Androguard is not installed.")
            return {"status": "error", "error": "androguard not installed"}
            
        try:
            apk = APK(apk_path)
            
            permissions = apk.get_permissions()
            activities = apk.get_activities()
            services = apk.get_services()
            receivers = apk.get_receivers()
            providers = apk.get_providers()
            
            cert_info = []
            if apk.is_signed():
                for cert in apk.get_certificates():
                    cert_info.append({
                        "issuer": cert.issuer.human_friendly,
                        "subject": cert.subject.human_friendly,
                        "serial": cert.serial_number,
                        "sha1": cert.sha1.hex(),
                        "sha256": cert.sha256.hex()
                    })

            return {
                "status": "success",
                "package": apk.get_package(),
                "version_name": apk.get_androidversion_name(),
                "version_code": apk.get_androidversion_code(),
                "min_sdk": apk.get_min_sdk_version(),
                "target_sdk": apk.get_target_sdk_version(),
                "permissions": permissions,
                "activities": activities,
                "services": services,
                "receivers": receivers,
                "providers": providers,
                "certificates": cert_info,
                "is_signed": apk.is_signed(),
                "is_signed_v1": apk.is_signed_v1(),
                "is_signed_v2": apk.is_signed_v2(),
                "is_signed_v3": apk.is_signed_v3()
            }
        except Exception as e:
            logger.error(f"Androguard failed: {e}")
            return {
                "status": "error",
                "error": str(e)
            }
