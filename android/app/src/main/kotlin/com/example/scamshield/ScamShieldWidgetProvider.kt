package com.example.scamshield

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * Home-screen widget: one tap from "this message looks wrong" to a scan.
 *
 * The value here is entirely about the number of steps. Unlocking the phone,
 * finding the app, opening it, reaching the scan tab and pasting is five
 * actions at the exact moment someone is being rushed by a scammer — which is
 * the whole tactic. This makes it one.
 *
 * ── Where its content comes from ───────────────────────────────────────────
 * A widget has no Flutter engine and cannot run Dart. Rather than duplicating
 * the app's statistics logic in Kotlin (where it would inevitably drift), Dart
 * writes a single ready-to-render status line into shared preferences whenever
 * the numbers change, and this class only reads and displays it. The one piece
 * of logic that lives here is the fallback when nothing has been written yet.
 *
 * The widget is never updated on a timer: `updatePeriodMillis` is 0 in
 * scamshield_widget_info.xml, and refreshes are pushed by the app after a scan.
 * A tile whose text changes only after a scan has no reason to wake the device
 * every half hour.
 */
class ScamShieldWidgetProvider : AppWidgetProvider() {

    companion object {
        const val FLUTTER_PREFS = "FlutterSharedPreferences"

        /** Written by HomeWidgetService on the Dart side; see the note above. */
        const val KEY_STATUS = "flutter.scamshield_widget_status"

        /** Read by MainActivity to decide where to land the user. */
        const val EXTRA_ACTION = "scamshield_widget_action"
        const val ACTION_SCAN = "scan"

        /** Re-renders every placed instance. Called from the method channel
         * after Dart updates the status text. */
        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, ScamShieldWidgetProvider::class.java)
            )
            if (ids.isEmpty()) return
            for (id in ids) {
                manager.updateAppWidget(id, buildViews(context))
            }
        }

        private fun buildViews(context: Context): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.scamshield_widget)

            val prefs = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            val status = prefs.getString(KEY_STATUS, null)
                ?: context.getString(R.string.widget_status_default)
            views.setTextViewText(R.id.widget_status, status)

            val intent = Intent(context, MainActivity::class.java).apply {
                putExtra(EXTRA_ACTION, ACTION_SCAN)
                // singleTask in the manifest means an already-running app is
                // brought forward rather than restarted; CLEAR_TOP makes sure
                // the user lands on the main screen and not on whatever
                // sub-screen they happened to leave open days ago.
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pending = PendingIntent.getActivity(
                context,
                0,
                intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            // The whole tile is the target, not just the pill — a widget where
            // only part of the surface responds is a widget people think is
            // broken.
            views.setOnClickPendingIntent(R.id.widget_status, pending)
            views.setOnClickPendingIntent(R.id.widget_action, pending)
            return views
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(id, buildViews(context))
        }
    }
}
