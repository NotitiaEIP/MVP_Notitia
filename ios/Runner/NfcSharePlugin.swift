// =============================================================================
// NOTITIA — Plugin natif iOS : CoreNFC Tag Write / Read (NFC uniquement)
// =============================================================================
// Transfert de transcriptions uniquement par NFC via des tags NDEF.
//
// Architecture :
// - ÉMETTEUR : écrit les données compressées sur un tag NFC
// - RÉCEPTEUR : lit les données depuis un tag NFC
// - Aucune connexion Bluetooth, WiFi ou P2P n'est utilisée.
// =============================================================================

import Flutter
import UIKit
import CoreNFC

/// Plugin iOS pour le partage Tap-to-Share via NFC uniquement.
///
/// Architecture :
/// - ÉMETTEUR : écrit un record NDEF contenant la transcription sur un tag NFC
/// - RÉCEPTEUR : lit le record NDEF depuis le tag NFC
class NfcSharePlugin: NSObject {

    // MARK: - Constants

    private static let channelName = "com.notitia/nfc_share"
    private static let ndefDomain = "app.notitia"
    private static let ndefType   = "transcription"

    // MARK: - Properties

    private var channel: FlutterMethodChannel?
    private var nfcSession: NFCNDEFReaderSession?
    private var pendingWriteData: Data?
    private var isSender: Bool = false

    // MARK: - Registration

    static func register(with registrar: FlutterPluginRegistrar) {
        let plugin = NfcSharePlugin()

        plugin.channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger()
        )
        plugin.channel?.setMethodCallHandler(plugin.handleMethodCall)

        NSLog("[NfcSharePlugin] Registered (NFC-only). NFC available: \(NFCNDEFReaderSession.readingAvailable)")
    }

    // MARK: - Method Call Handler

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isNfcAvailable":
            result(NFCNDEFReaderSession.readingAvailable)

        case "writeToTag":
            handleWriteToTag(call: call, result: result)

        case "readFromTag":
            handleReadFromTag(result: result)

        case "stopSession":
            handleStopSession(result: result)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Sender (Write to NFC Tag)

    private func handleWriteToTag(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let dataB64 = args["data"] as? String,
              let data = Data(base64Encoded: dataB64) else {
            result(FlutterError(
                code: "INVALID_ARGS",
                message: "data (base64) requis",
                details: nil
            ))
            return
        }

        guard NFCNDEFReaderSession.readingAvailable else {
            result(FlutterError(
                code: "NFC_UNAVAILABLE",
                message: "NFC non disponible sur cet appareil",
                details: nil
            ))
            return
        }

        pendingWriteData = data
        isSender = true

        nfcSession = NFCNDEFReaderSession(
            delegate: self,
            queue: DispatchQueue.main,
            invalidateAfterFirstRead: false
        )
        nfcSession?.alertMessage = "Approchez un tag NFC pour écrire la transcription"
        nfcSession?.begin()

        notifyState("writing")
        result(true)
    }

    // MARK: - Receiver (Read from NFC Tag)

    private func handleReadFromTag(result: @escaping FlutterResult) {
        guard NFCNDEFReaderSession.readingAvailable else {
            result(FlutterError(
                code: "NFC_UNAVAILABLE",
                message: "NFC non disponible sur cet appareil",
                details: nil
            ))
            return
        }

        isSender = false
        pendingWriteData = nil

        nfcSession = NFCNDEFReaderSession(
            delegate: self,
            queue: DispatchQueue.main,
            invalidateAfterFirstRead: false
        )
        nfcSession?.alertMessage = "Approchez l'autre téléphone ou un tag NFC"
        nfcSession?.begin()

        notifyState("reading")
        result(true)
    }

    // MARK: - Stop Session

    private func handleStopSession(result: @escaping FlutterResult) {
        nfcSession?.invalidate()
        nfcSession = nil
        pendingWriteData = nil
        NSLog("[NfcSharePlugin] Session stopped")
        result(nil)
    }

    // MARK: - NFC Tag Write

    private func writeToTag(_ tag: NFCNDEFTag, session: NFCNDEFReaderSession) {
        guard let data = pendingWriteData else {
            session.invalidate(errorMessage: "Aucune donnée à écrire")
            return
        }

        tag.queryNDEFStatus { [weak self] status, capacity, error in
            guard let self = self else { return }

            if let error = error {
                session.invalidate(errorMessage: "Erreur tag: \(error.localizedDescription)")
                return
            }

            guard status == .readWrite else {
                session.invalidate(errorMessage: "Le tag NFC n'est pas inscriptible")
                DispatchQueue.main.async {
                    self.notifyError("Le tag NFC est en lecture seule.")
                }
                return
            }

            // Build NDEF record with external type
            let typeString = "\(NfcSharePlugin.ndefDomain):\(NfcSharePlugin.ndefType)"
            let record = NFCNDEFPayload(
                format: .nfcExternal,
                type: typeString.data(using: .utf8)!,
                identifier: Data(),
                payload: data
            )
            let message = NFCNDEFMessage(records: [record])

            // Check capacity
            guard message.length <= capacity else {
                let needed = message.length
                session.invalidate(errorMessage: "Tag trop petit (\(capacity) octets). Il faut \(needed) octets.")
                DispatchQueue.main.async {
                    self.notifyError("Capacité du tag insuffisante (\(capacity)/\(needed) octets). Utilisez un tag NFC de plus grande capacité.")
                }
                return
            }

            tag.writeNDEF(message) { [weak self] error in
                guard let self = self else { return }

                if let error = error {
                    session.invalidate(errorMessage: "Écriture échouée: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.notifyError("Écriture NFC échouée: \(error.localizedDescription)")
                    }
                } else {
                    self.pendingWriteData = nil
                    session.alertMessage = "Transcription écrite sur le tag NFC ✓"
                    session.invalidate()
                    DispatchQueue.main.async {
                        self.notifyWriteComplete()
                    }
                }
            }
        }
    }

    // MARK: - NFC Tag Read

    private func readFromTag(_ tag: NFCNDEFTag, session: NFCNDEFReaderSession) {
        tag.readNDEF { [weak self] message, error in
            guard let self = self else { return }

            if let error = error {
                session.invalidate(errorMessage: "Lecture échouée: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.notifyError("Lecture NFC échouée: \(error.localizedDescription)")
                }
                return
            }

            guard let message = message else {
                session.invalidate(errorMessage: "Tag NFC vide")
                DispatchQueue.main.async {
                    self.notifyError("Aucune donnée sur ce tag NFC.")
                }
                return
            }

            // Search for our custom record
            let expectedType = "\(NfcSharePlugin.ndefDomain):\(NfcSharePlugin.ndefType)"
            for record in message.records {
                if record.typeNameFormat == .nfcExternal,
                   let type = String(data: record.type, encoding: .utf8),
                   type == expectedType {
                    let base64 = record.payload.base64EncodedString()
                    session.alertMessage = "Transcription reçue ✓"
                    session.invalidate()
                    DispatchQueue.main.async {
                        self.notifyDataRead(base64)
                    }
                    return
                }
            }

            session.invalidate(errorMessage: "Aucune transcription Notitia sur ce tag")
            DispatchQueue.main.async {
                self.notifyError("Ce tag NFC ne contient pas de transcription Notitia.")
            }
        }
    }

    // MARK: - Flutter Notifications

    private func notifyState(_ state: String) {
        channel?.invokeMethod("onStateChanged", arguments: state)
    }

    private func notifyWriteComplete() {
        channel?.invokeMethod("onWriteComplete", arguments: nil)
    }

    private func notifyDataRead(_ base64Data: String) {
        channel?.invokeMethod("onDataRead", arguments: base64Data)
    }

    private func notifyError(_ message: String) {
        channel?.invokeMethod("onError", arguments: message)
    }
}

// MARK: - NFCNDEFReaderSessionDelegate

extension NfcSharePlugin: NFCNDEFReaderSessionDelegate {

    func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {
        NSLog("[NfcSharePlugin] NFC session active (mode: \(isSender ? "write" : "read"))")
    }

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        NSLog("[NfcSharePlugin] NFC session invalidated: \(error)")
        let nfcError = error as? NFCReaderError
        // Ne pas notifier en cas d'annulation utilisateur
        if nfcError?.code != .readerSessionInvalidationErrorUserCanceled &&
           nfcError?.code != .readerSessionInvalidationErrorFirstNDEFTagRead {
            DispatchQueue.main.async {
                self.notifyError("Session NFC terminée: \(error.localizedDescription)")
            }
        }
    }

    // Not called when invalidateAfterFirstRead = false
    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        // Unused — we use didDetect tags: instead
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        guard let tag = tags.first else {
            session.invalidate(errorMessage: "Aucun tag NFC détecté")
            return
        }

        session.connect(to: tag) { [weak self] error in
            guard let self = self else { return }

            if let error = error {
                session.invalidate(errorMessage: "Connexion au tag échouée: \(error.localizedDescription)")
                return
            }

            if self.isSender {
                self.writeToTag(tag, session: session)
            } else {
                self.readFromTag(tag, session: session)
            }
        }
    }
}
