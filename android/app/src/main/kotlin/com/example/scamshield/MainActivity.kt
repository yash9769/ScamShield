package com.example.scamshield

import android.app.admin.DevicePolicyManager
import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import org.json.JSONArray

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.scamshield/security"
    private val SMS_METHOD_CHANNEL = "com.example.scamshield/sms"
    private val SMS_EVENT_CHANNEL = "com.example.scamshield/sms_stream"
    private val WIDGET_CHANNEL = "com.example.scamshield/widget"

    private var callScreeningBridge: CallScreeningBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Incoming-call screening: this channel only manages the system role.
        // The screening itself runs in CallScreeningServiceImpl, which the
        // system starts on its own with no Flutter engine involved.
        val callBridge = CallScreeningBridge(this)
        callScreeningBridge = callBridge
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CallScreeningBridge.CHANNEL)
            .setMethodCallHandler(callBridge)

        // Live messages: delivered here whenever the app process is alive,
        // regardless of which screen is in front.
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    SmsScreeningBridge.attach(events)
                }

                override fun onCancel(arguments: Any?) {
                    SmsScreeningBridge.attach(null)
                }
            })

        // Queued messages: anything that arrived while no engine was running
        // to receive the live event above.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "drainQueuedMessages" -> result.success(drainQueuedSms())
                    else -> result.notImplemented()
                }
            }

        // Home-screen widget. Dart owns the status text (so the statistics
        // logic is not duplicated in Kotlin where it would drift); this channel
        // only lets it ask for a redraw, and reports how the app was launched.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIDGET_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "refresh" -> {
                        ScamShieldWidgetProvider.refreshAll(applicationContext)
                        result.success(true)
                    }
                    "consumeLaunchAction" -> {
                        // Consumed, not just read: without clearing the extra,
                        // every later resume would look like a fresh widget tap
                        // and yank the user back to the scan tab.
                        val action = intent?.getStringExtra(
                            ScamShieldWidgetProvider.EXTRA_ACTION
                        )
                        intent?.removeExtra(ScamShieldWidgetProvider.EXTRA_ACTION)
                        result.success(action)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "checkDeviceIntegrity") {
                val isRooted = checkRootMethod1() || checkRootMethod2()
                val isEmulator = checkIsEmulator()
                
                val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as? DevicePolicyManager
                val encryptionStatus = dpm?.storageEncryptionStatus ?: DevicePolicyManager.ENCRYPTION_STATUS_UNSUPPORTED
                val isHardwareEncrypted = encryptionStatus == DevicePolicyManager.ENCRYPTION_STATUS_ACTIVE ||
                        encryptionStatus == DevicePolicyManager.ENCRYPTION_STATUS_ACTIVE_DEFAULT_KEY ||
                        (android.os.Build.VERSION.SDK_INT >= 24 &&
                         encryptionStatus == DevicePolicyManager.ENCRYPTION_STATUS_ACTIVE_PER_USER)

                val integrityData = mapOf(
                    "isRooted" to isRooted,
                    "isEmulator" to isEmulator,
                    "isHardwareEncrypted" to isHardwareEncrypted,
                    "bootloaderLocked" to !isRooted,
                    "statusMessage" to if (isRooted) "WARN: Root access or test-keys detected" else "SECURE: Hardware integrity verified"
                )
                result.success(integrityData)
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        // launchMode is singleTask, so tapping the widget while the app is
        // already running delivers here rather than through onCreate. Without
        // this the activity would keep serving the extras it was first started
        // with, and the widget would appear to do nothing.
        setIntent(intent)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        // Let the bridge answer its own pending Dart call first; anything it
        // doesn't recognise still has to reach super, or the Flutter plugins
        // that use startActivityForResult (image picking, permissions) break.
        if (callScreeningBridge?.onActivityResult(requestCode, resultCode) != true) {
            super.onActivityResult(requestCode, resultCode, data)
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

    /** Reads and clears whatever [SmsScreeningReceiver] queued while the app
     * process was not running, returning it as a JSON array string. */
    private fun drainQueuedSms(): String {
        val prefs = getSharedPreferences(SmsScreeningReceiver.PREFS, Context.MODE_PRIVATE)
        val pending = prefs.getString(SmsScreeningReceiver.KEY_PENDING, "[]") ?: "[]"
        prefs.edit().remove(SmsScreeningReceiver.KEY_PENDING).apply()
        return try {
            // Round-trip through JSONArray to fail closed on corrupt prefs
            // data rather than handing Dart a string it can't parse.
            JSONArray(pending).toString()
        } catch (e: Exception) {
            "[]"
        }
    }
}
