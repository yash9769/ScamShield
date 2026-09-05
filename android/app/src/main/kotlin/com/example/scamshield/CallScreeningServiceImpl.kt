package com.example.scamshield

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.telecom.Call
import android.telecom.CallScreeningService
import java.net.HttpURLConnection
import java.net.URL
import org.json.JSONObject

/**
 * Screens incoming calls against numbers ScamShield already knows are bad.
 *
 * ── Why this never rejects a call ────────────────────────────────────────────
 * It would be trivial to call [CallResponse.Builder.setDisallowCall] here, and
 * it would be the wrong thing to do. The cost of the two possible mistakes is
 * nowhere near symmetric: a missed warning means the user answers a call they
 * were going to answer anyway and still has every other defence in this app,
 * while a wrongly-blocked call can be a hospital, a bank's genuine fraud desk,
 * or a relative on an unknown phone. So the default response is *allow*, and
 * the protection is a heads-up notification the user sees while it is still
 * ringing.
 *
 * Silencing the ringer is offered as a separate, explicitly opt-in setting, and
 * even then only for numbers on the local list — never on a network verdict.
 *
 * ── Why the matching logic is here and not in Dart ───────────────────────────
 * Unlike SMS screening, this cannot defer to Dart: the system gives a screening
 * service a few seconds to respond and there may be no Flutter engine running
 * at all. So Dart owns the *data* (it maintains the local list and writes it to
 * shared preferences) and Kotlin owns only the lookup, which is a set
 * membership test on a normalized number.
 *
 * ── Availability ─────────────────────────────────────────────────────────────
 * Requires Android 10 (API 29) — that is when ROLE_CALL_SCREENING arrived.
 * Before it, the only way to screen calls was to replace the user's dialer,
 * which is far too much to ask for this feature.
 */
class CallScreeningServiceImpl : CallScreeningService() {

    companion object {
        // Flutter's shared_preferences writes into this file and prefixes every
        // key with "flutter.".
        const val FLUTTER_PREFS = "FlutterSharedPreferences"
        const val KEY_ENABLED = "flutter.scamshield_call_screening_enabled"
        const val KEY_BLOCKLIST = "flutter.scamshield_call_blocklist"
        const val KEY_SILENCE = "flutter.scamshield_call_silence_known"
        const val KEY_ONLINE_LOOKUP = "flutter.scamshield_call_online_lookup"
        const val KEY_API_BASE = "flutter.scamshield_api_base_url"

        const val CHANNEL_ID = "scamshield_call_alerts"

        /** Reports needed before the server's community data is treated as a
         * verdict. Mirrors REPORT_THRESHOLD_FOR_SIGNAL on the server, which
         * exists so a handful of malicious reports can't tar a real number. */
        const val REPORT_THRESHOLD = 3

        /** Well inside the system's screening budget, with room to respond. */
        const val LOOKUP_TIMEOUT_MS = 2500

        /**
         * Reduces a number to the form the rest of ScamShield stores.
         *
         * Indian numbers reach the device as +919876543210, 09876543210 or
         * 9876543210 depending on who dialled and from where; without this the
         * same scammer would miss the list on two of those three. Matches
         * _normalize_indicator() in server/main.py.
         */
        fun normalize(raw: String?): String {
            val digits = (raw ?: "").filter { it.isDigit() }
            return when {
                digits.length == 12 && digits.startsWith("91") -> digits.substring(2)
                digits.length == 11 && digits.startsWith("0") -> digits.substring(1)
                else -> digits
            }
        }
    }

    override fun onScreenCall(callDetails: Call.Details) {
        // The role that gets this service bound only exists on API 29+, so in
        // practice this is always true. Checked anyway because every API used
        // below it is 29+, and a service that throws instead of responding
        // leaves the user's call hanging.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            respondAllowing(callDetails, silence = false)
            return
        }

        // Only incoming calls are ours to judge; the user dialling a scam
        // number themselves is a different problem with a different answer.
        if (callDetails.callDirection != Call.Details.DIRECTION_INCOMING) {
            respondAllowing(callDetails, silence = false)
            return
        }

        val prefs = getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(KEY_ENABLED, false)) {
            respondAllowing(callDetails, silence = false)
            return
        }

        val number = normalize(callDetails.handle?.schemeSpecificPart)
        if (number.isEmpty()) {
            // A withheld/unknown number can't be looked up. Saying nothing is
            // better than warning about every private caller.
            respondAllowing(callDetails, silence = false)
            return
        }

        val onLocalList = blocklist(prefs).contains(number)

        // Respond before anything slow happens. Because a community verdict
        // never changes the response — it can add a warning but never silences
        // or blocks — the answer is fully determined by the local list, so the
        // call is never held up waiting on a network round trip.
        val silence = onLocalList && prefs.getBoolean(KEY_SILENCE, false)
        respondAllowing(callDetails, silence = silence)

        if (onLocalList) {
            warn(applicationContext, number, onLocalList = true, reports = 0, silenced = silence)
            return
        }

        if (!prefs.getBoolean(KEY_ONLINE_LOOKUP, false)) return

        // Opt-in only: this sends the calling number to ScamShield's reputation
        // API, which is a real disclosure and must be the user's choice rather
        // than a default.
        //
        // On its own thread for two reasons: network on the main thread throws
        // outright, and this service can be unbound the moment it has
        // responded. The notification is posted through the application
        // context so it still lands if that happens while the call is ringing.
        val context = applicationContext
        val apiBase = prefs.getString(KEY_API_BASE, "") ?: ""
        Thread {
            val reports = communityReportCount(apiBase, number)
            if (reports >= REPORT_THRESHOLD) {
                warn(context, number, onLocalList = false, reports = reports, silenced = false)
            }
        }.start()
    }

    private fun respondAllowing(callDetails: Call.Details, silence: Boolean) {
        // A screening service MUST respond, or the call is left hanging. Every
        // path through onScreenCall ends here.
        val builder = CallResponse.Builder()
            .setDisallowCall(false)
            .setRejectCall(false)
            .setSkipCallLog(false)
            .setSkipNotification(false)
        // setSilenceCall arrived with the role API in Android 10.
        if (silence && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setSilenceCall(true)
        }
        respondToCall(callDetails, builder.build())
    }

    /**
     * Asks the reputation API how many times this number has been reported.
     * Returns 0 on any failure — an unreachable server must never turn into a
     * warning about a number we know nothing about.
     */
    private fun communityReportCount(apiBase: String, number: String): Int {
        if (apiBase.isBlank()) return 0
        return try {
            val url = URL("${apiBase.trimEnd('/')}/reputation/phone/$number")
            val conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = LOOKUP_TIMEOUT_MS
                readTimeout = LOOKUP_TIMEOUT_MS
            }
            try {
                if (conn.responseCode != 200) return 0
                val body = conn.inputStream.bufferedReader().use { it.readText() }
                JSONObject(body).optInt("report_count", 0)
            } finally {
                conn.disconnect()
            }
        } catch (e: Exception) {
            android.util.Log.w("ScamShield", "Call reputation lookup failed", e)
            0
        }
    }

    /** The set of numbers Dart has written out, as a JSON array of strings. */
    private fun blocklist(prefs: android.content.SharedPreferences): Set<String> {
        return try {
            val raw = prefs.getString(KEY_BLOCKLIST, "[]") ?: "[]"
            val array = org.json.JSONArray(raw)
            (0 until array.length()).mapNotNull { normalize(array.optString(it)).ifEmpty { null } }.toSet()
        } catch (e: Exception) {
            emptySet()
        }
    }

    private fun warn(
        context: Context,
        number: String,
        onLocalList: Boolean,
        reports: Int,
        silenced: Boolean,
    ) {
        // Notification channels are API 26+; unreachable below 29 in practice,
        // but the compiler only knows this module's minSdk of 24.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Scam Call Alerts",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Warns while a call from a known scam number is ringing."
            }
        )

        val detail = when {
            onLocalList && silenced -> "Ringer silenced. This number is on your scam list."
            onLocalList -> "This number is on your scam list."
            else -> "Reported as a scam by $reports people."
        }

        val open = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        val notification = Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_warning)
            .setContentTitle("Likely scam call: $number")
            .setContentText(detail)
            .setCategory(Notification.CATEGORY_CALL)
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()

        // Keyed on the number so a repeat call from the same scammer replaces
        // its own warning instead of stacking a new one every ring.
        manager.notify(number.hashCode(), notification)
    }
}
