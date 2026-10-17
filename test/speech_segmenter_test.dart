import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notitia/services/speech_segmenter.dart';

const _rate = 16000;

/// PCM 16 bits : sinus (voix simulée) ou quasi-silence.
Uint8List _pcm(int ms, {bool speech = true}) {
  final n = _rate * ms ~/ 1000;
  final data = ByteData(n * 2);
  final rnd = Random(1);
  for (var i = 0; i < n; i++) {
    final v = speech
        ? (4000 * sin(2 * pi * 220 * i / _rate)).round()
        : rnd.nextInt(60) - 30;
    data.setInt16(i * 2, v, Endian.little);
  }
  return data.buffer.asUint8List();
}

int _ms(Uint8List bytes) => bytes.length ~/ 2 * 1000 ~/ _rate;

void main() {
  test('le silence seul ne produit aucun segment', () {
    final s = SpeechSegmenter();
    expect(s.add(_pcm(20000, speech: false)), isEmpty);
    expect(s.flush(), isNull);
  });

  test('parole puis pause → un segment coupé sur la pause', () {
    final s = SpeechSegmenter();
    final out = [...s.add(_pcm(3000)), ...s.add(_pcm(1000, speech: false))];
    expect(out, hasLength(1));
    // 3 s de parole + ~0,7 s de pause avant la coupe
    expect(_ms(out.single), inInclusiveRange(3600, 3800));
  });

  test('une pause trop tôt ne coupe pas (segment minimum)', () {
    final s = SpeechSegmenter();
    final out = [
      ...s.add(_pcm(1000)),
      ...s.add(_pcm(800, speech: false)),
      ...s.add(_pcm(500)),
    ];
    expect(out, isEmpty);
    expect(_ms(s.flush()!), inInclusiveRange(2200, 2400));
  });

  test('parole continue → coupe forcée à la durée maximale', () {
    final s = SpeechSegmenter();
    final out = s.add(_pcm(32000));
    expect(out, hasLength(2));
    expect(_ms(out.first), 15000);
  });

  test('les morceaux arbitraires du micro sont recollés correctement', () {
    final s = SpeechSegmenter();
    final audio = BytesBuilder()
      ..add(_pcm(3000))
      ..add(_pcm(1000, speech: false));
    final bytes = audio.takeBytes();
    final out = <Uint8List>[];
    for (var i = 0; i < bytes.length; i += 1234) {
      out.addAll(
        s.add(Uint8List.sublistView(bytes, i, min(i + 1234, bytes.length))),
      );
    }
    expect(out, hasLength(1));
  });

  test('toWav produit un en-tête WAV PCM 16 kHz mono valide', () {
    final pcm = _pcm(100);
    final wav = SpeechSegmenter.toWav(pcm);
    final h = ByteData.sublistView(wav);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(h.getUint16(22, Endian.little), 1);
    expect(h.getUint32(24, Endian.little), 16000);
    expect(h.getUint32(40, Endian.little), pcm.length);
    expect(wav.length, 44 + pcm.length);
  });
}
