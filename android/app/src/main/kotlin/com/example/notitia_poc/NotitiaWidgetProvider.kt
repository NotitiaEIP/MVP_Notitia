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
 * NOTITIA — Widget Provider (Écran d'accueil Android)
 *
 * Widget à double état qui fonctionne SANS ouvrir l'application Flutter :
 *
 *   IDLE      → Bouton micro néon rose. Tap = envoie un broadcast
 *               qui démarre NotitiaRecordingService (foreground service natif).
 *
 *   RECORDING → Timer cyan + bouton stop rouge. Tap = envoie un broadcast
 *               qui arrête le service → sauvegarde le transcript.
 *
 * Aucune Activity n'est lancée. Le widget communique uniquement via
 * des broadcasts et un Service Foreground Android natif.
 */
class NotitiaWidgetProvider : AppWidgetProvider() {

    companion object {
        const val TAG = "NotitiaWidget"
        const val ACTION_TOGGLE = "com.example.notitia.action.WIDGET_TOGGLE"
        private const val PREFS_NAME = "HomeWidgetPreferences"
    }

    // =========================================================================
    // onUpdate — Rafraîchir le visuel du widget
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
    // onReceive — Gère le broadcast TOGGLE (clic utilisateur)
    // =========================================================================
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)

        when (intent.action) {
            ACTION_TOGGLE -> {
                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                val isRecording = prefs.getBoolean("is_recording", false)

                Log.d(TAG, "Toggle reçu — actuellement recording=$isRecording")

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

            // Le service envoie ACTION_APPWIDGET_UPDATE pour rafraîchir le visuel
            AppWidgetManager.ACTION_APPWIDGET_UPDATE -> {
                val mgr = AppWidgetManager.getInstance(context)
                val ids = intent.getIntArrayExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS)
                    ?: mgr.getAppWidgetIds(
                        ComponentName(context, NotitiaWidgetProvider::class.java)
                    )
                for (id in ids) {
                    renderWidget(context, mgr, id)
                }
            }
        }
    }

    // =========================================================================
    // Rendu du widget (choix du layout idle/recording)
    // =========================================================================
    private fun renderWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int
    ) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val isRecording = prefs.getBoolean("is_recording", false)
        val timer = prefs.getString("timer", "00:00") ?: "00:00"

        val togglePending = createTogglePendingIntent(context)

        val views: RemoteViews = if (isRecording) {
            // === ÉTAT RECORDING ===
            RemoteViews(context.packageName, R.layout.widget_layout_recording).apply {
                setTextViewText(R.id.widget_timer, timer)
                setOnClickPendingIntent(R.id.widget_stop_button, togglePending)
                setOnClickPendingIntent(R.id.widget_glow_ring_rec, togglePending)
            }
        } else {
            // === ÉTAT IDLE ===
            RemoteViews(context.packageName, R.layout.widget_layout).apply {
                setOnClickPendingIntent(R.id.widget_mic_button, togglePending)
                setOnClickPendingIntent(R.id.widget_glow_ring, togglePending)
            }
        }

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    /**
     * Crée un PendingIntent broadcast (PAS une Activity !)
     * qui revient dans onReceive() avec ACTION_TOGGLE.
     */
    private fun createTogglePendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, NotitiaWidgetProvider::class.java).apply {
            action = ACTION_TOGGLE
        }
        return PendingIntent.getBroadcast(
            context,
            42, // request code fixe
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}
