// =============================================================================
// NOTITIA — Service HCE (Host Card Emulation) pour transfert NFC téléphone-à-téléphone
// =============================================================================
// Émule un NFC Forum Type 4 Tag via ISO-DEP (ISO 14443-4).
//
// Quand l'utilisateur choisit ENVOYER, ce service est activé avec les données
// de transcription. L'autre téléphone (en reader mode) peut alors lire les
// données comme si c'était un tag NFC physique.
//
// Protocole implémenté :
//   - SELECT by AID  (D2760000850101 = NDEF Tag Application)
//   - SELECT by File ID (E103 = CC, E104 = NDEF)
//   - READ BINARY
//
// Compatible avec : Android reader mode + iOS NFCNDEFReaderSession
// =============================================================================

package com.example.notitia

import android.nfc.NdefMessage
import android.nfc.NdefRecord
import android.nfc.cardemulation.HostApduService
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log

class NfcHceService : HostApduService() {

    companion object {
        private const val TAG = "NfcHceService"

        // ==================================================================
        // Données partagées — settées par NfcSharePlugin avant utilisation
        // ==================================================================

        /** Données brutes (.notitia bytes) à partager via NFC. Null = service inactif. */
        @Volatile
        var pendingData: ByteArray? = null

        /** Callback appelé quand le récepteur a terminé la lecture. */
        var onReadComplete: (() -> Unit)? = null

        /** Réinitialise le service (plus de données à partager). */
        fun clear() {
            pendingData = null
            onReadComplete = null
        }

        // ==================================================================
        // Constantes NFC Type 4 Tag
        // ==================================================================

        // NDEF Application AID (NFC Forum)
        private val NDEF_AID = byteArrayOf(
            0xD2.toByte(), 0x76, 0x00, 0x00,
            0x85.toByte(), 0x01, 0x01
        )

        // File IDs
        private val CC_FILE_ID   = byteArrayOf(0xE1.toByte(), 0x03)
        private val NDEF_FILE_ID = byteArrayOf(0xE1.toByte(), 0x04)

        // Status Words
        private val SW_OK              = byteArrayOf(0x90.toByte(), 0x00)
        private val SW_NOT_FOUND       = byteArrayOf(0x6A.toByte(), 0x82.toByte())
        private val SW_WRONG_PARAMS    = byteArrayOf(0x6B.toByte(), 0x00)
        private val SW_INS_NOT_SUPPORTED = byteArrayOf(0x6D.toByte(), 0x00)
    }

    // ==================================================================
    // État interne de la session APDU
    // ==================================================================

    private enum class SelectedFile { NONE, CC, NDEF }

    private var appSelected  = false
    private var selectedFile = SelectedFile.NONE
    private var ndefWasRead  = false

    // Fichiers construits à la demande
    private var ccFileBytes:   ByteArray = byteArrayOf()
    private var ndefFileBytes: ByteArray = byteArrayOf()

    // ==================================================================
    // processCommandApdu — Point d'entrée pour chaque commande APDU
    // ==================================================================

    override fun processCommandApdu(commandApdu: ByteArray, extras: Bundle?): ByteArray {
        // Si pas de données à partager → service inactif
        if (pendingData == null) return SW_NOT_FOUND

        if (commandApdu.size < 4) return SW_INS_NOT_SUPPORTED

        val ins = commandApdu[1]
        val p1  = commandApdu[2]
        val p2  = commandApdu[3]

        return when (ins) {
            0xA4.toByte() -> handleSelect(commandApdu, p1, p2)
            0xB0.toByte() -> handleReadBinary(commandApdu, p1, p2)
            else          -> SW_INS_NOT_SUPPORTED
        }
    }

    // ==================================================================
    // SELECT (INS = 0xA4)
    // ==================================================================

    private fun handleSelect(apdu: ByteArray, p1: Byte, p2: Byte): ByteArray {
        // SELECT by AID (P1 = 0x04)
        if (p1 == 0x04.toByte()) {
            val lc = if (apdu.size > 4) apdu[4].toInt() and 0xFF else 0
            if (lc == 0 || apdu.size < 5 + lc) return SW_WRONG_PARAMS

            val aid = apdu.copyOfRange(5, 5 + lc)
            if (aid.contentEquals(NDEF_AID)) {
                appSelected  = true
                selectedFile = SelectedFile.NONE
                buildFiles()
                Log.d(TAG, "NDEF Application selected → files built")
                return SW_OK
            }
            return SW_NOT_FOUND
        }

        // SELECT by File ID (P1 = 0x00, P2 = 0x0C)
        if (p1 == 0x00.toByte() && p2 == 0x0C.toByte()) {
            if (!appSelected) return SW_NOT_FOUND

            val lc = if (apdu.size > 4) apdu[4].toInt() and 0xFF else 0
            if (lc < 2 || apdu.size < 5 + lc) return SW_WRONG_PARAMS

            val fid = apdu.copyOfRange(5, 5 + 2)
            return when {
                fid.contentEquals(CC_FILE_ID) -> {
                    selectedFile = SelectedFile.CC
                    Log.d(TAG, "CC file selected")
                    SW_OK
                }
                fid.contentEquals(NDEF_FILE_ID) -> {
                    selectedFile = SelectedFile.NDEF
                    Log.d(TAG, "NDEF file selected")
                    SW_OK
                }
                else -> SW_NOT_FOUND
            }
        }

        return SW_WRONG_PARAMS
    }

    // ==================================================================
    // READ BINARY (INS = 0xB0)
    // ==================================================================

    private fun handleReadBinary(apdu: ByteArray, p1: Byte, p2: Byte): ByteArray {
        val file = when (selectedFile) {
            SelectedFile.CC   -> ccFileBytes
            SelectedFile.NDEF -> ndefFileBytes
            SelectedFile.NONE -> return SW_NOT_FOUND
        }

        val offset = ((p1.toInt() and 0xFF) shl 8) or (p2.toInt() and 0xFF)
        if (offset >= file.size) return SW_WRONG_PARAMS

        // Le = dernier octet de l'APDU (0 = 256)
        val le = if (apdu.size > 4) {
            val raw = apdu[apdu.size - 1].toInt() and 0xFF
            if (raw == 0) 256 else raw
        } else 256

        val end = minOf(offset + le, file.size)
        val chunk = file.copyOfRange(offset, end)

        // Détecter quand le fichier NDEF a été entièrement lu
        if (selectedFile == SelectedFile.NDEF && end >= ndefFileBytes.size) {
            ndefWasRead = true
            Log.d(TAG, "NDEF file fully read ✓")
        }

        return chunk + SW_OK
    }

    // ==================================================================
    // Construction des fichiers Type 4 Tag (CC + NDEF)
    // ==================================================================

    private fun buildFiles() {
        val data = pendingData ?: byteArrayOf()

        // 1. Message NDEF avec record de type externe
        val typeString = "app.notitia:transcription"
        val record = NdefRecord(
            NdefRecord.TNF_EXTERNAL_TYPE,
            typeString.toByteArray(Charsets.UTF_8),
            ByteArray(0),   // identifier
            data             // payload = données .notitia brutes
        )
        val ndefMessage = NdefMessage(arrayOf(record))
        val ndefBytes = ndefMessage.toByteArray()

        // 2. Fichier NDEF = [NLEN (2 octets)] + [message NDEF]
        ndefFileBytes = ByteArray(2 + ndefBytes.size)
        ndefFileBytes[0] = ((ndefBytes.size shr 8) and 0xFF).toByte()
        ndefFileBytes[1] = (ndefBytes.size and 0xFF).toByte()
        System.arraycopy(ndefBytes, 0, ndefFileBytes, 2, ndefBytes.size)

        // 3. Capability Container (CC) — 15 octets (NFC Forum Type 4 v2.0)
        val maxSize = ndefFileBytes.size
        ccFileBytes = byteArrayOf(
            0x00, 0x0F,                                              // CCLEN = 15 octets
            0x20,                                                    // Mapping version 2.0
            0x00, 0xFF.toByte(),                                     // MLe = 255 (max R-APDU data)
            0x00, 0xFF.toByte(),                                     // MLc = 255 (max C-APDU data)
            0x04, 0x06,                                              // NDEF File Control TLV (T=04, L=06)
            0xE1.toByte(), 0x04,                                     // File ID = E104
            ((maxSize shr 8) and 0xFF).toByte(),                     // Max NDEF file size (high)
            (maxSize and 0xFF).toByte(),                             // Max NDEF file size (low)
            0x00,                                                    // Read access: open
            0xFF.toByte()                                            // Write access: denied
        )

        Log.d(TAG, "Files built: NDEF msg=${ndefBytes.size}B, file=${ndefFileBytes.size}B, CC=${ccFileBytes.size}B")
    }

    // ==================================================================
    // Déconnexion NFC
    // ==================================================================

    override fun onDeactivated(reason: Int) {
        val reasonStr = if (reason == DEACTIVATION_LINK_LOSS) "link_loss" else "deselected"
        Log.d(TAG, "Deactivated ($reasonStr), ndefRead=$ndefWasRead")

        if (ndefWasRead) {
            // Notifier le plugin que le récepteur a lu nos données
            Handler(Looper.getMainLooper()).post {
                onReadComplete?.invoke()
            }
            ndefWasRead = false
        }

        // Réinitialiser l'état de session (pas les données)
        selectedFile = SelectedFile.NONE
        appSelected = false
    }
}
