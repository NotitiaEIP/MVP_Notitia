// =============================================================================
// NOTITIA — Plugin natif Android : NFC téléphone-à-téléphone (HCE + Reader)
// =============================================================================
// Transfert de transcriptions par NFC entre deux téléphones.
//
// Architecture :
// - ÉMETTEUR : active le service HCE → le téléphone émule un tag NFC Type 4
// - RÉCEPTEUR : active le Reader Mode → lit les données depuis l'émetteur
// - Fonctionne aussi avec des tags NFC physiques (réception uniquement)
// - Aucune connexion Bluetooth, WiFi ou P2P n'est utilisée.
// =============================================================================

package com.example.notitia

import android.content.Context
import android.nfc.NdefMessage
import android.nfc.NdefRecord
import android.nfc.NfcAdapter
import android.nfc.NfcManager
import android.nfc.Tag
import android.nfc.tech.IsoDep
import android.nfc.tech.Ndef
import android.os.Bundle
import android.util.Base64
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Plugin NFC pour le partage Tap-to-Share.
 *
 * Flux téléphone-à-téléphone :
 * 1. ÉMETTEUR : writeToTag(data) → charge les données dans le service HCE
 *    Le téléphone émule un tag NFC Type 4 (ISO-DEP).
 * 2. RÉCEPTEUR : readFromTag() → active le reader mode
 *    Lit les données depuis l'émetteur (ou un tag NFC physique).
 * 3. Les téléphones sont collés dos à dos → transfert automatique.
 */
class NfcSharePlugin(
    private val activity: MainActivity,
    private val flutterEngine: FlutterEngine
) {
    companion object {
        private const val TAG = "NfcSharePlugin"
        private const val CHANNEL = "com.notitia/nfc_share"
        private const val NDEF_DOMAIN = "app.notitia"
        private const val NDEF_TYPE = "transcription"
    }

    private var channel: MethodChannel? = null
    private var nfcAdapter: NfcAdapter? = null

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
                "writeToTag" -> handleStartSending(call, result)
                "readFromTag" -> handleStartReceiving(result)
                "stopSession" -> handleStopSession(result)
                else -> result.notImplemented()
            }
        }

        // Init NFC adapter
        val nfcManager = activity.getSystemService(Context.NFC_SERVICE) as? NfcManager
        nfcAdapter = nfcManager?.defaultAdapter

        Log.d(TAG, "NfcSharePlugin registered (HCE + Reader). NFC available: ${nfcAdapter?.isEnabled}")
    }

    // ---------------------------------------------------------------------------
    // NFC AVAILABILITY CHECK
    // ---------------------------------------------------------------------------

    private fun handleIsNfcAvailable(result: MethodChannel.Result) {
        val available = nfcAdapter?.isEnabled == true
        result.success(available)
    }

    // ---------------------------------------------------------------------------
    // MODE ÉMETTEUR — HCE (le téléphone émule un tag NFC Type 4)
    // ---------------------------------------------------------------------------

    private fun handleStartSending(call: MethodCall, result: MethodChannel.Result) {
        try {
            val dataB64 = call.argument<String>("data")
            if (dataB64 == null) {
                result.error("INVALID_ARGS", "data (base64) requis", null)
                return
            }

            val adapter = nfcAdapter
            if (adapter == null || !adapter.isEnabled) {
                result.error("NFC_UNAVAILABLE", "NFC non disponible ou désactivé", null)
                return
            }

            val data = Base64.decode(dataB64, Base64.DEFAULT)

            // ⚠️ Ne PAS activer le reader mode côté émetteur !
            // Le téléphone doit rester en mode card emulation (HCE).
            // Désactiver le reader mode au cas où il serait actif.
            adapter.disableReaderMode(activity)

            // Charger les données dans le service HCE
            NfcHceService.pendingData = data
            NfcHceService.onReadComplete = {
                Log.d(TAG, "HCE: données lues par le récepteur ✓")
                NfcHceService.clear()
                activity.runOnUiThread {
                    notifyWriteComplete()
                }
            }

            notifyState("writing")
            result.success(true)

            Log.d(TAG, "HCE émetteur prêt (${data.size} octets). En attente du récepteur...")

        } catch (e: Exception) {
            Log.e(TAG, "Start sending error", e)
            result.error("SEND_ERROR", e.message, null)
        }
    }

    // ---------------------------------------------------------------------------
    // MODE RÉCEPTEUR — Reader Mode (lit depuis HCE ou tag physique)
    // ---------------------------------------------------------------------------

    private fun handleStartReceiving(result: MethodChannel.Result) {
        try {
            val adapter = nfcAdapter
            if (adapter == null || !adapter.isEnabled) {
                result.error("NFC_UNAVAILABLE", "NFC non disponible ou désactivé", null)
                return
            }

            // S'assurer que le HCE est désactivé côté récepteur
            NfcHceService.clear()

            // Activer le reader mode
            adapter.enableReaderMode(
                activity,
                { tag -> handleTagDiscovered(tag) },
                NfcAdapter.FLAG_READER_NFC_A or
                        NfcAdapter.FLAG_READER_NFC_B or
                        NfcAdapter.FLAG_READER_NO_PLATFORM_SOUNDS,
                Bundle().apply {
                    putInt(NfcAdapter.EXTRA_READER_PRESENCE_CHECK_DELAY, 250)
                }
            )

            notifyState("reading")
            result.success(true)

            Log.d(TAG, "Reader mode activé. En attente d'une source NFC...")

        } catch (e: Exception) {
            Log.e(TAG, "Start receiving error", e)
            result.error("RECEIVE_ERROR", e.message, null)
        }
    }

    // ---------------------------------------------------------------------------
    // TAG / HCE DÉTECTÉ — Lecture des données
    // ---------------------------------------------------------------------------

    private fun handleTagDiscovered(tag: Tag) {
        Log.d(TAG, "Tag détecté. Techs: ${tag.techList.joinToString()}")

        // 1. Essayer Ndef (tag physique, ou HCE si NDEF discovery a réussi)
        val ndef = Ndef.get(tag)
        if (ndef != null) {
            readViaNdef(ndef)
            return
        }

        // 2. Essayer IsoDep (HCE quand NDEF discovery n'a pas abouti)
        val isoDep = IsoDep.get(tag)
        if (isoDep != null) {
            readViaIsoDep(isoDep)
            return
        }

        // Aucun protocole supporté
        activity.runOnUiThread {
            notifyError("Appareil NFC non compatible ou tag vide.")
        }
    }

    /**
     * Lecture via Ndef tech (tag physique + HCE si NDEF auto-détecté).
     */
    private fun readViaNdef(ndef: Ndef) {
        try {
            ndef.connect()
            val message = ndef.ndefMessage ?: ndef.cachedNdefMessage
            ndef.close()

            if (message == null) {
                activity.runOnUiThread { notifyError("Aucune donnée NFC.") }
                return
            }

            extractNotitiaData(message)

        } catch (e: Exception) {
            Log.e(TAG, "Ndef read error", e)
            activity.runOnUiThread {
                notifyError("Lecture NFC échouée: ${e.message}")
            }
        }
    }

    /**
     * Lecture via IsoDep (commandes APDU manuelles Type 4 Tag).
     * Utilisé quand l'émetteur est un autre téléphone (HCE).
     */
    private fun readViaIsoDep(isoDep: IsoDep) {
        try {
            isoDep.connect()
            isoDep.timeout = 5000

            // 1. SELECT NDEF Application (AID D2760000850101)
            var resp = isoDep.transceive(byteArrayOf(
                0x00, 0xA4.toByte(), 0x04, 0x00, 0x07,
                0xD2.toByte(), 0x76, 0x00, 0x00, 0x85.toByte(), 0x01, 0x01,
                0x00
            ))
            if (!isSwOk(resp)) {
                isoDep.close()
                activity.runOnUiThread { notifyError("Appareil non compatible Notitia.") }
                return
            }

            // 2. SELECT CC file (E103)
            resp = isoDep.transceive(byteArrayOf(
                0x00, 0xA4.toByte(), 0x00, 0x0C, 0x02,
                0xE1.toByte(), 0x03
            ))
            if (!isSwOk(resp)) {
                isoDep.close()
                activity.runOnUiThread { notifyError("Erreur lecture CC.") }
                return
            }

            // 3. READ BINARY CC (15 octets)
            resp = isoDep.transceive(byteArrayOf(
                0x00, 0xB0.toByte(), 0x00, 0x00, 0x0F
            ))
            if (!isSwOk(resp) || resp.size < 17) {
                isoDep.close()
                activity.runOnUiThread { notifyError("Erreur lecture CC.") }
                return
            }
            // CC parsed (nous savons que le fichier NDEF est E104)

            // 4. SELECT NDEF file (E104)
            resp = isoDep.transceive(byteArrayOf(
                0x00, 0xA4.toByte(), 0x00, 0x0C, 0x02,
                0xE1.toByte(), 0x04
            ))
            if (!isSwOk(resp)) {
                isoDep.close()
                activity.runOnUiThread { notifyError("Fichier NDEF non trouvé.") }
                return
            }

            // 5. READ BINARY — NLEN (2 premiers octets)
            resp = isoDep.transceive(byteArrayOf(
                0x00, 0xB0.toByte(), 0x00, 0x00, 0x02
            ))
            if (!isSwOk(resp) || resp.size < 4) {
                isoDep.close()
                activity.runOnUiThread { notifyError("Lecture taille NDEF échouée.") }
                return
            }
            val ndefLen = ((resp[0].toInt() and 0xFF) shl 8) or (resp[1].toInt() and 0xFF)
            Log.d(TAG, "NDEF message length: $ndefLen bytes")

            if (ndefLen == 0) {
                isoDep.close()
                activity.runOnUiThread { notifyError("Message NDEF vide.") }
                return
            }

            // 6. READ BINARY — données NDEF (offset +2 pour sauter NLEN)
            val ndefData = ByteArray(ndefLen)
            var offset = 0
            val chunkSize = 250
            while (offset < ndefLen) {
                val toRead = minOf(chunkSize, ndefLen - offset)
                val fileOffset = offset + 2  // +2 pour sauter NLEN
                val readCmd = byteArrayOf(
                    0x00, 0xB0.toByte(),
                    ((fileOffset shr 8) and 0xFF).toByte(),
                    (fileOffset and 0xFF).toByte(),
                    (toRead and 0xFF).toByte()
                )
                resp = isoDep.transceive(readCmd)
                if (!isSwOk(resp)) {
                    isoDep.close()
                    activity.runOnUiThread { notifyError("Lecture données NDEF échouée.") }
                    return
                }
                val dataLen = resp.size - 2  // exclure SW (90 00)
                System.arraycopy(resp, 0, ndefData, offset, dataLen)
                offset += dataLen
            }

            isoDep.close()

            // Parser NdefMessage et extraire les données Notitia
            val ndefMessage = NdefMessage(ndefData)
            extractNotitiaData(ndefMessage)

        } catch (e: Exception) {
            Log.e(TAG, "IsoDep read error", e)
            activity.runOnUiThread {
                notifyError("Lecture NFC échouée: ${e.message}")
            }
        }
    }

    /**
     * Extrait les données Notitia d'un NdefMessage.
     */
    private fun extractNotitiaData(message: NdefMessage) {
        val expectedType = "$NDEF_DOMAIN:$NDEF_TYPE"
        for (record in message.records) {
            if (record.tnf == NdefRecord.TNF_EXTERNAL_TYPE) {
                val type = String(record.type, Charsets.UTF_8)
                if (type == expectedType) {
                    val base64Data = Base64.encodeToString(
                        record.payload, Base64.NO_WRAP
                    )

                    // Désactiver le reader mode
                    nfcAdapter?.disableReaderMode(activity)

                    Log.d(TAG, "Données Notitia reçues (${record.payload.size} octets) ✓")

                    activity.runOnUiThread {
                        notifyDataRead(base64Data)
                    }
                    return
                }
            }
        }

        activity.runOnUiThread {
            notifyError("Ce tag/appareil ne contient pas de transcription Notitia.")
        }
    }

    /**
     * Vérifie si la réponse APDU se termine par SW 90 00 (succès).
     */
    private fun isSwOk(response: ByteArray): Boolean {
        return response.size >= 2 &&
                response[response.size - 2] == 0x90.toByte() &&
                response[response.size - 1] == 0x00.toByte()
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
            NfcHceService.clear()
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

    private fun notifyWriteComplete() {
        channel?.invokeMethod("onWriteComplete", null)
    }

    private fun notifyDataRead(base64Data: String) {
        channel?.invokeMethod("onDataRead", base64Data)
    }

    private fun notifyError(message: String) {
        channel?.invokeMethod("onError", message)
    }
}
