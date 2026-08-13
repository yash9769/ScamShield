import hashlib
import io
import logging
import re
import zipfile
from typing import Dict, Any, List
try:
    from androguard.core.apk import APK
except ImportError:
    APK = None

logger = logging.getLogger(__name__)

# Byte patterns (as latin-1 string substrings) for dangerous class/method
# references, matched against raw classes*.dex bytes. Scanning raw bytes keeps
# this fast and dependency-free while still catching obfuscation-agnostic
# framework API usage.
DEX_PATTERNS = {
    "accessibility_abuse": [
        "Landroid/accessibilityservice/AccessibilityService;",
        "AccessibilityNodeInfo",
        "performAction",
        "dispatchGesture",
    ],
    "sms_stealing": [
        "Landroid/telephony/SmsManager;",
        "Landroid/provider/Telephony$Sms;",
        "sms_text_fetched",
        "Landroid/content/BroadcastReceiver",
        "android.provider.Telephony.SMS_RECEIVED",
    ],
    "call_recording": [
        "MediaRecorder",
        "VOICE_CALL",
        "Landroid/telephony/TelephonyManager;",
        "getCallState",
        "ACCESS_ALL_CALL_RECORDING_PERMISSION",
    ],
    "dynamic_code_loading": [
        "Ldalvik/system/DexClassLoader;",
        "Ldalvik/system/PathClassLoader;",
        "Ldalvik/system/InMemoryDexClassLoader;",
        "Landroid/app/NativeActivity;",
        "System.loadLibrary",
    ],
    "rooting_hooks": [
        "Landroid/os/Runtime;",
        "su -c",
        "Lcom/topjohnwu/superuser/",
        "Magisk",
        "mount -o remount",
    ],
    "anti_analysis": [
        "Landroid/os/Debug;",
        "isDebuggerConnected",
        "Landroid/content/pm/PackageManager;",
        "getInstallerPackageName",
        "isRooted",
    ],
    "background_mic": [
        "MediaRecorder",
        "setAudioSource",
        "VOICE_RECOGNITION",
        "AudioRecord",
    ],
    "device_id_collection": [
        "Landroid/telephony/TelephonyManager;",
        "getDeviceId",
        "getImei",
        "getSubscriberId",
        "getSimSerialNumber",
    ],
    "credential_harvesting": [
        "Landroid/webkit/WebView;",
        "addJavascriptInterface",
        "Landroid/hardware/usb/UsbManager;",
        "KeyEvent",
        "setOnKeyListener",
    ],
    "remote_command": [
        "Landroid/os/Messenger;",
        "Landroid/accounts/AccountManager;",
        "java.lang.Process",
        "Runtime.getRuntime",
        "ProcessBuilder",
    ],
}

_DEX_FILE_RE = re.compile(r"^classes.*\.dex$")


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
                "is_signed_v3": apk.is_signed_v3(),
                "capability_indicators": self.detect_capability_indicators(apk_path),
                "dex_structural_fingerprint": self.compute_dex_fingerprint(apk_path),
            }
        except Exception as e:
            logger.error(f"Androguard failed: {e}")
            return {
                "status": "error",
                "error": str(e)
            }

    @staticmethod
    def detect_capability_indicators(apk_path: str) -> List[str]:
        """Scan classes*.dex entries for framework capability references.

        IMPORTANT: these are *potential capability indicators*, not proof of
        behavior. A string reference can exist yet never execute, legitimate
        apps use these APIs, and reflection/obfuscation can bypass direct
        references. Combine with permissions + manifest + behavioral context
        before making claims (see risk_engine).
        """
        found: List[str] = []
        try:
            with zipfile.ZipFile(apk_path) as zf:
                dex_names = [n for n in zf.namelist() if _DEX_FILE_RE.match(n)]
                for name in dex_names:
                    blob = zf.read(name)
                    # latin-1 keeps every byte addressable as a 1:1 char mapping
                    haystack = blob.decode("latin-1", errors="replace")
                    for api, patterns in DEX_PATTERNS.items():
                        if api in found:
                            continue
                        for pattern in patterns:
                            if pattern in haystack:
                                found.append(api)
                                break
                    if len(found) == len(DEX_PATTERNS):
                        break
        except Exception as e:
            logger.warning(f"Dangerous API scan failed: {e}")
        return found

    @staticmethod
    def compute_dex_fingerprint(apk_path: str) -> str:
        """
        DEX structural fingerprint: SHA-256 of dex entry names + their content,
        in zip order. This is an EXACT structural fingerprint, not fuzzy
        similarity — any significant dex change produces a different hash.
        Use it for exact re-sign / repackaging family matching; add TLSH +
        feature vectors for variant detection.
        """
        hasher = hashlib.sha256()
        try:
            with zipfile.ZipFile(apk_path) as zf:
                for name in zf.namelist():
                    if _DEX_FILE_RE.match(name):
                        hasher.update(name.encode("utf-8", "replace"))
                        hasher.update(zf.read(name))
        except Exception as e:
            logger.warning(f"Structural hash failed: {e}")
            return ""
        return hasher.hexdigest()
