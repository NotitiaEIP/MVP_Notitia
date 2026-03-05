// =============================================================================
// NOTITIA — Plugin natif iOS : CoreNFC + MultipeerConnectivity
// =============================================================================

import Flutter
import UIKit
import CoreNFC
import MultipeerConnectivity

/// Plugin iOS pour le partage Tap-to-Share via NFC et MultipeerConnectivity.
///
/// Architecture :
/// - ÉMETTEUR : écrit un tag NFC (handshake) + host MultipeerConnectivity
/// - RÉCEPTEUR : lit un tag NFC + browse MultipeerConnectivity
/// - Transfert P2P via MultipeerConnectivity (WiFi/BT)
class NfcSharePlugin: NSObject {

    // MARK: - Constants

    private static let channelName = "com.notitia/nfc_share"
    private static let serviceType = "notitia-share" // Max 15 chars, no dots

    // MARK: - Properties

    private var channel: FlutterMethodChannel?
    private var registrar: FlutterPluginRegistrar?

    // NFC
    private var nfcSession: NFCNDEFReaderSession?

    // MultipeerConnectivity
    private var peerID: MCPeerID?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var session: MCSession?

    // Session state
    private var currentSessionId: String?
    private var currentFilePath: String?
    private var currentFileSize: Int = 0
    private var currentChecksum: String?
    private var isSender: Bool = false
    private var connectedPeer: MCPeerID?

    // MARK: - Registration

    static func register(with registrar: FlutterPluginRegistrar) {
        let plugin = NfcSharePlugin()
        plugin.registrar = registrar

        plugin.channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger()
        )
        plugin.channel?.setMethodCallHandler(plugin.handleMethodCall)

        // Init peer ID
        plugin.peerID = MCPeerID(displayName: UIDevice.current.name)

        NSLog("[NfcSharePlugin] Registered. NFC available: \(NFCNDEFReaderSession.readingAvailable)")
    }

    // MARK: - Method Call Handler

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isNfcAvailable":
            result(NFCNDEFReaderSession.readingAvailable)

        case "startAdvertising":
            handleStartAdvertising(call: call, result: result)

        case "startDiscovery":
            handleStartDiscovery(call: call, result: result)

        case "stopSession":
            handleStopSession(result: result)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Sender (Advertising)

    private func handleStartAdvertising(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let filePath = args["file_path"] as? String,
              let sessionId = args["session_id"] as? String,
              let checksum = args["checksum"] as? String else {
            result(FlutterError(
                code: "INVALID_ARGS",
                message: "file_path, session_id, checksum requis",
                details: nil
            ))
            return
        }

        let fileSize = args["file_size"] as? Int ?? 0

        // Verify file exists
        guard FileManager.default.fileExists(atPath: filePath) else {
            result(FlutterError(
                code: "FILE_NOT_FOUND",
                message: "Fichier introuvable: \(filePath)",
                details: nil
            ))
            return
        }

        currentSessionId = sessionId
        currentFilePath = filePath
        currentFileSize = fileSize
        currentChecksum = checksum
        isSender = true

        // Start MultipeerConnectivity advertiser
        startMCAdvertiser(sessionId: sessionId)

        notifyState("advertising")
        result(true)
    }

    private func startMCAdvertiser(sessionId: String) {
        guard let peerID = peerID else { return }

        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session?.delegate = self

        advertiser = MCNearbyServiceAdvertiser(
            peer: peerID,
            discoveryInfo: ["session_id": sessionId],
            serviceType: NfcSharePlugin.serviceType
        )
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()

        NSLog("[NfcSharePlugin] MC advertising started for session: \(sessionId)")
    }

    // MARK: - Receiver (Discovery)

    private func handleStartDiscovery(call: FlutterMethodCall, result: @escaping FlutterResult) {
        isSender = false

        // Start NFC reader session
        startNFCReaderSession()

        // Start MultipeerConnectivity browser
        startMCBrowser()

        notifyState("discovering")
        result(true)
    }

    private func startNFCReaderSession() {
        guard NFCNDEFReaderSession.readingAvailable else {
            NSLog("[NfcSharePlugin] NFC not available on this device")
            return
        }

        nfcSession = NFCNDEFReaderSession(
            delegate: self,
            queue: DispatchQueue.main,
            invalidateAfterFirstRead: true
        )
        nfcSession?.alertMessage = "Approchez votre appareil pour le partage Notitia"
        nfcSession?.begin()

        NSLog("[NfcSharePlugin] NFC reader session started")
    }

    private func startMCBrowser() {
        guard let peerID = peerID else { return }

        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session?.delegate = self

        browser = MCNearbyServiceBrowser(
            peer: peerID,
            serviceType: NfcSharePlugin.serviceType
        )
        browser?.delegate = self
        browser?.startBrowsingForPeers()

        NSLog("[NfcSharePlugin] MC browsing started")
    }

    // MARK: - File Transfer

    private func sendFile(to peer: MCPeerID) {
        guard let filePath = currentFilePath,
              let session = session else {
            notifyError("Aucun fichier à envoyer")
            return
        }

        let fileURL = URL(fileURLWithPath: filePath)

        // Send handshake metadata first
        if let handshakeData = createHandshakeData() {
            do {
                try session.send(handshakeData, toPeers: [peer], with: .reliable)
                NSLog("[NfcSharePlugin] Handshake sent to \(peer.displayName)")
            } catch {
                NSLog("[NfcSharePlugin] Failed to send handshake: \(error)")
            }
        }

        // Send file via resource transfer
        let progress = session.sendResource(
            at: fileURL,
            withName: fileURL.lastPathComponent,
            toPeer: peer
        ) { error in
            if let error = error {
                NSLog("[NfcSharePlugin] File send error: \(error)")
                DispatchQueue.main.async {
                    self.notifyError("Erreur lors de l'envoi: \(error.localizedDescription)")
                }
            } else {
                NSLog("[NfcSharePlugin] File sent successfully")
                DispatchQueue.main.async {
                    self.notifyTransferComplete(filePath: nil)
                }
            }
        }

        // Observe progress
        if let progress = progress {
            observeProgress(progress)
        }
    }

    private func createHandshakeData() -> Data? {
        guard let sessionId = currentSessionId,
              let checksum = currentChecksum else { return nil }

        let handshake: [String: Any] = [
            "session_id": sessionId,
            "device_name": UIDevice.current.name,
            "file_size": currentFileSize,
            "checksum": checksum,
            "transport_type": "multipeer"
        ]

        return try? JSONSerialization.data(withJSONObject: handshake)
    }

    private func observeProgress(_ progress: Progress) {
        // KVO on progress
        let timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            let transferred = Int(progress.completedUnitCount)
            let total = Int(progress.totalUnitCount)

            self.notifyProgress(bytesTransferred: transferred, totalBytes: total)

            if progress.isFinished || progress.isCancelled {
                timer.invalidate()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    // MARK: - Stop Session

    private func handleStopSession(result: @escaping FlutterResult) {
        stopAll()
        result(nil)
    }

    private func stopAll() {
        nfcSession?.invalidate()
        nfcSession = nil

        advertiser?.stopAdvertisingPeer()
        advertiser = nil

        browser?.stopBrowsingForPeers()
        browser = nil

        session?.disconnect()
        session = nil

        connectedPeer = nil
        currentSessionId = nil
        currentFilePath = nil
        currentFileSize = 0
        currentChecksum = nil

        NSLog("[NfcSharePlugin] Session stopped")
    }

    // MARK: - Flutter Notifications

    private func notifyState(_ state: String) {
        channel?.invokeMethod("onStateChanged", arguments: state)
    }

    private func notifyHandshake(sessionId: String, deviceName: String, fileSize: Int, checksum: String) {
        channel?.invokeMethod("onHandshakeReceived", arguments: [
            "session_id": sessionId,
            "device_name": deviceName,
            "file_size": fileSize,
            "checksum": checksum,
            "transport_type": "multipeer"
        ])
    }

    private func notifyProgress(bytesTransferred: Int, totalBytes: Int) {
        channel?.invokeMethod("onTransferProgress", arguments: [
            "bytes_transferred": bytesTransferred,
            "total_bytes": totalBytes
        ])
    }

    private func notifyTransferComplete(filePath: String?) {
        channel?.invokeMethod("onTransferComplete", arguments: [
            "file_path": filePath as Any,
            "checksum": currentChecksum as Any
        ])
    }

    private func notifyError(_ message: String) {
        channel?.invokeMethod("onError", arguments: message)
    }
}

// MARK: - NFCNDEFReaderSessionDelegate

extension NfcSharePlugin: NFCNDEFReaderSessionDelegate {

    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        for message in messages {
            for record in message.records {
                guard record.typeNameFormat == .nfcExternal,
                      let payloadStr = String(data: record.payload, encoding: .utf8) else { continue }

                NSLog("[NfcSharePlugin] NFC detected: \(payloadStr)")

                if let data = payloadStr.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

                    let sessionId = json["session_id"] as? String ?? ""
                    let deviceName = json["device_name"] as? String ?? "Unknown"
                    let fileSize = json["file_size"] as? Int ?? 0
                    let checksum = json["checksum"] as? String ?? ""

                    currentSessionId = sessionId
                    currentFileSize = fileSize
                    currentChecksum = checksum

                    DispatchQueue.main.async {
                        self.notifyHandshake(
                            sessionId: sessionId,
                            deviceName: deviceName,
                            fileSize: fileSize,
                            checksum: checksum
                        )
                        self.notifyState("connecting")
                    }
                }
            }
        }
    }

    func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {
        NSLog("[NfcSharePlugin] NFC session active")
    }

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        NSLog("[NfcSharePlugin] NFC session invalidated: \(error)")
    }
}

// MARK: - MCSessionDelegate

extension NfcSharePlugin: MCSessionDelegate {

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        NSLog("[NfcSharePlugin] Peer \(peerID.displayName) state: \(state.rawValue)")

        switch state {
        case .connected:
            connectedPeer = peerID
            DispatchQueue.main.async {
                self.notifyState("transferring")
            }
            if isSender {
                sendFile(to: peerID)
            }

        case .notConnected:
            connectedPeer = nil

        case .connecting:
            DispatchQueue.main.async {
                self.notifyState("connecting")
            }

        @unknown default:
            break
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Handshake from sender
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let sessionId = json["session_id"] as? String ?? ""
        let deviceName = json["device_name"] as? String ?? "Unknown"
        let fileSize = json["file_size"] as? Int ?? 0
        let checksum = json["checksum"] as? String ?? ""

        currentSessionId = sessionId
        currentFileSize = fileSize
        currentChecksum = checksum

        DispatchQueue.main.async {
            self.notifyHandshake(
                sessionId: sessionId,
                deviceName: deviceName,
                fileSize: fileSize,
                checksum: checksum
            )
        }
    }

    func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {
        if let error = error {
            NSLog("[NfcSharePlugin] Resource receive error: \(error)")
            DispatchQueue.main.async {
                self.notifyError("Erreur de réception: \(error.localizedDescription)")
            }
            return
        }

        guard let localURL = localURL else {
            DispatchQueue.main.async {
                self.notifyError("Fichier reçu introuvable")
            }
            return
        }

        // Copy to app's cache directory
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent("nfc_received")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let destURL = cacheDir.appendingPathComponent(
            "received_\(Int(Date().timeIntervalSince1970 * 1000)).notitia"
        )

        do {
            try FileManager.default.moveItem(at: localURL, to: destURL)
            NSLog("[NfcSharePlugin] File saved: \(destURL.path)")

            DispatchQueue.main.async {
                self.notifyTransferComplete(filePath: destURL.path)
            }
        } catch {
            NSLog("[NfcSharePlugin] File save error: \(error)")
            DispatchQueue.main.async {
                self.notifyError("Erreur de sauvegarde: \(error.localizedDescription)")
            }
        }
    }

    func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {
        NSLog("[NfcSharePlugin] Receiving resource: \(resourceName)")
        DispatchQueue.main.async {
            self.observeProgress(progress)
        }
    }

    func session(
        _ session: MCSession,
        didReceive stream: InputStream,
        withName streamName: String,
        fromPeer peerID: MCPeerID
    ) {
        // Not used
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension NfcSharePlugin: MCNearbyServiceAdvertiserDelegate {

    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        NSLog("[NfcSharePlugin] Invitation from \(peerID.displayName)")
        invitationHandler(true, session)
    }

    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didNotStartAdvertisingPeer error: Error
    ) {
        NSLog("[NfcSharePlugin] Advertising error: \(error)")
        DispatchQueue.main.async {
            self.notifyError("Impossible de démarrer le partage: \(error.localizedDescription)")
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension NfcSharePlugin: MCNearbyServiceBrowserDelegate {

    func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        NSLog("[NfcSharePlugin] Found peer: \(peerID.displayName), info: \(info ?? [:])")

        let peerSessionId = info?["session_id"]

        if currentSessionId != nil && peerSessionId == currentSessionId {
            // Session ID matches — connect
            NSLog("[NfcSharePlugin] Session match! Inviting \(peerID.displayName)")
            browser.invitePeer(peerID, to: session!, withContext: nil, timeout: 30)
        } else if currentSessionId == nil {
            // No NFC handshake yet — connect to first peer
            currentSessionId = peerSessionId
            browser.invitePeer(peerID, to: session!, withContext: nil, timeout: 30)
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        NSLog("[NfcSharePlugin] Lost peer: \(peerID.displayName)")
    }

    func browser(
        _ browser: MCNearbyServiceBrowser,
        didNotStartBrowsingForPeers error: Error
    ) {
        NSLog("[NfcSharePlugin] Browsing error: \(error)")
        DispatchQueue.main.async {
            self.notifyError("Impossible de scanner: \(error.localizedDescription)")
        }
    }
}
