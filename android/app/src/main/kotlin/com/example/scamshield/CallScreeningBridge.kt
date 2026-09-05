package com.example.scamshield

import android.app.Activity
import android.app.role.RoleManager
import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges the call-screening *role* between Dart and Android.
 *
 * Screening incoming calls is not something an app can simply switch on. The
 * user has to hand it the ROLE_CALL_SCREENING role through a system dialog, and
 * only one app on the device can hold it at a time — so ScamShield has to ask,
 * accept "no" gracefully, and re-check every time, because the role can be
 * taken away by the user or claimed by another app at any point.
 *
 * The role API landed in Android 10 (API 29). Below that the only route was to
 * become the default dialer, which is a far bigger ask than this feature
 * justifies, so the feature reports itself unsupported there instead.
 */
class CallScreeningBridge(private val activity: Activity) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.example.scamshield/call_screening"
        const val REQUEST_CODE = 8731
    }

    /** Held across the system dialog so the Dart caller gets one answer back. */
    private var pendingResult: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(isSupported())
            "hasRole" -> result.success(hasRole())
            "requestRole" -> requestRole(result)
            "openRoleSettings" -> {
                // Revoking is only possible from system settings — an app cannot
                // drop a role it holds, so "turn this off" has to send the user
                // there rather than pretending to do it here.
                activity.startActivity(
                    Intent(android.provider.Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS)
                )
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun isSupported(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        val roleManager = activity.getSystemService(Context.ROLE_SERVICE) as? RoleManager
        return roleManager?.isRoleAvailable(RoleManager.ROLE_CALL_SCREENING) == true
    }

    private fun hasRole(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        val roleManager = activity.getSystemService(Context.ROLE_SERVICE) as? RoleManager
        return roleManager?.isRoleHeld(RoleManager.ROLE_CALL_SCREENING) == true
    }

    private fun requestRole(result: MethodChannel.Result) {
        if (!isSupported()) {
            result.success(false)
            return
        }
        if (hasRole()) {
            result.success(true)
            return
        }
        // A second dialog while one is already open would strand the first
        // caller's result, which Flutter treats as a hung Future.
        if (pendingResult != null) {
            result.success(false)
            return
        }

        val roleManager = activity.getSystemService(Context.ROLE_SERVICE) as? RoleManager
        if (roleManager == null) {
            result.success(false)
            return
        }
        pendingResult = result
        try {
            activity.startActivityForResult(
                roleManager.createRequestRoleIntent(RoleManager.ROLE_CALL_SCREENING),
                REQUEST_CODE,
            )
        } catch (e: Exception) {
            pendingResult = null
            result.success(false)
        }
    }

    /** Returns true if this bridge consumed the result. */
    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val result = pendingResult ?: return true
        pendingResult = null
        // Trust the role state over the result code: the user can grant the
        // role and then back out of the settings screen, and the reverse.
        result.success(resultCode == Activity.RESULT_OK || hasRole())
        return true
    }
}
