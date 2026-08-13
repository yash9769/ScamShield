package com.example.scamshield

import android.app.admin.DevicePolicyManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.scamshield/security"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkDeviceIntegrity" -> {
                    val isRooted = checkRootMethod1() || checkRootMethod2()
                    val isEmulator = checkIsEmulator()

                    val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as? DevicePolicyManager
                    val encryptionStatus = dpm?.storageEncryptionStatus ?: DevicePolicyManager.ENCRYPTION_STATUS_UNSUPPORTED
                    val isHardwareEncrypted = encryptionStatus == DevicePolicyManager.ENCRYPTION_STATUS_ACTIVE ||
                            encryptionStatus == DevicePolicyManager.ENCRYPTION_STATUS_ACTIVE_DEFAULT_KEY ||
                            (Build.VERSION.SDK_INT >= 24 &&
                             encryptionStatus == DevicePolicyManager.ENCRYPTION_STATUS_ACTIVE_PER_USER)

                    // Unknown sources: on Android 8+ each installer has its own setting.
                    // We approximate by reading the global INSTALL_NON_MARKET_APPS setting
                    // (still populated on many ROMs) as a best-effort signal.
                    @Suppress("DEPRECATION")
                    val unknownSources = try {
                        android.provider.Settings.Secure.getInt(
                            contentResolver,
                            android.provider.Settings.Secure.INSTALL_NON_MARKET_APPS, 0
                        ) == 1
                    } catch (_: Exception) { false }

                    // Bootloader: test-keys build or explicit UNLOCKED fingerprint
                    val bootloaderUnlocked = Build.TAGS?.contains("test-keys") == true ||
                            Build.FINGERPRINT?.contains("unlocked") == true

                    val integrityData = mapOf(
                        "isRooted" to isRooted,
                        "isEmulator" to isEmulator,
                        "isHardwareEncrypted" to isHardwareEncrypted,
                        "unknownSourcesEnabled" to unknownSources,
                        "bootloaderUnlocked" to bootloaderUnlocked,
                        "statusMessage" to if (isRooted) "WARN: Root access or test-keys detected" else "SECURE: Hardware integrity verified"
                    )
                    result.success(integrityData)
                }
                "getDeviceSecurityInfo" -> {
                    val deviceInfo = mapOf(
                        "manufacturer" to Build.MANUFACTURER,
                        "model" to Build.MODEL,
                        "osVersion" to Build.VERSION.RELEASE,
                        "sdkInt" to Build.VERSION.SDK_INT,
                        "securityPatch" to Build.VERSION.SECURITY_PATCH,
                        "fingerprint" to Build.FINGERPRINT,
                        "hardware" to Build.HARDWARE,
                        "isRooted" to (checkRootMethod1() || checkRootMethod2()),
                        "isEmulator" to checkIsEmulator()
                    )
                    result.success(deviceInfo)
                }
                "openSystemUpdate" -> {
                    try {
                        // Direct ACTION_SYSTEM_UPDATE_SETTINGS (Android 5.1+)
                        val intent = Intent(Settings.ACTION_SYSTEM_UPDATE_SETTINGS)
                        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        startActivity(intent)
                        result.success(null)
                    } catch (e: Exception) {
                        try {
                            // Fallback: open main settings
                            val intent = Intent(Settings.ACTION_SETTINGS)
                            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            startActivity(intent)
                            result.success(null)
                        } catch (e2: Exception) {
                            result.error("UNAVAILABLE", "Could not open system update settings", null)
                        }
                    }
                }
                "openSecuritySettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_SECURITY_SETTINGS)
                        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        startActivity(intent)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("UNAVAILABLE", "Could not open security settings", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun checkRootMethod1(): Boolean {
        val buildTags = android.os.Build.TAGS
        return buildTags != null && buildTags.contains("test-keys")
    }

    private fun checkRootMethod2(): Boolean {
        val paths = arrayOf(
            "/system/app/Superuser.apk",
            "/sbin/su",
            "/system/bin/su",
            "/system/xbin/su",
            "/data/local/xbin/su",
            "/data/local/bin/su",
            "/system/sd/xbin/su",
            "/system/bin/failsafe/su",
            "/data/local/su"
        )
        for (path in paths) {
            if (File(path).exists()) return true
        }
        return false
    }

    private fun checkIsEmulator(): Boolean {
        return (android.os.Build.FINGERPRINT.startsWith("generic")
                || android.os.Build.FINGERPRINT.startsWith("unknown")
                || android.os.Build.MODEL.contains("google_sdk")
                || android.os.Build.MODEL.contains("Emulator")
                || android.os.Build.MODEL.contains("Android SDK built for x86")
                || android.os.Build.MANUFACTURER.contains("Genymotion")
                || android.os.Build.BRAND.startsWith("generic") && android.os.Build.DEVICE.startsWith("generic")
                || "google_sdk" == android.os.Build.PRODUCT)
    }
}
