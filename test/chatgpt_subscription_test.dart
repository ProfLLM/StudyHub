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

  test('declined plan permission persists a specific consent retry, then normal sign-in stops forcing consent', () async {
    final native = FakeNative();
    final authorizations = <Map<String, String>>[];
    late String nonce;
    var granted = false;
    native.open = (url) async {
      final query = Uri.parse(url).queryParameters;
      authorizations.add(query);
      nonce = query['nonce']!;
      final target = Uri.parse(query['redirect_uri']!).replace(
        queryParameters: {
          'state': query['state']!,
          'code': 'synthetic-code',
          if (query['client_id'] == 'dynamic_agent_client')
            'client_id': 'oaiapp_test',
        },
      );
      final client = HttpClient();
      try {
        await (await (await client.getUrl(target)).close()).drain<void>();
      } finally {
        client.close(force: true);
      }
    };
    final transport = FakeTransport((_, uri, _, _) async {
      if (uri.path.endsWith('/jwks.json')) return jsonResponse({'keys': []});
      return jsonResponse({
        'access_token': 'synthetic-access',
        'refresh_token': 'synthetic-refresh',
        'id_token': 'synthetic-id',
        'scope': granted ? 'chatgpt.tokens.use.direct' : 'openid profile email',
        'expires_in': 3600,
      });
    });
    ChatGptSubscriptionProvider provider() => ChatGptSubscriptionProvider(
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
    await expectLater(
      provider().connect(),
      throwsA(isA<EnrichmentException>()),
    );
    expect(authorizations.first['client_id'], 'dynamic_agent_client');
    expect(authorizations.first.containsKey('prompt'), false);
    expect(native.values.containsKey('chatgpt.session'), false);
    expect(
      jsonDecode(native.values['chatgpt.registration']!)['needs_plan_consent'],
      true,
    );
    expect(await provider().needsPlanNotice, false);
    granted = true;
    final retry = provider();
    await retry.connect();
    expect(authorizations[1]['client_id'], 'oaiapp_test');
    expect(authorizations[1]['prompt'], 'consent');
    expect(authorizations[1].containsKey('agent_name_hint'), false);
    expect(
      authorizations[1]['ext_agent_host_id'],
      authorizations[0]['ext_agent_host_id'],
    );
    expect(
      jsonDecode(native.values['chatgpt.registration']!)['needs_plan_consent'],
      false,
    );
    expect(await retry.needsPlanNotice, true);
    await retry.markPlanNoticeShown();
    await provider().connect();
    expect(authorizations[2].containsKey('prompt'), false);
    expect(await provider().needsPlanNotice, false);
  });

  test('terminal refresh errors clear unusable tokens while retaining the registration', () async {
    final codes = [
      'invalid_grant',
      'invalid_refresh_token',
      'token_expired',
      'refresh_token_expired',
      'refresh_token_invalidated',
      'refresh_token_reused',
    ];
    for (var index = 0; index < codes.length; index++) {
      const registration =
          '{"client_id":"oaiapp_test","host_id":"urn:uuid:synthetic","subject":"synthetic","plan_notice_shown":true}';
      final native = FakeNative()
        ..values['chatgpt.session'] = session(
          now.subtract(const Duration(hours: 2)),
        )
        ..values['chatgpt.registration'] = registration;
      var requests = 0;
      final provider = ChatGptSubscriptionProvider(
        nativeAuth: native,
        now: () => now,
        transport: FakeTransport((_, uri, _, _) async {
          requests++;
          expect(uri.path.endsWith('/token'), true);
          final error = index.isEven ? codes[index] : {'code': codes[index]};
          return ChatGptHttpResponse(
            index.isEven ? 400 : 401,
            Stream.value(
              utf8.encode(
                jsonEncode({
                  'error': error,
                  'error_description':
                      'Synthetic private diagnostic must not leak',
                }),
              ),
            ),
          );
        }),
      );
      await expectLater(
        provider.generate(
          images: [
            Uint8List.fromList([1]),
          ],
          lectureTitle: '',
          sourceNotes: '',
        ),
        throwsA(
          isA<EnrichmentException>().having(
            (e) => e.message,
            'safe message',
            isNot(contains('private diagnostic')),
          ),
        ),
      );
      expect(requests, 1);
      expect(
        native.values.containsKey('chatgpt.session'),
        false,
        reason: codes[index],
      );
      expect(native.values['chatgpt.registration'], registration);
      expect(await provider.isConnected, false);
    }
  });

  test('transient refresh failures and invalid client preserve credentials for recovery', () async {
    for (final failure in [
      (status: 503, body: '{"error":"invalid_grant"}'),
      (status: 429, body: '{"error":"rate_limit"}'),
      (status: 400, body: '{"error":"invalid_client"}'),
      (status: 401, body: '<html>temporary gateway failure</html>'),
      (status: 400, body: '{"error":{"code":"unknown_error"}}'),
      (status: 0, body: ''),
    ]) {
      final saved = session(now.subtract(const Duration(hours: 2)));
      final native = FakeNative()..values['chatgpt.session'] = saved;
      final provider = ChatGptSubscriptionProvider(
        nativeAuth: native,
        now: () => now,
        transport: FakeTransport((_, _, _, _) async {
          if (failure.status == 0) {
            throw const SocketException('Synthetic offline');
          }
          return ChatGptHttpResponse(
            failure.status,
            Stream.value(utf8.encode(failure.body)),
          );
        }),
      );
      await expectLater(
        provider.generate(
          images: [
            Uint8List.fromList([1]),
          ],
          lectureTitle: '',
          sourceNotes: '',
        ),
        throwsA(isA<EnrichmentException>()),
      );
      expect(native.values['chatgpt.session'], saved);
    }
  });

  test('plan notice is local, registration-bound, and remains acknowledged after reconnect', () async {
    final native = FakeNative();
    final registration = {
      'client_id': 'oaiapp_test',
      'subject': 'synthetic',
      'host_id': 'urn:uuid:synthetic',
    };
    native.values['chatgpt.registration'] = jsonEncode(registration);
    ChatGptSubscriptionProvider provider() => ChatGptSubscriptionProvider(
      nativeAuth: native,
      transport: FakeTransport(
        (_, _, _, _) async => throw StateError('No remote request allowed'),
      ),
    );
    expect(await provider().needsPlanNotice, false);
    await expectLater(
      provider().markPlanNoticeShown(),
      throwsA(isA<EnrichmentException>()),
    );
    native.values['chatgpt.session'] = session(now);
    expect(await provider().needsPlanNotice, true);
    await provider().markPlanNoticeShown();
    expect(await provider().needsPlanNotice, false);
    native.values.remove('chatgpt.session');
    expect(await provider().needsPlanNotice, false);
    native.values['chatgpt.session'] = session(now);
    expect(await provider().needsPlanNotice, false);
    final mismatched = jsonDecode(session(now)) as Map;
    mismatched['subject'] = 'different-account';
    native.values['chatgpt.session'] = jsonEncode(mismatched);
    expect(await provider().needsPlanNotice, false);
    await expectLater(
      provider().markPlanNoticeShown(),
      throwsA(isA<EnrichmentException>()),
    );
    expect(
      jsonDecode(native.values['chatgpt.registration']!)['subject'],
      'synthetic',
    );
  });

  test('usage settings uses the native action without account or inference requests', () async {
    final native = FakeNative();
    await ChatGptSubscriptionProvider(
      nativeAuth: native,
      transport: FakeTransport(
        (_, _, _, _) async => throw StateError('No remote request allowed'),
      ),
    ).openUsage();
    expect(native.usageOpened, 1);
    expect(native.values, isEmpty);
  });

  test(
    'expired sign-in closes its callback and a fresh attempt can connect',
    () async {
      final native = FakeNative();
      final authorizations = <Uri>[];
      late String nonce;
      var requests = 0;
      native.open = (url) async => authorizations.add(Uri.parse(url));
      final provider = ChatGptSubscriptionProvider(
        nativeAuth: native,
        authTimeout: const Duration(milliseconds: 30),
        now: () => now,
        transport: FakeTransport((_, uri, _, _) async {
          requests++;
          if (uri.path.endsWith('/jwks.json')) {
            return jsonResponse({'keys': []});
          }
          return jsonResponse({
            'access_token': 'synthetic-access',
            'refresh_token': 'synthetic-refresh',
            'id_token': 'synthetic-id',
            'scope': 'chatgpt.tokens.use.direct',
            'expires_in': 3600,
          });
        }),
        verifyIdToken: (_, _) async => {
          'iss': 'https://auth.openai.com',
          'aud': 'oaiapp_test',
          'nonce': nonce,
          'sub': 'synthetic',
          'exp': now.millisecondsSinceEpoch ~/ 1000 + 3600,
        },
      );
      await expectLater(
        provider.connect(),
        throwsA(
          isA<EnrichmentException>().having(
            (e) => e.message,
            'recovery guidance',
            contains('fresh sign-in session'),
          ),
        ),
      );
      expect(native.closed, true);
      expect(requests, 0);
      expect(native.values.containsKey('chatgpt.session'), false);
      final expired = authorizations.single.queryParameters;
      final host = jsonDecode(
        native.values['chatgpt.registration']!,
      )['host_id'];
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 1);
      try {
        await expectLater(
          client.getUrl(Uri.parse(expired['redirect_uri']!)),
          throwsA(isA<SocketException>()),
        );
        native.open = (url) async {
          final query = Uri.parse(url).queryParameters;
          expect(query['state'], isNot(expired['state']));
          expect(query['nonce'], isNot(expired['nonce']));
          expect(query['code_challenge'], isNot(expired['code_challenge']));
          expect(query['ext_agent_host_id'], host);
          nonce = query['nonce']!;
          final callback = Uri.parse(query['redirect_uri']!).replace(
            queryParameters: {
              'state': query['state']!,
              'code': 'synthetic-fresh-code',
              'client_id': 'oaiapp_test',
            },
          );
          await (await (await client.getUrl(callback)).close()).drain<void>();
        };
        await provider.connect();
        expect(await provider.isConnected, true);
        expect(requests, 2);
      } finally {
        client.close(force: true);
      }
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
  int usageOpened = 0;
  @override
  Future<void> openUsage() async {
    usageOpened++;
  }

  @override
  Future<void> openAuth(String url) async {
    if (!opened.isCompleted) opened.complete();
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
