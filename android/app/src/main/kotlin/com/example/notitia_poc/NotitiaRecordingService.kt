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
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * NOTITIA — Service d'enregistrement natif (Foreground Service)
 *
 * Enregistre l'audio dans un fichier WAV, SANS ouvrir l'application Flutter.
 * Aucune clé ni appel réseau ici : la transcription (Whisper open source via
 * la passerelle Notitia) est faite par l'app à sa prochaine ouverture.
 *
 * Déclenché par le widget écran d'accueil :
 *   ACTION_START → démarre l'enregistrement + notification persistante
 *   ACTION_STOP  → arrête, sauvegarde le transcript dans SharedPreferences
 *
 * Le widget lit l'état (is_recording, timer) dans SharedPreferences
 * et affiche le bon layout (idle / recording + timer).
 *
 * Au prochain lancement de l'app Flutter, les enregistrements en attente
 * (pending_audio_paths) sont transcrits, corrigés et sauvegardés.
 */
class NotitiaRecordingService : Service() {

    companion object {
        const val TAG = "NotitiaRec"

        const val ACTION_START = "com.example.notitia.action.START_RECORDING"
        const val ACTION_STOP  = "com.example.notitia.action.STOP_RECORDING"

        const val CHANNEL_ID      = "notitia_widget_recording"
        const val NOTIFICATION_ID  = 1001
        const val PREFS_NAME       = "HomeWidgetPreferences"

        // Audio : PCM 16 bits mono 16 kHz (format attendu par Whisper)
        private const val SAMPLE_RATE      = 16000
        private const val CHANNEL_CONFIG   = AudioFormat.CHANNEL_IN_MONO
        private const val AUDIO_FORMAT     = AudioFormat.ENCODING_PCM_16BIT
    }

    // =========================================================================
    // État
    // =========================================================================
    private var audioRecord: AudioRecord? = null
    private var recordingThread: Thread? = null
    private var isRecording = false

    private var pcmFile: File? = null
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

        // Mettre à jour le widget immédiatement
        updateWidgetState(true, "00:00")

        // Démarrer l'enregistrement audio dans un fichier
        startAudioRecording()

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

        // Arrêter l'enregistrement et attendre l'écriture des derniers octets
        try {
            audioRecord?.stop()
        } catch (e: Exception) {
            Log.e(TAG, "Erreur arrêt AudioRecord", e)
        }
        try {
            recordingThread?.join(2000)
        } catch (e: InterruptedException) {
            Log.e(TAG, "Attente du thread audio interrompue", e)
        }
        audioRecord?.release()
        audioRecord = null
        recordingThread = null

        // Fichier PCM → WAV, ajouté aux enregistrements en attente (Flutter le transcrira)
        val wav = pcmFile?.let { finalizeWav(it) }
        pcmFile = null
        if (wav != null) {
            savePendingAudio(wav)
        }

        // Repasser le widget en état idle
        updateWidgetState(false, "00:00")

        // Arrêter le foreground service
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()

        Log.d(TAG, "✅ Enregistrement arrêté et sauvegardé")
    }

    // =========================================================================
    // Enregistrement audio (AudioRecord → fichier PCM)
    // =========================================================================
    @Suppress("MissingPermission") // Vérification faite dans startRecording()
    private fun startAudioRecording() {
        val bufferSize = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL_CONFIG, AUDIO_FORMAT)
        audioRecord = AudioRecord(
            MediaRecorder.AudioSource.VOICE_RECOGNITION,
            SAMPLE_RATE,
            CHANNEL_CONFIG,
            AUDIO_FORMAT,
            bufferSize * 2
        )

        val file = File(recordingsDir(), "widget_${System.currentTimeMillis()}.pcm")
        pcmFile = file
        audioRecord?.startRecording()

        recordingThread = Thread({
            val buffer = ByteArray(bufferSize)
            try {
                FileOutputStream(file).use { out ->
                    while (isRecording && audioRecord != null) {
                        val bytesRead = audioRecord?.read(buffer, 0, buffer.size) ?: -1
                        if (bytesRead > 0) out.write(buffer, 0, bytesRead)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Erreur écriture audio", e)
            }
        }, "NotitiaAudioRecord").apply { start() }

        Log.d(TAG, "🎤 Enregistrement audio démarré → ${file.name}")
    }

    private fun recordingsDir(): File =
        File(filesDir, "widget_recordings").apply { mkdirs() }

    /** Ajoute l'en-tête WAV (44 octets) au PCM brut ; null si rien d'enregistré. */
    private fun finalizeWav(pcm: File): File? {
        val dataSize = pcm.length()
        if (dataSize < SAMPLE_RATE * 2 / 2) { // < 0,5 s : rien d'exploitable
            pcm.delete()
            return null
        }
        val wav = File(pcm.parentFile, pcm.nameWithoutExtension + ".wav")
        try {
            FileOutputStream(wav).use { out ->
                out.write(wavHeader(dataSize))
                pcm.inputStream().use { input -> input.copyTo(out) }
            }
            pcm.delete()
            return wav
        } catch (e: Exception) {
            Log.e(TAG, "Erreur création WAV", e)
            return null
        }
    }

    private fun wavHeader(dataSize: Long): ByteArray {
        val byteRate = SAMPLE_RATE * 2
        val header = java.nio.ByteBuffer.allocate(44).order(java.nio.ByteOrder.LITTLE_ENDIAN)
        header.put("RIFF".toByteArray())
        header.putInt((36 + dataSize).toInt())
        header.put("WAVE".toByteArray())
        header.put("fmt ".toByteArray())
        header.putInt(16)                // taille du bloc fmt
        header.putShort(1)               // PCM
        header.putShort(1)               // mono
        header.putInt(SAMPLE_RATE)
        header.putInt(byteRate)
        header.putShort(2)               // octets par échantillon
        header.putShort(16)              // bits
        header.put("data".toByteArray())
        header.putInt(dataSize.toInt())
        return header.array()
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
        // La transcription se fait à l'ouverture de l'app : simple indication ici
        val liveText = if (isRec) "🎙️ Enregistrement… (transcrit à l'ouverture de Notitia)" else ""

        getPrefs().edit()
            .putBoolean("is_recording", isRec)
            .putString("timer", timer)
            .putString("live_transcript", liveText)
            .apply()

        // Rafraîchir les deux widgets (petit + grand)
        triggerWidgetUpdate()
    }

    /** Liste (une ligne par fichier) des enregistrements à transcrire par l'app. */
    private fun savePendingAudio(wav: File) {
        val prefs = getPrefs()
        val existing = prefs.getString("pending_audio_paths", "").orEmpty()
        val paths = if (existing.isBlank()) wav.absolutePath else "$existing\n${wav.absolutePath}"
        val dateStr = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US).format(Date())
        prefs.edit()
            .putString("pending_audio_paths", paths)
            .putString("pending_transcription_date", dateStr)
            .putString("last_transcription", "Enregistrement prêt — ouvrez Notitia")
            .putString("live_transcript", "")
            .apply()

        Log.d(TAG, "Enregistrement en attente : ${wav.name} (${wav.length() / 1024} Ko)")
    }

    private fun triggerWidgetUpdate() {
        try {
            val mgr = AppWidgetManager.getInstance(this)

            // Petit widget (2×2)
            val smallIds = mgr.getAppWidgetIds(
                ComponentName(this, NotitiaWidgetProvider::class.java)
            )
            if (smallIds.isNotEmpty()) {
                val intent = Intent(this, NotitiaWidgetProvider::class.java).apply {
                    action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, smallIds)
                }
                sendBroadcast(intent)
            }

            // Grand widget (3×3)
            val largeIds = mgr.getAppWidgetIds(
                ComponentName(this, NotitiaWidgetLargeProvider::class.java)
            )
            if (largeIds.isNotEmpty()) {
                val intent = Intent(this, NotitiaWidgetLargeProvider::class.java).apply {
                    action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, largeIds)
                }
                sendBroadcast(intent)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Erreur refresh widgets", e)
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
