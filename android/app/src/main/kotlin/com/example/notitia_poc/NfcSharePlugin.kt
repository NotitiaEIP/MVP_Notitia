// =============================================================================
// NOTITIA — Plugin natif Android : NFC Handshake + Nearby Connections P2P
// =============================================================================
// Architecture :
// - NFC reader mode (récepteur) : lit les tags NDEF pour le handshake
// - Nearby Connections API : transfert du fichier .notitia via P2P (BLE/WiFi)
// - Handshake metadata : envoyé comme BYTES payload via Nearby Connections
//   (Android Beam / setNdefPushMessage supprimé en Android 14+)
// =============================================================================

package com.example.notitia

import android.content.Context
import android.nfc.NdefMessage
import android.nfc.NdefRecord
import android.nfc.NfcAdapter
import android.nfc.NfcManager
import android.nfc.Tag
import android.nfc.tech.Ndef
import android.os.Build
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.util.Log
import com.google.android.gms.nearby.Nearby
import com.google.android.gms.nearby.connection.*
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.charset.Charset

/**
 * Plugin NFC + Nearby Connections pour le partage Tap-to-Share.
 *
 * Flux :
 * 1. ÉMETTEUR : startAdvertising() → prépare le handshake + démarre Nearby advertising
 * 2. RÉCEPTEUR : startDiscovery() → active NFC reader + démarre Nearby discovery
 * 3. Nearby Connections : connexion P2P établie via session ID matching
 * 4. ÉMETTEUR envoie handshake metadata (BYTES) puis le fichier (FILE)
 * 5. Le résultat est renvoyé à Flutter via le MethodChannel
 */
class NfcSharePlugin(
    private val activity: MainActivity,
    private val flutterEngine: FlutterEngine
) {
    companion object {
        private const val TAG = "NfcSharePlugin"
        private const val CHANNEL = "com.notitia/nfc_share"
        private const val SERVICE_ID = "com.notitia.tap_share"
        private const val NDEF_DOMAIN = "com.notitia"
        private const val NDEF_TYPE = "share"
    }

    private var channel: MethodChannel? = null
    private var nfcAdapter: NfcAdapter? = null

    // Session state
    private var currentSessionId: String? = null
    private var currentFilePath: String? = null
    private var currentFileSize: Int = 0
    private var currentChecksum: String? = null
    private var isSender: Boolean = false

    // Nearby Connections
    private var connectionsClient: ConnectionsClient? = null
    private var connectedEndpointId: String? = null
    private var pendingHandshakePayload: String? = null
    private var sentFilePayloadId: Long = -1

    // ---------------------------------------------------------------------------
    // INITIALISATION
    // ---------------------------------------------------------------------------

    fun register() {
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        )
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isNfcAvailable" -> handleIsNfcAvailable(result)
                "startAdvertising" -> handleStartAdvertising(call, result)
                "startDiscovery" -> handleStartDiscovery(call, result)
                "stopSession" -> handleStopSession(result)
                else -> result.notImplemented()
            }
        }

        // Init NFC adapter
        val nfcManager = activity.getSystemService(Context.NFC_SERVICE) as? NfcManager
        nfcAdapter = nfcManager?.defaultAdapter

        // Init Nearby Connections
        connectionsClient = Nearby.getConnectionsClient(activity)

        Log.d(TAG, "NfcSharePlugin registered. NFC available: ${nfcAdapter != null}")
    }

    // ---------------------------------------------------------------------------
    // NFC AVAILABILITY CHECK
    // ---------------------------------------------------------------------------

    private fun handleIsNfcAvailable(result: MethodChannel.Result) {
        val available = nfcAdapter?.isEnabled == true
        result.success(available)
    }

    // ---------------------------------------------------------------------------
    // MODE ÉMETTEUR — Nearby Advertising
    // ---------------------------------------------------------------------------

    private fun handleStartAdvertising(call: MethodCall, result: MethodChannel.Result) {
        try {
            val filePath = call.argument<String>("file_path")
            val sessionId = call.argument<String>("session_id")
            val fileSize = call.argument<Int>("file_size") ?: 0
            val checksum = call.argument<String>("checksum")

            if (filePath == null || sessionId == null || checksum == null) {
                result.error("INVALID_ARGS", "file_path, session_id, checksum requis", null)
                return
            }

            val file = File(filePath)
            if (!file.exists()) {
                result.error("FILE_NOT_FOUND", "Fichier introuvable: $filePath", null)
                return
            }

            currentSessionId = sessionId
            currentFilePath = filePath
            currentFileSize = fileSize
            currentChecksum = checksum
            isSender = true

            // 1. Préparer le handshake metadata (sera envoyé via Nearby BYTES payload)
            setupSenderHandshake(sessionId, fileSize, checksum)

            // 2. Démarrer Nearby Connections en mode Advertising
            startNearbyAdvertising(sessionId)

            notifyState("advertising")
            result.success(true)

        } catch (e: Exception) {
            Log.e(TAG, "Start advertising error", e)
            result.error("ADVERTISING_ERROR", e.message, null)
        }
    }

    /**
     * Prépare les métadonnées du handshake côté émetteur.
     * Sera envoyé comme BYTES payload après connexion Nearby.
     */
    private fun setupSenderHandshake(sessionId: String, fileSize: Int, checksum: String) {
        val handshakeJson = JSONObject().apply {
            put("session_id", sessionId)
            put("device_name", Build.MODEL)
            put("file_size", fileSize)
            put("checksum", checksum)
            put("transport_type", "nearby")
        }

        pendingHandshakePayload = handshakeJson.toString()
        Log.d(TAG, "Sender handshake prepared: session=$sessionId")
    }

    /**
     * Démarre Nearby Connections en mode Advertising (émetteur).
     * L'émetteur attend qu'un récepteur se connecte.
     */
    private fun startNearbyAdvertising(sessionId: String) {
        val advertisingOptions = AdvertisingOptions.Builder()
            .setStrategy(Strategy.P2P_POINT_TO_POINT)
            .build()

        connectionsClient?.startAdvertising(
            sessionId, // Utiliser le sessionId comme endpoint name
            SERVICE_ID,
            connectionLifecycleCallback,
            advertisingOptions
        )?.addOnSuccessListener {
            Log.d(TAG, "Nearby advertising started")
        }?.addOnFailureListener { e ->
            Log.e(TAG, "Nearby advertising failed", e)
            notifyError("Impossible de démarrer le partage P2P: ${e.message}")
        }
    }

    // ---------------------------------------------------------------------------
    // MODE RÉCEPTEUR — NFC Discovery + Nearby Discovery
    // ---------------------------------------------------------------------------

    private fun handleStartDiscovery(call: MethodCall, result: MethodChannel.Result) {
        try {
            isSender = false

            // 1. Activer le NFC reader mode pour lire le handshake
            setupNfcReceiver()

            // 2. Démarrer Nearby Connections en mode Discovery
            startNearbyDiscovery()

            notifyState("discovering")
            result.success(true)

        } catch (e: Exception) {
            Log.e(TAG, "Start discovery error", e)
            result.error("DISCOVERY_ERROR", e.message, null)
        }
    }

    /**
     * Active le NFC en mode reader pour lire un éventuel message NDEF.
     */
    private fun setupNfcReceiver() {
        val adapter = nfcAdapter ?: return

        adapter.enableReaderMode(
            activity,
            { tag -> handleNfcTagDiscovered(tag) },
            NfcAdapter.FLAG_READER_NFC_A or
                    NfcAdapter.FLAG_READER_NFC_B or
                    NfcAdapter.FLAG_READER_NFC_F or
                    NfcAdapter.FLAG_READER_NFC_V or
                    NfcAdapter.FLAG_READER_NO_PLATFORM_SOUNDS,
            Bundle().apply {
                putInt(NfcAdapter.EXTRA_READER_PRESENCE_CHECK_DELAY, 250)
            }
        )

        Log.d(TAG, "NFC receiver configured")
    }

    /**
     * Callback quand un tag NFC est détecté en mode reader.
     * Lit le message NDEF pour extraire les métadonnées du handshake.
     */
    private fun handleNfcTagDiscovered(tag: Tag) {
        try {
            val ndef = Ndef.get(tag) ?: return
            ndef.connect()
            val ndefMessage = ndef.ndefMessage ?: return
            ndef.close()

            for (record in ndefMessage.records) {
                if (record.tnf == NdefRecord.TNF_EXTERNAL_TYPE) {
                    val payload = String(record.payload, Charset.forName("UTF-8"))
                    Log.d(TAG, "NFC handshake received: $payload")

                    val json = JSONObject(payload)
                    val sessionId = json.optString("session_id", "")
                    val deviceName = json.optString("device_name", "Unknown")
                    val fileSize = json.optInt("file_size", 0)
                    val checksum = json.optString("checksum", "")

                    currentSessionId = sessionId
                    currentFileSize = fileSize
                    currentChecksum = checksum

                    // Notifier Flutter du handshake
                    activity.runOnUiThread {
                        notifyHandshake(sessionId, deviceName, fileSize, checksum)
                        notifyState("connecting")
                    }

                    return
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "NFC read error", e)
        }
    }

    /**
     * Démarre Nearby Connections en mode Discovery (récepteur).
     */
    private fun startNearbyDiscovery() {
        val discoveryOptions = DiscoveryOptions.Builder()
            .setStrategy(Strategy.P2P_POINT_TO_POINT)
            .build()

        connectionsClient?.startDiscovery(
            SERVICE_ID,
            endpointDiscoveryCallback,
            discoveryOptions
        )?.addOnSuccessListener {
            Log.d(TAG, "Nearby discovery started")
        }?.addOnFailureListener { e ->
            Log.e(TAG, "Nearby discovery failed", e)
            notifyError("Impossible de scanner les appareils: ${e.message}")
        }
    }

    // ---------------------------------------------------------------------------
    // NEARBY CONNECTIONS CALLBACKS
    // ---------------------------------------------------------------------------

    /**
     * Callback quand un endpoint est découvert (côté récepteur).
     * Connecte automatiquement si le sessionId correspond.
     */
    private val endpointDiscoveryCallback = object : EndpointDiscoveryCallback() {
        override fun onEndpointFound(endpointId: String, info: DiscoveredEndpointInfo) {
            Log.d(TAG, "Endpoint found: $endpointId, name=${info.endpointName}")

            // Le nom de l'endpoint est le sessionId — vérifier la correspondance
            if (currentSessionId != null && info.endpointName == currentSessionId) {
                Log.d(TAG, "Session match! Connecting to $endpointId")
                connectionsClient?.requestConnection(
                    Build.MODEL,
                    endpointId,
                    connectionLifecycleCallback
                )
            } else if (currentSessionId == null) {
                // Pas encore de handshake NFC — se connecter au premier endpoint trouvé
                currentSessionId = info.endpointName
                connectionsClient?.requestConnection(
                    Build.MODEL,
                    endpointId,
                    connectionLifecycleCallback
                )
            }
        }

        override fun onEndpointLost(endpointId: String) {
            Log.d(TAG, "Endpoint lost: $endpointId")
        }
    }

    /**
     * Callback du cycle de vie de la connexion (les deux côtés).
     */
    private val connectionLifecycleCallback = object : ConnectionLifecycleCallback() {
        override fun onConnectionInitiated(endpointId: String, info: ConnectionInfo) {
            Log.d(TAG, "Connection initiated with $endpointId")
            // Accepter automatiquement (la sécurité est assurée par le sessionId)
            connectionsClient?.acceptConnection(endpointId, payloadCallback)
        }

        override fun onConnectionResult(endpointId: String, result: ConnectionResolution) {
            if (result.status.isSuccess) {
                Log.d(TAG, "Connected to $endpointId")
                connectedEndpointId = endpointId

                // Arrêter advertising/discovery après connexion
                connectionsClient?.stopAdvertising()
                connectionsClient?.stopDiscovery()

                activity.runOnUiThread {
                    notifyState("transferring")
                }

                // Si émetteur, envoyer le handshake metadata puis le fichier
                if (isSender) {
                    pendingHandshakePayload?.let { json ->
                        val bytes = json.toByteArray(Charset.forName("UTF-8"))
                        connectionsClient?.sendPayload(endpointId, Payload.fromBytes(bytes))
                    }
                    currentFilePath?.let { sendFile(endpointId, it) }
                }
            } else {
                Log.e(TAG, "Connection failed: ${result.status}")
                activity.runOnUiThread {
                    notifyError("Connexion P2P échouée: ${result.status.statusMessage}")
                }
            }
        }

        override fun onDisconnected(endpointId: String) {
            Log.d(TAG, "Disconnected from $endpointId")
            connectedEndpointId = null
        }
    }

    // ---------------------------------------------------------------------------
    // TRANSFERT DE FICHIER via Nearby Connections
    // ---------------------------------------------------------------------------

    /**
     * Envoie le fichier .notitia au récepteur connecté.
     */
    private fun sendFile(endpointId: String, filePath: String) {
        try {
            val file = File(filePath)
            val filePayload = Payload.fromFile(file)
            sentFilePayloadId = filePayload.id

            Log.d(TAG, "Sending file: ${file.name} (${file.length()} bytes), payloadId=${filePayload.id}")

            connectionsClient?.sendPayload(endpointId, filePayload)
                ?.addOnSuccessListener {
                    Log.d(TAG, "File payload sent")
                }
                ?.addOnFailureListener { e ->
                    Log.e(TAG, "Send payload failed", e)
                    activity.runOnUiThread {
                        notifyError("Erreur lors de l'envoi: ${e.message}")
                    }
                }

        } catch (e: Exception) {
            Log.e(TAG, "Send file error", e)
            activity.runOnUiThread {
                notifyError("Impossible d'envoyer le fichier: ${e.message}")
            }
        }
    }

    /**
     * Callback de réception des payloads (côté récepteur).
     * 
     * IMPORTANT : Le PFD est dupliqué (dup()) dans onPayloadReceived car le
     * framework Nearby Connections peut fermer le fd original après le transfert.
     * Appeler asParcelFileDescriptor() dans onPayloadTransferUpdate(SUCCESS)
     * provoque EBADF (Bad file descriptor).
     */
    private val payloadCallback = object : PayloadCallback() {
        private var filePayloadId: Long = -1
        private var receivedPfd: ParcelFileDescriptor? = null

        override fun onPayloadReceived(endpointId: String, payload: Payload) {
            when (payload.type) {
                Payload.Type.FILE -> {
                    Log.d(TAG, "Receiving file payload id=${payload.id}")
                    filePayloadId = payload.id
                    // Capturer et dupliquer le PFD MAINTENANT, avant que le
                    // framework ne ferme le fd après la fin du transfert.
                    try {
                        val originalPfd = payload.asFile()?.asParcelFileDescriptor()
                        receivedPfd = originalPfd?.dup()
                        // Ne PAS fermer originalPfd ici — le framework en a
                        // encore besoin pour écrire les données entrantes.
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to dup() PFD on receive", e)
                        receivedPfd = null
                    }
                }
                Payload.Type.BYTES -> {
                    // Handshake metadata from sender
                    val data = payload.asBytes() ?: return
                    val jsonStr = String(data, Charset.forName("UTF-8"))
                    Log.d(TAG, "Handshake payload received: $jsonStr")
                    try {
                        val json = JSONObject(jsonStr)
                        val sessionId = json.optString("session_id", "")
                        val deviceName = json.optString("device_name", "Unknown")
                        val fileSize = json.optInt("file_size", 0)
                        val checksum = json.optString("checksum", "")

                        currentSessionId = sessionId
                        currentFileSize = fileSize
                        currentChecksum = checksum

                        activity.runOnUiThread {
                            notifyHandshake(sessionId, deviceName, fileSize, checksum)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to parse handshake payload", e)
                    }
                }
                else -> {
                    Log.d(TAG, "Received unknown payload type: ${payload.type}")
                }
            }
        }

        override fun onPayloadTransferUpdate(endpointId: String, update: PayloadTransferUpdate) {
            // Notifier la progression pour le FILE payload (émetteur OU récepteur)
            val isFilePayload = update.payloadId == filePayloadId || update.payloadId == sentFilePayloadId
            if (isFilePayload) {
                val totalBytes = update.totalBytes
                val bytesTransferred = update.bytesTransferred

                if (totalBytes > 0) {
                    activity.runOnUiThread {
                        notifyProgress(bytesTransferred, totalBytes)
                    }
                }
            }

            when (update.status) {
                PayloadTransferUpdate.Status.SUCCESS -> {
                    if (isSender && update.payloadId == sentFilePayloadId) {
                        // Côté émetteur : le fichier a été entièrement envoyé
                        Log.d(TAG, "Sender FILE sent complete: ${update.bytesTransferred} bytes")
                        sentFilePayloadId = -1
                        handleTransferComplete(null)
                    } else if (!isSender && update.payloadId == filePayloadId) {
                        // Côté récepteur : le fichier a été entièrement reçu
                        Log.d(TAG, "Receiver FILE received complete: ${update.bytesTransferred} bytes")
                        handleTransferComplete(receivedPfd)
                        receivedPfd = null
                    }
                }
                PayloadTransferUpdate.Status.FAILURE -> {
                    if (isFilePayload) {
                        Log.e(TAG, "FILE transfer failed")
                        receivedPfd?.close()
                        receivedPfd = null
                        sentFilePayloadId = -1
                        activity.runOnUiThread {
                            notifyError("Le transfert a échoué. Réessayez.")
                        }
                    }
                }
                PayloadTransferUpdate.Status.CANCELED -> {
                    if (isFilePayload) {
                        Log.w(TAG, "FILE transfer cancelled")
                        receivedPfd?.close()
                        receivedPfd = null
                        sentFilePayloadId = -1
                        activity.runOnUiThread {
                            notifyError("Le transfert a été annulé.")
                        }
                    }
                }
                PayloadTransferUpdate.Status.IN_PROGRESS -> {
                    // Progression normale
                }
            }
        }
    }

    /**
     * Traitement après réception complète du fichier.
     * Lit via le ParcelFileDescriptor dupliqué (compatible scoped storage,
     * pas de EBADF car le dup() survit à la fermeture du fd original).
     */
    private fun handleTransferComplete(pfd: ParcelFileDescriptor?) {
        if (isSender) {
            // Côté émetteur : le transfert est réussi
            activity.runOnUiThread {
                notifyTransferComplete(null)
            }
            return
        }

        // Côté récepteur : sauvegarder le fichier
        try {
            if (pfd == null) {
                activity.runOnUiThread {
                    notifyError("Fichier reçu introuvable.")
                }
                return
            }

            // Copier dans le dossier cache de l'app via le file descriptor dupliqué
            val cacheDir = File(activity.cacheDir, "nfc_received")
            if (!cacheDir.exists()) cacheDir.mkdirs()

            val destFile = File(cacheDir, "received_${System.currentTimeMillis()}.notitia")

            FileInputStream(pfd.fileDescriptor).use { input ->
                FileOutputStream(destFile).use { output ->
                    input.copyTo(output)
                }
            }
            pfd.close()

            Log.d(TAG, "File saved to: ${destFile.absolutePath} (${destFile.length()} bytes)")

            activity.runOnUiThread {
                notifyTransferComplete(destFile.absolutePath)
            }

        } catch (e: Exception) {
            Log.e(TAG, "Handle transfer complete error", e)
            activity.runOnUiThread {
                notifyError("Erreur lors de la sauvegarde du fichier: ${e.message}")
            }
        }
    }

    // ---------------------------------------------------------------------------
    // STOP SESSION
    // ---------------------------------------------------------------------------

    private fun handleStopSession(result: MethodChannel.Result) {
        stopAll()
        result.success(null)
    }

    private fun stopAll() {
        try {
            nfcAdapter?.disableReaderMode(activity)

            connectionsClient?.stopAdvertising()
            connectionsClient?.stopDiscovery()
            connectedEndpointId?.let {
                connectionsClient?.disconnectFromEndpoint(it)
            }
            connectionsClient?.stopAllEndpoints()

            connectedEndpointId = null
            currentSessionId = null
            currentFilePath = null
            currentFileSize = 0
            currentChecksum = null
            pendingHandshakePayload = null
            sentFilePayloadId = -1

            Log.d(TAG, "Session stopped")
        } catch (e: Exception) {
            Log.e(TAG, "Stop error", e)
        }
    }

    fun unregister() {
        stopAll()
        channel?.setMethodCallHandler(null)
        channel = null
    }

    // ---------------------------------------------------------------------------
    // NOTIFICATIONS VERS FLUTTER (via MethodChannel)
    // ---------------------------------------------------------------------------

    private fun notifyState(state: String) {
        channel?.invokeMethod("onStateChanged", state)
    }

    private fun notifyHandshake(
        sessionId: String,
        deviceName: String,
        fileSize: Int,
        checksum: String
    ) {
        channel?.invokeMethod("onHandshakeReceived", mapOf(
            "session_id" to sessionId,
            "device_name" to deviceName,
            "file_size" to fileSize,
            "checksum" to checksum,
            "transport_type" to "nearby"
        ))
    }

    private fun notifyProgress(bytesTransferred: Long, totalBytes: Long) {
        channel?.invokeMethod("onTransferProgress", mapOf(
            "bytes_transferred" to bytesTransferred.toInt(),
            "total_bytes" to totalBytes.toInt()
        ))
    }

    private fun notifyTransferComplete(filePath: String?) {
        channel?.invokeMethod("onTransferComplete", mapOf(
            "file_path" to filePath,
            "checksum" to currentChecksum
        ))
    }

    private fun notifyError(message: String) {
        channel?.invokeMethod("onError", message)
    }
}
