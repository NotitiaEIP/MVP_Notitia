import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notitia/services/ai_client.dart';
import 'package:notitia/services/open_stt_service.dart';

const _rate = 16000;

Uint8List _pcm(int ms, {bool speech = true}) {
  final n = _rate * ms ~/ 1000;
  final data = ByteData(n * 2);
  for (var i = 0; i < n; i++) {
    data.setInt16(
      i * 2,
      speech ? (4000 * sin(2 * pi * 220 * i / _rate)).round() : 0,
      Endian.little,
    );
  }
  return data.buffer.asUint8List();
}

/// 3 s de parole suivies d'une pause : un segment par appel.
Uint8List _utterance() =>
    (BytesBuilder()
          ..add(_pcm(3000))
          ..add(_pcm(1000, speech: false)))
        .takeBytes();

/// Valeur d'un champ texte dans le corps multipart reçu.
String? _field(http.Request req, String name) {
  final body = utf8.decode(req.bodyBytes, allowMalformed: true);
  // Les champs non ASCII reçoivent des en-têtes en plus (content-type…)
  final match = RegExp(
    'name="$name"(?:\r\n[^\r]+)*\r\n\r\n([^\r]*)\r\n',
  ).firstMatch(body);
  return match?.group(1);
}

void main() {
  group('OpenSttService', () {
    test('transcrit les segments dans l\'ordre et passe le contexte', () async {
      final replies = ['Bonjour à tous.', 'On commence la réunion.'];
      final prompts = <String?>[];
      var call = 0;
      final ai = AiClient(
        httpClient: MockClient((req) async {
          prompts.add(_field(req, 'prompt'));
          // Le 1er segment répond plus lentement : l'ordre doit tenir quand même
          final i = call++;
          await Future.delayed(Duration(milliseconds: i == 0 ? 50 : 0));
          return http.Response(
            jsonEncode({'text': replies[i]}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
        baseUrl: 'http://gateway.test',
        apiKey: 'sk-test',
      );
      final events = <String>[];
      final stt = OpenSttService(client: ai)
        ..onTranscript = (t, isFinal) =>
            events.add('${isFinal ? 'F' : 'P'}:$t');

      await stt.processAudio(
        (BytesBuilder()
              ..add(_utterance())
              ..add(_utterance()))
            .takeBytes(),
        end: true,
      );

      expect(stt.fullTranscript, 'Bonjour à tous. On commence la réunion.');
      expect(prompts, [null, 'Bonjour à tous.']);
      expect(events.where((e) => e.startsWith('F:')), [
        'F:Bonjour à tous.',
        'F:On commence la réunion.',
      ]);
      expect(stt.isTranscribing, isFalse);
    });

    test('n\'envoie rien pour du silence', () async {
      var calls = 0;
      final ai = AiClient(
        httpClient: MockClient((_) async {
          calls++;
          return http.Response('{"text":"x"}', 200);
        }),
        baseUrl: 'http://gateway.test',
        apiKey: 'sk-test',
      );
      final stt = OpenSttService(client: ai);
      await stt.processAudio(_pcm(10000, speech: false), end: true);
      expect(calls, 0);
      expect(stt.fullTranscript, isEmpty);
    });

    test('signale une seule erreur si la passerelle échoue', () async {
      final ai = AiClient(
        httpClient: MockClient(
          (_) async => http.Response('{"error":{"message":"budget"}}', 400),
        ),
        baseUrl: 'http://gateway.test',
        apiKey: 'sk-test',
      );
      final errors = <String>[];
      final stt = OpenSttService(client: ai)..onError = errors.add;
      await stt.processAudio(
        (BytesBuilder()
              ..add(_utterance())
              ..add(_utterance()))
            .takeBytes(),
        end: true,
      );
      expect(errors, ['budget']);
      expect(stt.fullTranscript, isEmpty);
    });

    test(
      'transcribeRecording découpe un long enregistrement du widget',
      () async {
        final prompts = <String?>[];
        var call = 0;
        final ai = AiClient(
          httpClient: MockClient((req) async {
            prompts.add(_field(req, 'prompt'));
            return http.Response('{"text":"Partie ${++call}."}', 200);
          }),
          baseUrl: 'http://gateway.test',
          apiKey: 'sk-test',
        );
        // 6 min de parole continue → coupe forcée à 5 min → 2 segments
        final text = await OpenSttService.transcribeRecording(
          _pcm(6 * 60 * 1000),
          client: ai,
        );
        expect(text, 'Partie 1. Partie 2.');
        expect(prompts, [null, 'Partie 1.']);
      },
    );

    test('filtre les phrases inventées par Whisper sur du silence', () {
      expect(
        OpenSttService.cleanTranscript(
          "Sous-titres réalisés par la communauté d'Amara.org",
        ),
        '',
      );
      expect(OpenSttService.cleanTranscript("Merci d'avoir regardé !"), '');
      expect(
        OpenSttService.cleanTranscript('  Le budget est validé. '),
        'Le budget est validé.',
      );
    });
  });

  test(
    'AiClient.transcribe envoie le WAV en multipart avec modèle et langue',
    () async {
      late http.Request sent;
      final ai = AiClient(
        httpClient: MockClient((req) async {
          sent = req;
          return http.Response('{"text":" Salut "}', 200);
        }),
        baseUrl: 'http://gateway.test',
        apiKey: 'sk-test',
      );
      final text = await ai.transcribe(
        Uint8List.fromList([1, 2, 3]),
        language: 'fr',
      );
      expect(text, 'Salut');
      expect(sent.url.path, '/v1/audio/transcriptions');
      expect(sent.headers['Authorization'], 'Bearer sk-test');
      expect(_field(sent, 'model'), 'notitia-transcribe');
      expect(_field(sent, 'language'), 'fr');
      expect(_field(sent, 'prompt'), isNull);
      expect(
        utf8.decode(sent.bodyBytes, allowMalformed: true),
        contains('filename="audio.wav"'),
      );
    },
  );
}
