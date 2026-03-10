package com.example.notitia

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import android.widget.RemoteViews

/**
 * NOTITIA — Widget Provider LARGE (3×3)
 *
 * Même fonctionnement que NotitiaWidgetProvider (2×2) mais avec un layout
 * plus grand qui affiche aussi la transcription en temps réel.
 *
 * Les deux widgets partagent le même NotitiaRecordingService et les mêmes
 * SharedPreferences — ils sont toujours synchronisés.
 */
class NotitiaWidgetLargeProvider : AppWidgetProvider() {

    companion object {
        const val TAG = "NotitiaWidgetLarge"
        const val ACTION_TOGGLE_LARGE = "com.example.notitia.action.WIDGET_TOGGLE_LARGE"
        private const val PREFS_NAME = "HomeWidgetPreferences"
    }

    // =========================================================================
    // onUpdate
    // =========================================================================
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (id in appWidgetIds) {
            renderWidget(context, appWidgetManager, id)
        }
    }

    // =========================================================================
    // onReceive — broadcast TOGGLE
    // =========================================================================
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)

        when (intent.action) {
            ACTION_TOGGLE_LARGE -> {
                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                val isRecording = prefs.getBoolean("is_recording", false)

                Log.d(TAG, "Toggle LARGE reçu — recording=$isRecording")

                val serviceIntent = Intent(context, NotitiaRecordingService::class.java).apply {
                    action = if (isRecording) {
                        NotitiaRecordingService.ACTION_STOP
                    } else {
                        NotitiaRecordingService.ACTION_START
                    }
                }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(serviceIntent)
                } else {
                    context.startService(serviceIntent)
                }
            }

            AppWidgetManager.ACTION_APPWIDGET_UPDATE -> {
                val mgr = AppWidgetManager.getInstance(context)
                val ids = intent.getIntArrayExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS)
                    ?: mgr.getAppWidgetIds(
                        ComponentName(context, NotitiaWidgetLargeProvider::class.java)
                    )
                for (id in ids) {
                    renderWidget(context, mgr, id)
                }
            }
        }
    }

    // =========================================================================
    // Rendu du widget large (idle / recording + transcription)
    // =========================================================================
    private fun renderWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int
    ) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val isRecording = prefs.getBoolean("is_recording", false)
        val timer = prefs.getString("timer", "00:00") ?: "00:00"
        val transcript = prefs.getString("live_transcript", "") ?: ""
        val lastTranscript = prefs.getString("last_transcription", "") ?: ""

        val togglePending = createTogglePendingIntent(context)

        val views: RemoteViews = if (isRecording) {
            RemoteViews(context.packageName, R.layout.widget_large_layout_recording).apply {
                setTextViewText(R.id.widget_timer, timer)
                // Afficher le transcript live (ou placeholder)
                val displayText = if (transcript.isNotEmpty()) {
                    // Tronquer à ~120 chars pour le widget
                    if (transcript.length > 120) "…${transcript.takeLast(120)}" else transcript
                } else {
                    "En attente de transcription…"
                }
                setTextViewText(R.id.widget_transcript, displayText)
                setOnClickPendingIntent(R.id.widget_stop_button, togglePending)
                setOnClickPendingIntent(R.id.widget_glow_ring_rec, togglePending)
            }
        } else {
            RemoteViews(context.packageName, R.layout.widget_large_layout).apply {
                // Afficher la dernière transcription si dispo
                val displayText = if (lastTranscript.isNotEmpty()) {
                    "\"$lastTranscript\""
                } else {
                    "Dernière transcription apparaîtra ici"
                }
                setTextViewText(R.id.widget_transcript, displayText)
                setOnClickPendingIntent(R.id.widget_mic_button, togglePending)
                setOnClickPendingIntent(R.id.widget_glow_ring, togglePending)
            }
        }

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    private fun createTogglePendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, NotitiaWidgetLargeProvider::class.java).apply {
            action = ACTION_TOGGLE_LARGE
        }
        return PendingIntent.getBroadcast(
            context,
            43, // request code différent du petit widget (42)
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}
