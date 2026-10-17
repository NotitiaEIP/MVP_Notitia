// =============================================================================
// NOTITIA — Découpage de la parole en segments (détection de silence)
//
// Whisper transcrit des fichiers, pas un flux continu. On découpe donc le flux
// micro (PCM 16 bits mono) en segments qui se terminent sur une pause, pour
// afficher le texte au fil de l'eau sans couper les mots. Les segments sans
// parole sont jetés : sur du silence, Whisper a tendance à inventer du texte.
// =============================================================================

import 'dart:math';
import 'dart:typed_data';

class SpeechSegmenter {
  SpeechSegmenter({
    this.sampleRate = 16000,
    this.frameMs = 30,
    this.minSegmentMs = 2500,
    this.maxSegmentMs = 15000,
    this.silenceToCutMs = 700,
    this.minSpeechMs = 300,
    this.minSpeechRms = 300,
  });

  final int sampleRate;
  final int frameMs;

  /// Durée minimale d'un segment avant de pouvoir couper sur un silence.
  final int minSegmentMs;

  /// Coupe forcée au-delà (parole continue).
  final int maxSegmentMs;

  /// Pause nécessaire pour terminer un segment.
  final int silenceToCutMs;

  /// En dessous de cette quantité de parole, le segment est jeté.
  final int minSpeechMs;

  /// Énergie minimale (RMS, échelle int16) pour considérer qu'il y a de la voix.
  final double minSpeechRms;

  int get _frameBytes => sampleRate * frameMs ~/ 1000 * 2;

  final BytesBuilder _segment = BytesBuilder(copy: false);
  Uint8List _pending = Uint8List(0);
  double _noiseFloor = 0;
  int _segmentMs = 0;
  int _speechMs = 0;
  int _trailingSilenceMs = 0;

  /// Ajoute de l'audio ; renvoie les segments terminés (avec parole).
  List<Uint8List> add(Uint8List pcm) {
    final out = <Uint8List>[];
    final data = _pending.isEmpty
        ? pcm
        : (BytesBuilder(copy: false)
                ..add(_pending)
                ..add(pcm))
              .takeBytes();
    var offset = 0;
    while (offset + _frameBytes <= data.length) {
      final frame = Uint8List.sublistView(data, offset, offset + _frameBytes);
      offset += _frameBytes;
      final segment = _addFrame(frame);
      if (segment != null) out.add(segment);
    }
    _pending = Uint8List.fromList(Uint8List.sublistView(data, offset));
    return out;
  }

  /// Termine le segment en cours (fin d'enregistrement).
  Uint8List? flush() {
    if (_pending.isNotEmpty) {
      _segment.add(_pending);
      _pending = Uint8List(0);
    }
    return _cut();
  }

  Uint8List? _addFrame(Uint8List frame) {
    final rms = _rms(frame);
    final threshold = max(minSpeechRms, _noiseFloor * 2.5);
    final isSpeech = rms >= threshold;

    if (!isSpeech) {
      // Le bruit de fond s'adapte lentement (pièce calme ou bruyante)
      _noiseFloor = _noiseFloor == 0 ? rms : _noiseFloor * 0.95 + rms * 0.05;
    }

    _segment.add(frame);
    _segmentMs += frameMs;
    if (isSpeech) {
      _speechMs += frameMs;
      _trailingSilenceMs = 0;
    } else {
      _trailingSilenceMs += frameMs;
    }

    final pauseCut =
        _segmentMs >= minSegmentMs && _trailingSilenceMs >= silenceToCutMs;
    if (pauseCut || _segmentMs >= maxSegmentMs) return _cut();
    return null;
  }

  Uint8List? _cut() {
    final bytes = _segment.takeBytes();
    final hasSpeech = _speechMs >= minSpeechMs;
    _segmentMs = 0;
    _speechMs = 0;
    _trailingSilenceMs = 0;
    return hasSpeech && bytes.isNotEmpty ? bytes : null;
  }

  static double _rms(Uint8List frame) {
    final samples = ByteData.sublistView(frame);
    final count = frame.length ~/ 2;
    if (count == 0) return 0;
    var sum = 0.0;
    for (var i = 0; i < count; i++) {
      final s = samples.getInt16(i * 2, Endian.little);
      sum += s * s;
    }
    return sqrt(sum / count);
  }

  /// Ajoute un en-tête WAV (PCM 16 bits mono) au flux brut.
  static Uint8List toWav(Uint8List pcm, {int sampleRate = 16000}) {
    final header = ByteData(44);
    void ascii(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        header.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    header.setUint32(4, 36 + pcm.length, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    header.setUint32(16, 16, Endian.little); // taille du bloc fmt
    header.setUint16(20, 1, Endian.little); // PCM
    header.setUint16(22, 1, Endian.little); // mono
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * 2, Endian.little); // octets / s
    header.setUint16(32, 2, Endian.little); // octets / échantillon
    header.setUint16(34, 16, Endian.little); // bits
    ascii(36, 'data');
    header.setUint32(40, pcm.length, Endian.little);
    return (BytesBuilder(copy: false)
          ..add(header.buffer.asUint8List())
          ..add(pcm))
        .takeBytes();
  }
}
