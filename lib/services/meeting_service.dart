// =============================================================================
// NOTITIA — Service de réunion via réseau local (WebSocket)
// =============================================================================
//
// Architecture :
//   - L'hôte lance un serveur HTTP léger sur le réseau local.
//   - Les participants scannent le QR code contenant l'IP:port de l'hôte.
//   - Ils rejoignent via POST /join puis ouvrent un WebSocket sur /ws.
//   - L'hôte POUSSE les mises à jour et la transcription via WebSocket.
//   - Plus de polling : communication push en temps réel.
//
// Réseau local (même Wi-Fi) = le plus simple, pas de serveur cloud nécessaire.
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/meeting.dart';
import '../models/transcription.dart';

/// État de la réunion côté host ou participant.
enum MeetingStatus { waiting, active, ended }

// =============================================================================
// SERVICE HOST — Celui qui lance la réunion
// =============================================================================
class MeetingHostService {
  HttpServer? _server;
  final List<MeetingParticipant> _participants = [];
  final List<WebSocket> _wsClients = [];
  MeetingStatus _status = MeetingStatus.waiting;
  Transcription? _finalTranscription;
  String? _hostName;
  String? _meetingId;

  List<MeetingParticipant> get participants => List.unmodifiable(_participants);
  MeetingStatus get status => _status;

  /// Callback quand un nouveau participant rejoint.
  void Function(MeetingParticipant)? onParticipantJoined;

  /// Récupère l'adresse IP locale du téléphone sur le réseau Wi-Fi.
  static Future<String?> getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      String? wifiIp;
      String? fallbackIp;

      for (final iface in interfaces) {
        final n = iface.name.toLowerCase();
        if (n.startsWith('lo') ||
            n.startsWith('docker') ||
            n.startsWith('br-') ||
            n.startsWith('veth') ||
            n.startsWith('virbr') ||
            n.startsWith('vmnet')) {
          continue;
        }
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            if (n.startsWith('wlan') ||
                n.startsWith('wl') ||
                n.contains('wifi') ||
                n.contains('wi-fi') ||
                n.startsWith('en0') ||
                n.startsWith('ap')) {
              wifiIp = addr.address;
            } else {
              fallbackIp ??= addr.address;
            }
          }
        }
      }

      final ip = wifiIp ?? fallbackIp;
      if (ip != null) debugPrint('[Host] IP locale détectée : $ip');
      return ip;
    } catch (e) {
      debugPrint('[Host] Erreur récupération IP locale : $e');
    }
    return null;
  }

  /// Démarre le serveur HTTP local pour la réunion.
  Future<String?> startServer({required String hostName}) async {
    _hostName = hostName;
    _meetingId = DateTime.now().millisecondsSinceEpoch.toString();
    _status = MeetingStatus.waiting;
    _participants.clear();
    _wsClients.clear();

    final localIp = await getLocalIp();
    if (localIp == null) return null;

    _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    final port = _server!.port;

    debugPrint('[Host] Serveur réunion démarré sur $localIp:$port');

    _server!.listen(_handleRequest);

    return jsonEncode({
      'ip': localIp,
      'port': port,
      'meetingId': _meetingId,
      'hostName': _hostName,
    });
  }

  /// Passe la réunion en mode actif (enregistrement lancé).
  void startRecording() {
    _status = MeetingStatus.active;
    _broadcastStatus();
  }

  void _handleRequest(HttpRequest request) async {
    try {
      final path = request.uri.path;

      // WebSocket upgrade
      if (path == '/ws' && WebSocketTransformer.isUpgradeRequest(request)) {
        final ws = await WebSocketTransformer.upgrade(request);
        _wsClients.add(ws);
        debugPrint('[Host] WebSocket client connecté (total: ${_wsClients.length})');

        // Envoyer l'état actuel immédiatement
        _sendTo(ws, _buildStatusMessage());

        // Si la réunion est déjà terminée avec transcription, envoyer aussi
        if (_status == MeetingStatus.ended && _finalTranscription != null) {
          _sendTo(ws, {
            'type': 'transcription',
            'transcription': _finalTranscription!.toJson(),
          });
        }

        ws.listen(
          (_) {}, // On n'attend pas de messages du client
          onDone: () {
            _wsClients.remove(ws);
            debugPrint('[Host] WebSocket client déconnecté (restant: ${_wsClients.length})');
          },
          onError: (_) => _wsClients.remove(ws),
        );
        return;
      }

      // HTTP classique
      request.response.headers.set('Content-Type', 'application/json');

      if (request.method == 'POST' && path == '/join') {
        await _handleJoin(request);
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write(jsonEncode({'error': 'Not found'}));
      }
    } catch (e) {
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write(jsonEncode({'error': e.toString()}));
    } finally {
      if (!WebSocketTransformer.isUpgradeRequest(request)) {
        await request.response.close();
      }
    }
  }

  Future<void> _handleJoin(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    final data = jsonDecode(body) as Map<String, dynamic>;

    final name = data['name'] as String? ?? 'Anonyme';
    final participantId = DateTime.now().millisecondsSinceEpoch.toString();

    final participant = MeetingParticipant(
      id: participantId,
      name: name,
      ipAddress: request.connectionInfo?.remoteAddress.address ?? 'unknown',
    );

    // Éviter les doublons par nom + IP
    final alreadyJoined = _participants.any(
      (p) => p.name == name && p.ipAddress == participant.ipAddress,
    );
    if (!alreadyJoined) {
      _participants.add(participant);
      onParticipantJoined?.call(participant);
      // Notifier tous les clients WS du nouveau participant
      _broadcastStatus();
    }

    request.response.statusCode = HttpStatus.ok;
    request.response.write(jsonEncode({
      'participantId': participantId,
      'meetingId': _meetingId,
      'hostName': _hostName,
      'status': _status.name,
      'participants': _participants.map((p) => p.toJson()).toList(),
    }));
  }

  Map<String, dynamic> _buildStatusMessage() => {
    'type': 'status',
    'status': _status.name,
    'meetingId': _meetingId,
    'hostName': _hostName,
    'participants': _participants.map((p) => p.toJson()).toList(),
  };

  void _broadcastStatus() => _broadcast(_buildStatusMessage());

  void _broadcast(Map<String, dynamic> message) {
    final encoded = jsonEncode(message);
    final dead = <WebSocket>[];
    for (final ws in _wsClients) {
      try {
        ws.add(encoded);
      } catch (_) {
        dead.add(ws);
      }
    }
    for (final ws in dead) {
      _wsClients.remove(ws);
    }
    debugPrint('[Host] Broadcast type=${message['type']} à ${_wsClients.length} client(s)');
  }

  void _sendTo(WebSocket ws, Map<String, dynamic> message) {
    try {
      ws.add(jsonEncode(message));
    } catch (_) {
      _wsClients.remove(ws);
    }
  }

  /// Termine la réunion et pousse la transcription à tous les participants.
  void endMeeting(Transcription transcription) {
    _finalTranscription = transcription;
    _status = MeetingStatus.ended;

    // D'abord envoyer le changement de statut
    _broadcastStatus();

    // Puis envoyer la transcription
    _broadcast({
      'type': 'transcription',
      'transcription': transcription.toJson(),
    });

    debugPrint('[Host] Transcription envoyée à ${_wsClients.length} client(s)');
  }

  /// Arrête le serveur proprement.
  Future<void> stopServer() async {
    // Fermer tous les WebSockets
    for (final ws in _wsClients) {
      try {
        await ws.close(WebSocketStatus.goingAway, 'Réunion terminée');
      } catch (_) {}
    }
    _wsClients.clear();

    try {
      await _server?.close(force: false).timeout(
        const Duration(seconds: 5),
        onTimeout: () async {
          await _server?.close(force: true);
        },
      );
    } catch (_) {
      try { await _server?.close(force: true); } catch (_) {}
    }
    _server = null;
    _participants.clear();
    _status = MeetingStatus.waiting;
    _finalTranscription = null;
  }

  /// Informations pour construire l'objet Meeting à sauvegarder.
  Meeting buildMeetingRecord({required DateTime startedAt, String? transcriptionId}) {
    return Meeting(
      id: _meetingId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      hostName: _hostName ?? 'Hôte',
      startedAt: startedAt,
      endedAt: DateTime.now(),
      participants: List.from(_participants),
      transcriptionId: transcriptionId,
    );
  }
}

// =============================================================================
// SERVICE PARTICIPANT — Rejoint via WebSocket (push, pas de polling)
// =============================================================================
class MeetingClientService {
  String? _meetingId;
  WebSocket? _ws;
  bool _transcriptionReceived = false;

  MeetingStatus _status = MeetingStatus.waiting;
  String? _hostName;
  List<MeetingParticipant> _participants = [];

  MeetingStatus get status => _status;
  String? get hostName => _hostName;
  String? get meetingId => _meetingId;
  List<MeetingParticipant> get participants => List.unmodifiable(_participants);

  /// Callbacks
  void Function(MeetingStatus)? onStatusChanged;
  void Function(List<MeetingParticipant>)? onParticipantsUpdated;
  void Function(Transcription)? onTranscriptionReceived;

  /// Rejoint une réunion : POST /join puis connecte le WebSocket.
  Future<bool> joinMeeting({
    required String qrData,
    required String participantName,
  }) async {
    try {
      final data = jsonDecode(qrData) as Map<String, dynamic>;
      final ip = data['ip'] as String;
      final port = data['port'] as int;
      _meetingId = data['meetingId'] as String;
      _hostName = data['hostName'] as String?;
      _transcriptionReceived = false;

      // 1) POST /join pour s'enregistrer
      final joinResponse = await _doPost(ip, port, participantName);
      if (joinResponse == null) return false;

      final result = jsonDecode(joinResponse) as Map<String, dynamic>;
      _hostName = result['hostName'] as String?;
      _status = MeetingStatus.values.firstWhere(
        (s) => s.name == result['status'],
        orElse: () => MeetingStatus.waiting,
      );
      _updateParticipants(result['participants'] as List<dynamic>?);

      // 2) Ouvrir le WebSocket
      final wsUrl = 'ws://$ip:$port/ws';
      debugPrint('[Client] Connexion WebSocket vers $wsUrl');
      _ws = await WebSocket.connect(wsUrl).timeout(
        const Duration(seconds: 10),
      );
      debugPrint('[Client] WebSocket connecté');

      _ws!.listen(
        _onWsMessage,
        onDone: () {
          debugPrint('[Client] WebSocket fermé par le serveur');
          _ws = null;
        },
        onError: (e) {
          debugPrint('[Client] WebSocket erreur: $e');
          _ws = null;
        },
      );

      return true;
    } catch (e) {
      debugPrint('[Client] Erreur joinMeeting : $e');
    }
    return false;
  }

  /// POST /join avec un HttpClient éphémère.
  Future<String?> _doPost(String ip, int port, String name) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.postUrl(Uri.parse('http://$ip:$port/join'));
      request.headers.set('Content-Type', 'application/json');
      request.write(jsonEncode({'name': name}));
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      debugPrint('[Client] JOIN => ${response.statusCode}, ${body.length} bytes');
      if (response.statusCode == HttpStatus.ok) return body;
    } catch (e) {
      debugPrint('[Client] POST /join erreur: $e');
    } finally {
      client.close(force: true);
    }
    return null;
  }

  /// Traite un message WebSocket du serveur.
  void _onWsMessage(dynamic raw) {
    try {
      final message = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = message['type'] as String?;
      debugPrint('[Client] WS message reçu: type=$type');

      switch (type) {
        case 'status':
          final newStatus = MeetingStatus.values.firstWhere(
            (s) => s.name == message['status'],
            orElse: () => MeetingStatus.active,
          );
          _updateParticipants(message['participants'] as List<dynamic>?);
          if (newStatus != _status) {
            _status = newStatus;
            onStatusChanged?.call(_status);
          }
          break;

        case 'transcription':
          if (_transcriptionReceived) break;
          final tJson = message['transcription'];
          if (tJson != null && tJson is Map<String, dynamic>) {
            _transcriptionReceived = true;
            debugPrint('[Client] Transcription reçue ! (${raw.toString().length} bytes)');
            final t = Transcription.fromJson(tJson);
            onTranscriptionReceived?.call(t);
          }
          break;
      }
    } catch (e) {
      debugPrint('[Client] Erreur traitement message WS: $e');
    }
  }

  void _updateParticipants(List<dynamic>? list) {
    if (list == null) return;
    _participants = list
        .map((p) => MeetingParticipant.fromJson(p as Map<String, dynamic>))
        .toList();
    onParticipantsUpdated?.call(_participants);
  }

  /// Quitte la réunion proprement.
  void disconnect() {
    try {
      _ws?.close(WebSocketStatus.normalClosure, 'Déconnexion');
    } catch (_) {}
    _ws = null;
    _meetingId = null;
    _status = MeetingStatus.waiting;
    _participants = [];
    _transcriptionReceived = false;
  }
}
