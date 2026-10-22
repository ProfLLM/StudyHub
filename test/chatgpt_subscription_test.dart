import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jose/jose.dart';
import 'package:studyhub/ai/chatgpt_subscription_provider.dart';

void main() {
  final now = DateTime.utc(2026, 10, 22);
  final redirect = Uri.parse('http://127.0.0.1:12345/auth/callback');

  test(
    'OAuth rejects substituted state, client, duplicate code and callback path',
    () {
      for (final query in [
        'state=wrong&code=c&client_id=oaiapp_test',
        'state=s&code=c&client_id=other',
        'state=s&code=a&code=b&client_id=oaiapp_test',
      ]) {
        expect(
          () => validateChatGptCallback(
            redirect.replace(query: query),
            redirect: redirect,
            state: 's',
            savedClientId: 'oaiapp_test',
          ),
          throwsA(isA<EnrichmentException>()),
        );
      }
      expect(
        () => validateChatGptCallback(
          redirect.replace(
            path: '/callback',
            query: 'state=s&code=c&client_id=oaiapp_test',
          ),
          redirect: redirect,
          state: 's',
        ),
        throwsA(isA<EnrichmentException>()),
      );
      expect(
        validateChatGptCallback(
          redirect.replace(query: 'state=s&code=c&client_id=oaiapp_test'),
          redirect: redirect,
          state: 's',
        ).clientId,
        'oaiapp_test',
      );
    },
  );

  test('ID token must match issuer, account audience, nonce and lifetime', () {
    final claims = {
      'iss': 'https://auth.openai.com',
      'aud': 'oaiapp_test',
      'sub': 'learner',
      'nonce': 'n',
      'exp': now.millisecondsSinceEpoch ~/ 1000 + 3600,
    };
    validateChatGptClaims(
      claims,
      clientId: 'oaiapp_test',
      nonce: 'n',
      now: now,
    );
    for (final invalid in [
      {'iss': 'https://attacker.invalid'},
      {'aud': 'another-client'},
      {'nonce': 'wrong'},
      {'exp': 0},
      {'sub': ''},
    ]) {
      expect(
        () => validateChatGptClaims(
          {...claims, ...invalid},
          clientId: 'oaiapp_test',
          nonce: 'n',
          now: now,
        ),
        throwsA(isA<EnrichmentException>()),
      );
    }
  });

  test('real RSA signature verified; forged or unsigned JWT rejected', () async {
    final key = JsonWebKey.generate('RS256', keyBitLength: 2048);
    final public = Map<String, dynamic>.from(
      key.toJson(),
    )..removeWhere((key, _) => ['d', 'p', 'q', 'dp', 'dq', 'qi'].contains(key));
    final builder = JsonWebSignatureBuilder()
      ..jsonContent = {'sub': 'synthetic'};
    builder.addRecipient(key, algorithm: 'RS256');
    final token = builder.build().toCompactSerialization();
    expect(
      (await verifyChatGptIdTokenSignature(token, {
        'keys': [public],
      }))['sub'],
      'synthetic',
    );
    final parts = token.split('.');
    parts[1] = base64Url
        .encode(utf8.encode('{"sub":"forged"}'))
        .replaceAll('=', '');
    await expectLater(
      verifyChatGptIdTokenSignature(parts.join('.'), {
        'keys': [public],
      }),
      throwsA(anything),
    );
    final unsigned =
        '${base64Url.encode(utf8.encode('{"alg":"none"}')).replaceAll('=', '')}.${parts[1]}.';
    await expectLater(
      verifyChatGptIdTokenSignature(unsigned, {
        'keys': [public],
      }),
      throwsA(anything),
    );
  });

  test('SSE handles UTF8 chunks and requires completed terminal event', () async {
    final bytes = utf8.encode(
      '${event('response.output_text.delta', delta: '<html>α</html>')}${event('response.completed')}',
    );
    expect(
      await readChatGptHtmlStream(
        Stream.fromIterable(bytes.map((byte) => [byte])),
      ),
      '<html>α</html>',
    );
    await expectLater(
      readChatGptHtmlStream(
        Stream.value(
          utf8.encode(
            event('response.output_text.delta', delta: '<html>partial'),
          ),
        ),
      ),
      throwsA(isA<EnrichmentException>()),
    );
  });

  test('SSE failure after partial output never returns a rendition', () async {
    await expectLater(
      readChatGptHtmlStream(
        Stream.value(
          utf8.encode(
            '${event('response.output_text.delta', delta: '<html>partial')}${event('response.failed')}',
          ),
        ),
      ),
      throwsA(isA<EnrichmentException>()),
    );
    await expectLater(
      readChatGptHtmlStream(
        Stream.value(utf8.encode(event('response.completed'))),
      ),
      throwsA(isA<EnrichmentException>()),
    );
  });

  test('only account-visible supported models can be selected', () {
    expect(
      selectChatGptModel({
        'models': [
          {'slug': 'gpt-6.1-sol', 'visibility': 'hide'},
          {'slug': 'gpt-6-sol', 'visibility': 'list'},
        ],
      }),
      'gpt-6-sol',
    );
    expect(
      () => selectChatGptModel({
        'models': [
          {'slug': 'unknown', 'visibility': 'list'},
        ],
      }),
      throwsA(isA<EnrichmentException>()),
    );
  });

  test(
    'generation sends ordered images with subscription contract only',
    () async {
      final native = FakeNative()..values['chatgpt.session'] = session(now);
      final transport = FakeTransport((method, uri, headers, body) async {
        expect(headers['Authorization'], 'Bearer synthetic-access');
        if (uri.path.endsWith('/models')) {
          return jsonResponse({
            'models': [
              {'slug': 'gpt-6.1-sol', 'visibility': 'list'},
            ],
          });
        }
        expect(uri.toString(), 'https://api.openai.com/v1/responses');
        final request = jsonDecode(body!) as Map;
        expect(request.keys.toSet(), {
          'model',
          'instructions',
          'input',
          'store',
          'stream',
        });
        expect(request['store'], false);
        expect(request['stream'], true);
        final content = request['input'][0]['content'] as List;
        expect(content[1]['image_url'], 'data:image/png;base64,AQ==');
        expect(content[2]['image_url'], 'data:image/png;base64,Ag==');
        return sseResponse();
      });
      final provider = ChatGptSubscriptionProvider(
        nativeAuth: native,
        transport: transport,
        now: () => now,
      );
      expect(
        await provider.generate(
          images: [
            Uint8List.fromList([1]),
            Uint8List.fromList([2]),
          ],
          lectureTitle: 'Synthetic',
          sourceNotes: '',
        ),
        '<html>done</html>',
      );
    },
  );

  test('expired session rotates refresh token before inference', () async {
    final native = FakeNative()
      ..values['chatgpt.session'] = session(
        now.subtract(const Duration(hours: 2)),
      );
    final transport = FakeTransport((method, uri, headers, body) async {
      if (uri.path.endsWith('/token')) {
        final fields = Uri.splitQueryString(body!);
        expect(fields['grant_type'], 'refresh_token');
        expect(fields['client_id'], 'oaiapp_test');
        return jsonResponse({
          'access_token': 'new-access',
          'refresh_token': 'rotated-refresh',
          'expires_in': 3600,
        });
      }
      expect(headers['Authorization'], 'Bearer new-access');
      if (uri.path.endsWith('/models')) {
        return jsonResponse({
          'models': [
            {'slug': 'gpt-6.1-sol', 'visibility': 'list'},
          ],
        });
      }
      return sseResponse();
    });
    final provider = ChatGptSubscriptionProvider(
      nativeAuth: native,
      transport: transport,
      now: () => now,
    );
    await provider.generate(
      images: [
        Uint8List.fromList([1]),
      ],
      lectureTitle: '',
      sourceNotes: '',
    );
    expect(
      jsonDecode(native.values['chatgpt.session']!)['refresh_token'],
      'rotated-refresh',
    );
  });

  test(
    'cancel interrupts an active response without publishing partial HTML',
    () async {
      final native = FakeNative()..values['chatgpt.session'] = session(now);
      final stream = StreamController<List<int>>();
      final reached = Completer<void>();
      final transport = FakeTransport((method, uri, headers, body) async {
        if (uri.path.endsWith('/models')) {
          return jsonResponse({
            'models': [
              {'slug': 'gpt-6.1-sol', 'visibility': 'list'},
            ],
          });
        }
        reached.complete();
        return ChatGptHttpResponse(200, stream.stream);
      });
      final provider = ChatGptSubscriptionProvider(
        nativeAuth: native,
        transport: transport,
        now: () => now,
      );
      final generation = provider.generate(
        images: [
          Uint8List.fromList([1]),
        ],
        lectureTitle: '',
        sourceNotes: '',
      );
      final assertion = expectLater(
        generation,
        throwsA(isA<EnrichmentException>()),
      );
      await reached.future;
      provider.cancel();
      await assertion;
      await stream.close();
    },
  );

  test(
    'full OAuth loopback registration validates identity before saving',
    () async {
      final native = FakeNative();
      late String nonce;
      native.open = (url) async {
        final query = Uri.parse(url).queryParameters;
        expect(query['client_id'], 'dynamic_agent_client');
        expect(query['code_challenge_method'], 'S256');
        expect(query['resource'], 'https://api.openai.com/v1');
        nonce = query['nonce']!;
        final target = Uri.parse(query['redirect_uri']!).replace(
          queryParameters: {
            'state': query['state']!,
            'client_id': 'oaiapp_test',
            'code': 'synthetic-code',
          },
        );
        final client = HttpClient();
        try {
          final response = await (await client.getUrl(target)).close();
          await response.drain<void>();
        } finally {
          client.close(force: true);
        }
      };
      final transport = FakeTransport((method, uri, headers, body) async {
        if (uri.path.endsWith('/jwks.json')) return jsonResponse({'keys': []});
        return jsonResponse({
          'access_token': 'synthetic-access',
          'refresh_token': 'synthetic-refresh',
          'id_token': 'synthetic-id',
          'scope': 'chatgpt.tokens.use.direct',
          'expires_in': 3600,
        });
      });
      final provider = ChatGptSubscriptionProvider(
        nativeAuth: native,
        transport: transport,
        now: () => now,
        verifyIdToken: (_, _) async => {
          'iss': 'https://auth.openai.com',
          'aud': 'oaiapp_test',
          'nonce': nonce,
          'sub': 'synthetic',
          'exp': now.millisecondsSinceEpoch ~/ 1000 + 3600,
        },
      );
      await provider.connect();
      expect(await provider.isConnected, true);
      expect(native.closed, true);
      expect(
        jsonDecode(native.values['chatgpt.registration']!)['client_id'],
        'oaiapp_test',
      );
    },
  );

  test(
    'OAuth browser cancellation closes local listener and browser',
    () async {
      final native = FakeNative()..open = (_) async {};
      final provider = ChatGptSubscriptionProvider(
        nativeAuth: native,
        transport: FakeTransport(
          (_, _, _, _) async => throw StateError('No request expected'),
        ),
      );
      final connecting = provider.connect();
      final assertion = expectLater(
        connecting,
        throwsA(isA<EnrichmentException>()),
      );
      await native.opened.future;
      native.onCancelled?.call();
      await assertion;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(native.closed, true);
      expect(native.values.containsKey('chatgpt.session'), false);
    },
  );
}

String event(String type, {String? delta}) =>
    'data: ${jsonEncode({'type': type, 'delta': ?delta})}\n\n';
ChatGptHttpResponse jsonResponse(Map<String, dynamic> value) =>
    ChatGptHttpResponse(200, Stream.value(utf8.encode(jsonEncode(value))));
ChatGptHttpResponse sseResponse() => ChatGptHttpResponse(
  200,
  Stream.value(
    utf8.encode(
      '${event('response.output_text.delta', delta: '<html>done</html>')}${event('response.completed')}',
    ),
  ),
);
String session(DateTime now) => jsonEncode({
  'access_token': 'synthetic-access',
  'refresh_token': 'synthetic-refresh',
  'scope': 'chatgpt.tokens.use.direct',
  'client_id': 'oaiapp_test',
  'subject': 'synthetic',
  'expires_at': now.add(const Duration(hours: 1)).millisecondsSinceEpoch,
});

class FakeNative extends ChatGptNativeAuth {
  final values = <String, String>{};
  final opened = Completer<void>();
  Future<void> Function(String)? open;
  bool closed = false;
  @override
  Future<void> openAuth(String url) async {
    opened.complete();
    await open?.call(url);
  }

  @override
  Future<void> closeAuth() async {
    closed = true;
  }

  @override
  Future<String?> readSecure(String key) async => values[key];
  @override
  Future<void> writeSecure(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> deleteSecure(String key) async {
    values.remove(key);
  }
}

class FakeTransport extends ChatGptTransport {
  FakeTransport(this.handler);
  final Future<ChatGptHttpResponse> Function(
    String,
    Uri,
    Map<String, String>,
    String?,
  )
  handler;
  @override
  Future<ChatGptHttpResponse> request(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    String? body,
  }) => handler(method, uri, headers, body);
  @override
  void cancel() {}
}
