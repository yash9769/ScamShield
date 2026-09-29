package com.example.scamshield

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import org.json.JSONArray
import org.json.JSONObject

/**
 * Receives incoming SMS so ScamShield can screen it for scam content.
 *
 * Two delivery paths, because an SMS does not wait for the app to be open:
 *
 *  - App alive: the message goes straight to the Dart side over the event
 *    sink in [SmsScreeningBridge], and is screened immediately.
 *  - App not running: Android still starts this receiver, but there is no
 *    Flutter engine to hand the message to. It is queued in app-private
 *    storage and drained by Dart on next launch.
 *
 * The queue is capped and cleared once drained. It holds message bodies, which
 * is the same class of data the app's existing scan history already stores in
 * its local SQLite database — app-private, never transmitted by this receiver.
 *
 * Screening itself deliberately stays in Dart: the detection engine, the user's
 * consent state and the "AI analysis disabled" privacy setting all live there,
 * and duplicating any of that in Kotlin would let the two drift apart.
 */
class SmsScreeningReceiver : BroadcastReceiver() {

    companion object {
        const val PREFS = "scamshield_sms_queue"
        const val KEY_PENDING = "pending"

        /** Bounded so a burst (or an abusive sender) can't grow without limit. */
        const val MAX_QUEUED = 20
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        // A long SMS arrives split across multiple PDUs; concatenating them is
        // what makes the difference between screening a whole scam message and
        // screening its first 160 characters.
        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        if (messages.isEmpty()) return

        val sender = messages[0].originatingAddress ?: "unknown"
        val body = StringBuilder()
        for (message in messages) {
            body.append(message.messageBody ?: "")
        }
        val text = body.toString()
        if (text.isBlank()) return

        val payload = mapOf(
            "sender" to sender,
            "body" to text,
            "timestamp" to System.currentTimeMillis(),
        )

        if (!SmsScreeningBridge.deliver(payload)) {
            queue(context, payload)
        }
    }

    /** Persists a message for the next app launch when no engine is listening. */
    private fun queue(context: Context, payload: Map<String, Any>) {
        try {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val existing = JSONArray(prefs.getString(KEY_PENDING, "[]"))

            val entry = JSONObject()
            entry.put("sender", payload["sender"])
            entry.put("body", payload["body"])
            entry.put("timestamp", payload["timestamp"])
            existing.put(entry)

            // Keep the newest MAX_QUEUED entries.
            val trimmed = JSONArray()
            val start = maxOf(0, existing.length() - MAX_QUEUED)
            for (i in start until existing.length()) {
                trimmed.put(existing.get(i))
            }
            prefs.edit().putString(KEY_PENDING, trimmed.toString()).apply()
        } catch (e: Exception) {
            // A failure to queue must never crash the receiver — the user's
            // messaging app is not ScamShield's to break.
            android.util.Log.w("ScamShield", "Failed to queue SMS for screening", e)
        }
    }
}
