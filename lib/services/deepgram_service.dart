import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:record/record.dart';

import '../config/ai_config.dart';

/// 🎙️ Service Deepgram Nova-3 pour Flutter
/// Transcription en temps réel via WebSocket - Sans serveur Python
/// 
/// Utilisation:
/// ```dart
/// final deepgram = DeepgramService();
/// deepgram.onTranscript = (text, isFinal) => print(text);
/// await deepgram.startListening();
/// // ...
/// await deepgram.stopListening();
/// ```
class DeepgramService {
  // ---------------------------------------------------------------------------
  // Configuration
  // ---------------------------------------------------------------------------
  
  /// Clé API Deepgram, injectée au build (DEEPGRAM_API_KEY dans env/ai.json)
  static const String _apiKey = ServiceKeys.deepgram;
  
  /// URL WebSocket Deepgram
  static const String _wsBaseUrl = 'wss://api.deepgram.com/v1/listen';
  
  /// Configuration par défaut
  String language;
  String model;
  bool punctuate;
  bool smartFormat;
  bool interimResults;
  int sampleRate;
  
  // ---------------------------------------------------------------------------
  // État interne
  // ---------------------------------------------------------------------------
  
  WebSocketChannel? _channel;
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _audioSubscription;
  
  bool _isListening = false;
  String _fullTranscript = '';
  String _currentPartial = '';
  double _confidence = 0.0;
  
  // ---------------------------------------------------------------------------
  // Callbacks
  // ---------------------------------------------------------------------------
  
  /// Appelé pour chaque transcription reçue
  /// - text: Le texte transcrit
  /// - isFinal: true si c'est un résultat final, false si partiel
  void Function(String text, bool isFinal)? onTranscript;
  
  /// Appelé en cas d'erreur
  void Function(String error)? onError;
  
  /// Appelé quand la connexion est établie
  void Function()? onConnected;
  
  /// Appelé quand la connexion est fermée
  void Function()? onDisconnected;
  
  // ---------------------------------------------------------------------------
  // Constructeur
  // ---------------------------------------------------------------------------
  
  DeepgramService({
    this.language = 'fr',
    this.model = 'nova-3',
    this.punctuate = true,
    this.smartFormat = true,
    this.interimResults = true,
    this.sampleRate = 16000,
  });
  
  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------
  
  bool get isListening => _isListening;
  String get fullTranscript => _fullTranscript;
  String get currentPartial => _currentPartial;
  double get confidence => _confidence;
  
  /// Texte complet incluant le partiel en cours
  String get displayText {
    if (_currentPartial.isEmpty) return _fullTranscript;
    if (_fullTranscript.isEmpty) return _currentPartial;
    return '$_fullTranscript $_currentPartial';
  }
  
  // ---------------------------------------------------------------------------
  // API Publique
  // ---------------------------------------------------------------------------
  
  /// Démarre l'écoute et la transcription
  Future<bool> startListening() async {
    if (_isListening) return true;
    
    try {
      // Vérifier les permissions
      if (!await _recorder.hasPermission()) {
        onError?.call('Permission microphone refusée');
        return false;
      }
      
      // Réinitialiser l'état
      _fullTranscript = '';
      _currentPartial = '';
      _confidence = 0.0;
      
      // Connecter au WebSocket Deepgram
      await _connectWebSocket();
      
      // Démarrer l'enregistrement audio en streaming
      await _startAudioStream();
      
      _isListening = true;
      debugPrint('🎙️ Deepgram: Écoute démarrée');
      
      return true;
    } catch (e) {
      debugPrint('❌ Deepgram: Erreur démarrage - $e');
      onError?.call('Erreur démarrage: $e');
      await stopListening();
      return false;
    }
  }
  
  /// Arrête l'écoute et la transcription
  Future<void> stopListening() async {
    if (!_isListening && _channel == null) return;
    
    debugPrint('⏹️ Deepgram: Arrêt en cours...');
    
    // Arrêter l'enregistrement audio
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    
    try {
      await _recorder.stop();
    } catch (e) {
      debugPrint('⚠️ Deepgram: Erreur arrêt recorder - $e');
    }
    
    // Fermer le WebSocket
    try {
      await _channel?.sink.close();
    } catch (e) {
      debugPrint('⚠️ Deepgram: Erreur fermeture WebSocket - $e');
    }
    _channel = null;
    
    // Finaliser le transcript si un partiel était en cours
    if (_currentPartial.isNotEmpty) {
      if (_fullTranscript.isNotEmpty) _fullTranscript += ' ';
      _fullTranscript += _currentPartial;
      _currentPartial = '';
    }
    
    _isListening = false;
    onDisconnected?.call();
    
    debugPrint('✅ Deepgram: Arrêté - Transcript final: $_fullTranscript');
  }
  
  /// Réinitialise la transcription
  void reset() {
    _fullTranscript = '';
    _currentPartial = '';
    _confidence = 0.0;
  }
  
  /// Libère les ressources
  Future<void> dispose() async {
    await stopListening();
    _recorder.dispose();
  }
  
  // ---------------------------------------------------------------------------
  // Connexion WebSocket
  // ---------------------------------------------------------------------------
  
  Future<void> _connectWebSocket() async {
    // Construire l'URL avec les paramètres
    final params = {
      'model': model,
      'language': language,
      'punctuate': punctuate.toString(),
      'smart_format': smartFormat.toString(),
      'interim_results': interimResults.toString(),
      'encoding': 'linear16',
      'sample_rate': sampleRate.toString(),
      'channels': '1',
    };
    
    final queryString = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    
    final wsUrl = '$_wsBaseUrl?$queryString';
    
    debugPrint('🔌 Deepgram: Connexion à $wsUrl');
    
    // Créer la connexion WebSocket avec l'authentification via Header
    // Deepgram requiert le header Authorization: Token <api_key>
    try {
      if (!kIsWeb) {
        // Mobile/Desktop: utiliser IOWebSocketChannel avec headers
        final socket = await WebSocket.connect(
          wsUrl,
          headers: {'Authorization': 'Token $_apiKey'},
        );
        _channel = IOWebSocketChannel(socket);
        debugPrint('✅ Deepgram: WebSocket connecté (IOWebSocketChannel)');
      } else {
        // Web: utiliser WebSocketChannel standard (limité, pas de headers custom)
        // Note: Sur web, l'auth par header n'est pas supportée
        _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
        debugPrint('⚠️ Deepgram: WebSocket web (auth limitée)');
      }
    } catch (e) {
      debugPrint('❌ Deepgram WebSocket error: $e');
      throw Exception('Erreur WebSocket: $e');
    }
    
    // Écouter les messages entrants
    _channel!.stream.listen(
      _onMessage,
      onError: _onWebSocketError,
      onDone: _onWebSocketDone,
    );
    
    onConnected?.call();
  }
  
  void _onMessage(dynamic message) {
    try {
      final data = json.decode(message as String) as Map<String, dynamic>;
      
      // Vérifier si c'est une erreur
      if (data.containsKey('error')) {
        onError?.call(data['error'].toString());
        return;
      }
      
      // Parser la réponse de transcription
      final channel = data['channel'] as Map<String, dynamic>?;
      if (channel != null) {
        final alternatives = channel['alternatives'] as List<dynamic>?;
        if (alternatives != null && alternatives.isNotEmpty) {
          final alt = alternatives[0] as Map<String, dynamic>;
          final transcript = alt['transcript'] as String? ?? '';
          final conf = (alt['confidence'] as num?)?.toDouble() ?? 0.0;
          
          // Vérifier si c'est un résultat final ou partiel
          final isFinal = data['is_final'] as bool? ?? true;
          final speechFinal = data['speech_final'] as bool? ?? false;
          
          if (transcript.isNotEmpty) {
            _confidence = conf;
            
            if (isFinal || speechFinal) {
              // Résultat final - ajouter au transcript complet
              if (_fullTranscript.isNotEmpty) _fullTranscript += ' ';
              _fullTranscript += transcript;
              _currentPartial = '';
              
              debugPrint('📝 [FINAL] $transcript (conf: ${(conf * 100).toStringAsFixed(1)}%)');
            } else {
              // Résultat partiel
              _currentPartial = transcript;
              
              debugPrint('📝 [PARTIAL] $transcript');
            }
            
            onTranscript?.call(transcript, isFinal || speechFinal);
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Deepgram: Erreur parsing message - $e');
    }
  }
  
  void _onWebSocketError(dynamic error) {
    debugPrint('❌ Deepgram WebSocket error: $error');
    onError?.call('Erreur WebSocket: $error');
  }
  
  void _onWebSocketDone() {
    debugPrint('🔌 Deepgram: WebSocket fermé');
    if (_isListening) {
      // Reconnexion automatique si on était en écoute
      _isListening = false;
      onDisconnected?.call();
    }
  }
  
  // ---------------------------------------------------------------------------
  // Streaming Audio
  // ---------------------------------------------------------------------------
  
  Future<void> _startAudioStream() async {
    // Configuration pour PCM 16-bit, 16kHz, mono
    const config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
      autoGain: true,
      echoCancel: true,
      noiseSuppress: true,
    );
    
    // Démarrer le stream audio
    final stream = await _recorder.startStream(config);
    
    // Envoyer chaque chunk au WebSocket
    _audioSubscription = stream.listen(
      (Uint8List audioData) {
        if (_channel != null && _isListening) {
          _channel!.sink.add(audioData);
        }
      },
      onError: (error) {
        debugPrint('❌ Deepgram: Erreur audio stream - $error');
        onError?.call('Erreur audio: $error');
      },
    );
    
    debugPrint('🎤 Deepgram: Stream audio démarré');
  }
}
