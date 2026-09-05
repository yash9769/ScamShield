package com.example.scamshield

import io.flutter.plugin.common.EventChannel
import org.json.JSONObject

/**
 * Hands incoming-SMS payloads from [SmsScreeningReceiver] to the Dart side
 * while the Flutter engine is alive, over an [EventChannel].
 *
 * This is a process-wide singleton rather than an instance owned by
 * [MainActivity] because the broadcast receiver that produces messages and the
 * activity that hosts the Flutter engine are different Android components with
 * independent lifecycles — a plain object is the simplest thing that lets one
 * find the other.
 */
object SmsScreeningBridge {
    @Volatile
    private var sink: EventChannel.EventSink? = null

    fun attach(newSink: EventChannel.EventSink?) {
        sink = newSink
    }

    /** Returns true if an active Dart listener received the message. */
    fun deliver(payload: Map<String, Any>): Boolean {
        val currentSink = sink ?: return false
        val json = JSONObject()
        json.put("sender", payload["sender"])
        json.put("body", payload["body"])
        json.put("timestamp", payload["timestamp"])
        return try {
            currentSink.success(json.toString())
            true
        } catch (e: Exception) {
            // The sink can go stale between the null-check above and use here
            // (engine torn down mid-broadcast); queuing is the correct fallback,
            // not a crash.
            false
        }
    }
}
