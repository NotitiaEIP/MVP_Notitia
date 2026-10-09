import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notitia/services/ai_client.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, dynamic> _chatBody(String content) => {
  'model': 'notitia-smart',
  'choices': [
    {
      'message': {'role': 'assistant', 'content': content},
    },
  ],
  'usage': {'prompt_tokens': 12, 'completion_tokens': 34},
};

AiClient _client(MockClientHandler handler) => AiClient(
  httpClient: MockClient(handler),
  baseUrl: 'http://gateway.test/',
  apiKey: 'sk-test',
);

void main() {
  group('chat', () {
    test(
      'envoie modèle, system, JSON mode et clé ; renvoie le contenu',
      () async {
        late http.Request sent;
        final ai = _client((req) async {
          sent = req;
          return _json(_chatBody('{"ok": true}'));
        });

        final result = await ai.chat(
          model: 'notitia-smart',
          system: 'Tu es Notitia',
          messages: [
            {'role': 'user', 'content': 'Bonjour'},
          ],
          jsonMode: true,
        );

        expect(sent.url.toString(), 'http://gateway.test/v1/chat/completions');
        expect(sent.headers['Authorization'], 'Bearer sk-test');
        final body = jsonDecode(sent.body) as Map<String, dynamic>;
        expect(body['model'], 'notitia-smart');
        expect(body['response_format'], {'type': 'json_object'});
        expect((body['messages'] as List).first, {
          'role': 'system',
          'content': 'Tu es Notitia',
        });
        expect(result.content, '{"ok": true}');
        expect(result.inputTokens, 12);
        expect(result.outputTokens, 34);
      },
    );

    test('retire les blocs <think> et décode l\'UTF-8', () async {
      final ai = _client(
        (_) async => _json(_chatBody('<think>hmm…</think>\nRéunion décalée')),
      );
      expect(await ai.complete(model: 'm', prompt: 'x'), 'Réunion décalée');
    });

    test('réessaie sur 503 puis réussit', () async {
      var calls = 0;
      final ai = _client((_) async {
        calls++;
        return calls == 1
            ? _json({'error': 'down'}, 503)
            : _json(_chatBody('ok'));
      });
      expect(await ai.complete(model: 'm', prompt: 'x'), 'ok');
      expect(calls, 2);
    });

    test('ne réessaie pas sur 401 et remonte le message', () async {
      var calls = 0;
      final ai = _client((_) async {
        calls++;
        return _json({
          'error': {'message': 'Invalid proxy server token'},
        }, 401);
      });
      await expectLater(
        ai.complete(model: 'm', prompt: 'x'),
        throwsA(
          isA<AiException>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.message, 'message', contains('Invalid')),
        ),
      );
      expect(calls, 1);
    });

    test('échoue sans clé configurée', () async {
      final ai = AiClient(
        httpClient: MockClient((_) async => _json({})),
        baseUrl: 'http://gateway.test',
        apiKey: '',
      );
      expect(ai.isConfigured, isFalse);
      await expectLater(
        ai.complete(model: 'm', prompt: 'x'),
        throwsA(isA<AiException>()),
      );
    });
  });

  group('embed', () {
    test('renvoie les vecteurs dans l\'ordre des entrées', () async {
      late Map<String, dynamic> body;
      final ai = _client((req) async {
        body = jsonDecode(req.body) as Map<String, dynamic>;
        return _json({
          'data': [
            {
              'index': 1,
              'embedding': [0.3, 0.4],
            },
            {
              'index': 0,
              'embedding': [0.1, 0.2],
            },
          ],
        });
      });

      final vectors = await ai.embed(['a', 'b'], model: 'emb', dimensions: 2);

      expect(body, {
        'model': 'emb',
        'input': ['a', 'b'],
        'dimensions': 2,
      });
      expect(vectors, [
        [0.1, 0.2],
        [0.3, 0.4],
      ]);
    });
  });

  group('search', () {
    test('mappe les résultats et ignore les URL invalides', () async {
      late http.Request sent;
      final ai = _client((req) async {
        sent = req;
        return _json({
          'object': 'search',
          'results': [
            {'title': 'A', 'url': 'https://a.fr', 'snippet': 's'},
            {'title': 'B', 'url': 'javascript:alert(1)'},
          ],
        });
      });

      final results = await ai.search('ia open source');

      expect(sent.url.path, '/v1/search/brave-search');
      expect(results, hasLength(1));
      expect(results.first.url, 'https://a.fr');
    });

    test('renvoie une liste vide en cas d\'erreur', () async {
      final ai = _client((_) async => _json({'error': 'bad key'}, 400));
      expect(await ai.search('x'), isEmpty);
    });
  });

  test('extractJsonObject tolère les fences et le texte autour', () {
    expect(
      AiClient.extractJsonObject('Voici :\n```json\n{"a": 1}\n```'),
      '{"a": 1}',
    );
    expect(AiClient.extractJsonObject('Résultat {"a": 1}'), '{"a": 1}');
  });
}
