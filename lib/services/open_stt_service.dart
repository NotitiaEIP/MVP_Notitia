// =============================================================================
// NOTITIA — Transcription open source (Whisper large-v3-turbo via la passerelle)
//
// Le micro est découpé en segments sur les pauses (SpeechSegmenter) ; chaque
// segment est envoyé à Whisper, dans l'ordre, et son texte affiché dès qu'il
// revient (quelques secondes de décalage, sans clé de fournisseur dans l'app).
// =============================================================================

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import 'ai_client.dart';
import 'live_transcriber.dart';
import 'speech_segmenter.dart';

class OpenSttService implements LiveTranscriber {
  OpenSttService({
    this.language = 'fr',
    AiClient? client,
    AudioRecorder? recorder,
  }) : _ai = client ?? AiClient.instance,
       _recorder = recorder;

  /// Code langue ISO (fr, en…) transmis à Whisper.
  final String language;

  final AiClient _ai;

  /// Créé au premier démarrage : on ne réserve pas le micro avant.
  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _audioSubscription;
  SpeechSegmenter _segmenter = SpeechSegmenter();

  /// File d'attente : les segments sont transcrits un par un, dans l'ordre.
  Future<void> _queue = Future.value();
  int _inFlight = 0;

  bool _isListening = false;
  String _fullTranscript = '';
  bool _errorReported = false;

  @override
  void Function(String text, bool isFinal)? onTranscript;
  @override
  void Function(String error)? onError;
  @override
  void Function()? onConnected;
  @override
  void Function()? onDisconnected;

  @override
  bool get isListening => _isListening;
  @override
  String get fullTranscript => _fullTranscript;
  @override
  double get confidence => 0;

  /// Vrai tant qu'un segment attend sa transcription.
  bool get isTranscribing => _inFlight > 0;

  @override
  Future<bool> startListening() async {
    if (_isListening) return true;
    try {
      final recorder = _recorder ??= AudioRecorder();
      if (!await recorder.hasPermission()) {
        onError?.call('Permission microphone refusée');
        return false;
      }
      reset();
      final stream = await recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
        ),
      );
      _audioSubscription = stream.listen(
        (chunk) => _segmenter.add(chunk).forEach(_enqueue),
        onError: (e) => onError?.call('Erreur audio: $e'),
      );
      _isListening = true;
      onConnected?.call();
      debugPrint('🎙️ OpenSTT: écoute démarrée (Whisper, $language)');
      return true;
    } catch (e) {
      debugPrint('❌ OpenSTT: erreur démarrage - $e');
      onError?.call('Erreur démarrage: $e');
      await stopListening();
      return false;
    }
  }

  @override
  Future<void> stopListening() async {
    if (!_isListening && _audioSubscription == null) return;
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    try {
      await _recorder?.stop();
    } catch (e) {
      debugPrint('⚠️ OpenSTT: erreur arrêt micro - $e');
    }
    final last = _segmenter.flush();
    if (last != null) _enqueue(last);
    _isListening = false;

    // Le transcript n'est complet qu'une fois tous les segments revenus
    await _queue;
    onDisconnected?.call();
    debugPrint('✅ OpenSTT: arrêté - $_fullTranscript');
  }

  @override
  void reset() {
    _segmenter = SpeechSegmenter();
    _fullTranscript = '';
    _errorReported = false;
  }

  @override
  Future<void> dispose() async {
    await stopListening();
    await _recorder?.dispose();
    _recorder = null;
  }

  /// Transcrit un enregistrement complet (PCM 16 bits mono 16 kHz), par
  /// morceaux de 5 minutes maximum coupés sur les pauses. Lève une exception
  /// si la passerelle est injoignable, pour pouvoir réessayer plus tard.
  static Future<String> transcribeRecording(
    Uint8List pcm, {
    String language = 'fr',
    AiClient? client,
  }) async {
    final ai = client ?? AiClient.instance;
    final segmenter = SpeechSegmenter(
      minSegmentMs: 60000,
      maxSegmentMs: 300000,
    );
    final segments = [...segmenter.add(pcm), ?segmenter.flush()];
    var transcript = '';
    for (final segment in segments) {
      final text = cleanTranscript(
        await ai.transcribe(
          SpeechSegmenter.toWav(segment),
          language: language,
          prompt: transcript.isEmpty
              ? null
              : transcript.substring(max(0, transcript.length - 200)),
        ),
      );
      if (text.isNotEmpty) {
        transcript = transcript.isEmpty ? text : '$transcript $text';
      }
    }
    return transcript;
  }

  /// Injecte de l'audio sans micro (tests) ; [end] termine le dernier segment.
  @visibleForTesting
  Future<void> processAudio(Uint8List pcm, {bool end = false}) {
    _segmenter.add(pcm).forEach(_enqueue);
    if (end) {
      final last = _segmenter.flush();
      if (last != null) _enqueue(last);
    }
    return _queue;
  }

  void _enqueue(Uint8List pcm) {
    _inFlight++;
    onTranscript?.call('…', false);
    _queue = _queue.then((_) => _transcribe(pcm));
  }

  Future<void> _transcribe(Uint8List pcm) async {
    try {
      final text = cleanTranscript(
        await _ai.transcribe(
          SpeechSegmenter.toWav(pcm),
          language: language,
          prompt: _contextPrompt(),
        ),
      );
      _inFlight--;
      if (text.isNotEmpty) {
        _fullTranscript = _fullTranscript.isEmpty
            ? text
            : '$_fullTranscript $text';
        onTranscript?.call(text, true);
        if (_inFlight > 0) onTranscript?.call('…', false);
      } else if (_inFlight == 0) {
        onTranscript?.call('', false);
      }
    } catch (e) {
      _inFlight--;
      debugPrint('❌ OpenSTT: segment non transcrit - $e');
      if (!_errorReported) {
        _errorReported = true;
        onError?.call(
          e is AiException ? e.message : 'Transcription indisponible',
        );
      }
      if (_inFlight == 0) onTranscript?.call('', false);
    }
  }

  /// Fin du texte déjà transcrit : aide Whisper à garder le fil entre segments.
  String? _contextPrompt() {
    if (_fullTranscript.isEmpty) return null;
    return _fullTranscript.length <= 200
        ? _fullTranscript
        : _fullTranscript.substring(_fullTranscript.length - 200);
  }

  /// Phrases que Whisper invente sur du bruit ou du silence (sous-titres YouTube).
  static final List<RegExp> _hallucinations = [
    RegExp(r'amara\.org', caseSensitive: false),
    RegExp(r'sous-titr(es|age)', caseSensitive: false),
    RegExp(r"^merci d'avoir regardé", caseSensitive: false),
    RegExp(r'^abonnez-vous', caseSensitive: false),
    RegExp(r'^thanks? for watching', caseSensitive: false),
  ];

  @visibleForTesting
  static String cleanTranscript(String text) {
    final t = text.trim();
    if (t.isEmpty || _hallucinations.any((r) => r.hasMatch(t))) return '';
    return t;
  }
}
