package com.example.notitia

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import okio.ByteString.Companion.toByteString
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.TimeUnit

/**
 * NOTITIA — Service d'enregistrement natif (Foreground Service)
 *
 * Enregistre l'audio et stream vers Deepgram Nova-3 pour transcription
 * en temps réel, SANS ouvrir l'application Flutter.
 *
 * Déclenché par le widget écran d'accueil :
 *   ACTION_START → démarre l'enregistrement + notification persistante
 *   ACTION_STOP  → arrête, sauvegarde le transcript dans SharedPreferences
 *
 * Le widget lit l'état (is_recording, timer) dans SharedPreferences
 * et affiche le bon layout (idle / recording + timer).
 *
 * Au prochain lancement de l'app Flutter, le transcript en attente
 * est récupéré, corrigé par Mistral, et sauvegardé dans StorageService.
 */
class NotitiaRecordingService : Service() {

    companion object {
        const val TAG = "NotitiaRec"

        const val ACTION_START = "com.example.notitia.action.START_RECORDING"
        const val ACTION_STOP  = "com.example.notitia.action.STOP_RECORDING"

        const val CHANNEL_ID      = "notitia_widget_recording"
        const val NOTIFICATION_ID  = 1001
        const val PREFS_NAME       = "HomeWidgetPreferences"

        // Deepgram
        private const val DEEPGRAM_API_KEY = "f7a04f3710a4b823fc325c44cae2c39b52a007e7"
        private const val SAMPLE_RATE      = 16000
        private const val CHANNEL_CONFIG   = AudioFormat.CHANNEL_IN_MONO
        private const val AUDIO_FORMAT     = AudioFormat.ENCODING_PCM_16BIT
    }

    // =========================================================================
    // État
    // =========================================================================
    private var audioRecord: AudioRecord? = null
    private var webSocket: WebSocket? = null
    private var okHttpClient: OkHttpClient? = null
    private var recordingThread: Thread? = null
    private var isRecording = false

    private val transcript = StringBuilder()
    private var currentPartial = ""
    private var startTimeMillis: Long = 0

    private val handler = Handler(Looper.getMainLooper())
    private val timerRunnable = object : Runnable {
        override fun run() {
            if (isRecording) {
                updateTimer()
                handler.postDelayed(this, 1000)
            }
        }
    }

    // =========================================================================
    // Service lifecycle
    // =========================================================================

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startRecording()
            ACTION_STOP  -> stopRecording()
        }
        return START_STICKY
    }

    override fun onDestroy() {
        if (isRecording) {
            stopRecording()
        }
        super.onDestroy()
    }

    // =========================================================================
    // START recording
    // =========================================================================
    private fun startRecording() {
        if (isRecording) return

        // Vérifier permission micro
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED
        ) {
            Log.e(TAG, "Permission RECORD_AUDIO non accordée")
            updateWidgetState(false, "Perm. requise")
            stopSelf()
            return
        }

        Log.d(TAG, "Démarrage de l'enregistrement...")

        // Notification foreground
        val notification = buildNotification("00:00")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID, notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        isRecording = true
        startTimeMillis = System.currentTimeMillis()
        transcript.clear()
        currentPartial = ""

        // Mettre à jour le widget immédiatement
        updateWidgetState(true, "00:00")

        // Connecter Deepgram WebSocket
        connectDeepgram()

        // Démarrer le streaming audio
        startAudioStreaming()

        // Démarrer le timer (mise à jour chaque seconde)
        handler.postDelayed(timerRunnable, 1000)

        Log.d(TAG, "✅ Enregistrement démarré")
    }

    // =========================================================================
    // STOP recording + sauvegarde
    // =========================================================================
    private fun stopRecording() {
        if (!isRecording) {
            stopSelf()
            return
        }

        Log.d(TAG, "Arrêt de l'enregistrement...")
        isRecording = false

        // Arrêter le timer
        handler.removeCallbacks(timerRunnable)

        // Arrêter le streaming audio
        try {
            audioRecord?.stop()
            audioRecord?.release()
        } catch (e: Exception) {
            Log.e(TAG, "Erreur arrêt AudioRecord", e)
        }
        audioRecord = null
        recordingThread = null

        // Fermer le WebSocket
        try {
            webSocket?.close(1000, "Recording stopped")
        } catch (e: Exception) {
            Log.e(TAG, "Erreur fermeture WebSocket", e)
        }
        webSocket = null

        // Finaliser le transcript
        if (currentPartial.isNotEmpty()) {
            if (transcript.isNotEmpty()) transcript.append(" ")
            transcript.append(currentPartial)
            currentPartial = ""
        }

        val finalTranscript = transcript.toString().trim()
        Log.d(TAG, "Transcript final: $finalTranscript")

        // Sauvegarder le transcript en attente (Flutter le récupérera)
        if (finalTranscript.isNotEmpty()) {
            savePendingTranscription(finalTranscript)
        }

        // Repasser le widget en état idle
        updateWidgetState(false, "00:00")

        // Arrêter le foreground service
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()

        Log.d(TAG, "✅ Enregistrement arrêté et sauvegardé")
    }

    // =========================================================================
    // Deepgram WebSocket
    // =========================================================================
    private fun connectDeepgram() {
        val params = mapOf(
            "model" to "nova-3",
            "language" to "fr",
            "punctuate" to "true",
            "smart_format" to "true",
            "interim_results" to "true",
            "encoding" to "linear16",
            "sample_rate" to SAMPLE_RATE.toString(),
            "channels" to "1"
        )
        val query = params.entries.joinToString("&") { "${it.key}=${it.value}" }
        val url = "wss://api.deepgram.com/v1/listen?$query"

        okHttpClient = OkHttpClient.Builder()
            .readTimeout(0, TimeUnit.MILLISECONDS)   // pas de timeout sur WebSocket
            .writeTimeout(10, TimeUnit.SECONDS)
            .connectTimeout(10, TimeUnit.SECONDS)
            .build()

        val request = Request.Builder()
            .url(url)
            .header("Authorization", "Token $DEEPGRAM_API_KEY")
            .build()

        webSocket = okHttpClient!!.newWebSocket(request, deepgramListener)
        Log.d(TAG, "Connexion Deepgram en cours...")
    }

    private val deepgramListener = object : WebSocketListener() {
        override fun onOpen(ws: WebSocket, response: Response) {
            Log.d(TAG, "🔌 Deepgram WebSocket connecté")
        }

        override fun onMessage(ws: WebSocket, text: String) {
            try {
                val json = JSONObject(text)

                // Erreur Deepgram ?
                if (json.has("error")) {
                    Log.e(TAG, "Deepgram error: ${json.getString("error")}")
                    return
                }

                val channel = json.optJSONObject("channel") ?: return
                val alternatives = channel.optJSONArray("alternatives") ?: return
                if (alternatives.length() == 0) return

                val alt = alternatives.getJSONObject(0)
                val text2 = alt.optString("transcript", "")
                val isFinal = json.optBoolean("is_final", false)
                val speechFinal = json.optBoolean("speech_final", false)

                if (text2.isNotEmpty()) {
                    if (isFinal || speechFinal) {
                        if (transcript.isNotEmpty()) transcript.append(" ")
                        transcript.append(text2)
                        currentPartial = ""
                        Log.d(TAG, "📝 [FINAL] $text2")
                    } else {
                        currentPartial = text2
                        Log.d(TAG, "📝 [PARTIAL] $text2")
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Erreur parsing Deepgram", e)
            }
        }

        override fun onFailure(ws: WebSocket, t: Throwable, response: Response?) {
            Log.e(TAG, "❌ Deepgram WebSocket error: ${t.message}", t)
        }

        override fun onClosed(ws: WebSocket, code: Int, reason: String) {
            Log.d(TAG, "Deepgram WebSocket fermé: $reason")
        }
    }

    // =========================================================================
    // Audio streaming (AudioRecord → WebSocket)
    // =========================================================================
    @Suppress("MissingPermission") // Vérification faite dans startRecording()
    private fun startAudioStreaming() {
        val bufferSize = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL_CONFIG, AUDIO_FORMAT)
        audioRecord = AudioRecord(
            MediaRecorder.AudioSource.VOICE_RECOGNITION,
            SAMPLE_RATE,
            CHANNEL_CONFIG,
            AUDIO_FORMAT,
            bufferSize * 2
        )

        audioRecord?.startRecording()

        recordingThread = Thread({
            val buffer = ByteArray(bufferSize)
            while (isRecording && audioRecord != null) {
                val bytesRead = audioRecord?.read(buffer, 0, buffer.size) ?: -1
                if (bytesRead > 0 && webSocket != null) {
                    try {
                        webSocket?.send(buffer.copyOf(bytesRead).toByteString())
                    } catch (e: Exception) {
                        Log.e(TAG, "Erreur envoi audio", e)
                    }
                }
            }
        }, "NotitiaAudioStream").apply { start() }

        Log.d(TAG, "🎤 Stream audio démarré (buffer=$bufferSize)")
    }

    // =========================================================================
    // Timer + mise à jour widget & notification
    // =========================================================================
    private fun updateTimer() {
        val elapsed = System.currentTimeMillis() - startTimeMillis
        val totalSeconds = (elapsed / 1000).toInt()
        val minutes = totalSeconds / 60
        val seconds = totalSeconds % 60
        val formatted = String.format(Locale.US, "%02d:%02d", minutes, seconds)

        // Notification mise à jour
        val notification = buildNotification(formatted)
        val mgr = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        mgr.notify(NOTIFICATION_ID, notification)

        // Widget mise à jour
        updateWidgetState(true, formatted)
    }

    // =========================================================================
    // SharedPreferences + Widget refresh
    // =========================================================================
    private fun getPrefs(): SharedPreferences =
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun updateWidgetState(isRec: Boolean, timer: String) {
        getPrefs().edit()
            .putBoolean("is_recording", isRec)
            .putString("timer", timer)
            .apply()

        // Rafraîchir le widget
        triggerWidgetUpdate()
    }

    private fun savePendingTranscription(text: String) {
        val dateStr = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US).format(Date())
        getPrefs().edit()
            .putString("pending_transcription", text)
            .putString("pending_transcription_date", dateStr)
            .apply()

        Log.d(TAG, "Transcript en attente sauvegardé (${text.length} chars)")
    }

    private fun triggerWidgetUpdate() {
        try {
            val mgr = AppWidgetManager.getInstance(this)
            val ids = mgr.getAppWidgetIds(
                ComponentName(this, NotitiaWidgetProvider::class.java)
            )
            val intent = Intent(this, NotitiaWidgetProvider::class.java).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
            }
            sendBroadcast(intent)
        } catch (e: Exception) {
            Log.e(TAG, "Erreur refresh widget", e)
        }
    }

    // =========================================================================
    // Notification
    // =========================================================================
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Enregistrement Widget Notitia",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Enregistrement vocal déclenché depuis le widget"
                setShowBadge(false)
                enableVibration(false)
                setSound(null, null)
            }
            val mgr = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            mgr.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(duration: String): Notification {
        // Action STOP dans la notification
        val stopIntent = Intent(this, NotitiaRecordingService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPending = PendingIntent.getService(
            this, 0, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Notitia — Enregistrement")
            .setContentText("🔴 $duration — Tap pour arrêter")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .addAction(
                android.R.drawable.ic_media_pause,
                "Arrêter",
                stopPending
            )
            .build()
    }
}
