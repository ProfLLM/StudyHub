import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:studyhub/ai/chatgpt_subscription_provider.dart';

final _now = DateTime.utc(2026, 10, 22);

String _session({bool expired = false}) => jsonEncode({
  'access_token': 'fixture-access',
  'refresh_token': 'fixture-refresh',
  'scope': 'chatgpt.tokens.use.direct',
  'client_id': 'oaiapp_fixture',
  'subject': 'original-account',
  'expires_at': _now
      .add(Duration(hours: expired ? -1 : 1))
      .millisecondsSinceEpoch,
});

class _Native extends ChatGptNativeAuth {
  final values = <String, String>{};
  Future<void> Function(Uri)? open;
  Future<void> Function(String key, String value)? beforeWrite;
  bool closed = false;

  @override
  Future<String?> readSecure(String key) async => values[key];
  @override
  Future<void> writeSecure(String key, String value) async {
    await beforeWrite?.call(key, value);
    values[key] = value;
  }

  @override
  Future<void> deleteSecure(String key) async => values.remove(key);
  @override
  Future<void> openAuth(String url) async => open?.call(Uri.parse(url));
  @override
  Future<void> closeAuth() async => closed = true;
}

typedef _Handler = Future<ChatGptHttpResponse> Function(
  String method,
  Uri uri,
  Map<String, String> headers,
  String? body,
);

class _Transport extends ChatGptTransport {
  _Transport(this.handler);
  final _Handler handler;
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

ChatGptHttpResponse _json(Map<String, dynamic> value) =>
    ChatGptHttpResponse(200, Stream.value(utf8.encode(jsonEncode(value))));

String _event(String type, {String? delta}) =>
    'data: ${jsonEncode({'type': type, 'delta': ?delta})}\n\n';

ChatGptHttpResponse _complete() => ChatGptHttpResponse(
  200,
  Stream.value(
    utf8.encode(
      '${_event('response.output_text.delta', delta: '<h1>Complete</h1>')}${_event('response.completed')}',
    ),
  ),
);

ChatGptHttpResponse _models() => _json({
  'models': [
    {'slug': 'gpt-6.1-sol', 'visibility': 'list'},
  ],
});

Future<String> _generate(ChatGptSubscriptionProvider provider) =>
    provider.generate(
      images: [
        Uint8List.fromList([1]),
      ],
      lectureTitle: 'Synthetic lecture',
      sourceNotes: 'Synthetic authorized source only.',
    );

void main() {
  test('sign-out excludes new inference while revocation is pending', () async {
    final native = _Native()..values['chatgpt.session'] = _session();
    final discovery = Completer<ChatGptHttpResponse>();
    final reached = Completer<void>();
    var inferenceRequests = 0;
    final provider = ChatGptSubscriptionProvider(
      nativeAuth: native,
      now: () => _now,
      transport: _Transport((method, uri, headers, body) async {
        if (uri.path.endsWith('openid-configuration')) {
          reached.complete();
          return discovery.future;
        }
        if (uri.path.endsWith('/revoke')) {
          return ChatGptHttpResponse(200, const Stream.empty());
        }
        inferenceRequests++;
        return uri.path.endsWith('/models') ? _models() : _complete();
      }),
    );
    final signingOut = provider.disconnect();
    await reached.future;
    Object? generationError;
    try {
      await _generate(provider);
    } catch (error) {
      generationError = error;
    } finally {
      discovery.complete(
        _json({'revocation_endpoint': 'https://auth.openai.com/revoke'}),
      );
      await signingOut;
    }
    expect(generationError, isA<EnrichmentException>());
    expect(inferenceRequests, 0);
    expect(native.values.containsKey('chatgpt.session'), isFalse);
  });

  test(
    'canceling after callback validation prevents the code exchange',
    () async {
      final native = _Native();
      var requests = 0;
      native.beforeWrite = (key, value) async {
        if (key == 'chatgpt.registration' &&
            jsonDecode(value)['client_id'] != null) {
          native.onCancelled?.call();
        }
      };
      native.open = (url) async {
        final query = url.queryParameters;
        final target = Uri.parse(query['redirect_uri']!).replace(
          queryParameters: {
            'state': query['state']!,
            'code': 'synthetic-code',
            'client_id': 'oaiapp_fixture',
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
      final provider = ChatGptSubscriptionProvider(
        nativeAuth: native,
        transport: _Transport((method, uri, headers, body) async {
          requests++;
          return uri.path.endsWith('/jwks.json')
              ? _json({'keys': []})
              : _json({
                  'access_token': 'fixture-access',
                  'refresh_token': 'fixture-refresh',
                  'id_token': 'fixture-token',
                  'scope': 'chatgpt.tokens.use.direct',
                  'expires_in': 3600,
                });
        }),
      );
      await expectLater(
        provider.connect(),
        throwsA(isA<EnrichmentException>()),
      );
      expect(requests, 0);
      expect(native.values.containsKey('chatgpt.session'), isFalse);
      expect(native.closed, isTrue);
    },
  );

  test(
    'cancel during catalog lookup cannot send the source afterward',
    () async {
      final native = _Native()..values['chatgpt.session'] = _session();
      final catalog = Completer<ChatGptHttpResponse>();
      final reached = Completer<void>();
      var sentSource = false;
      final provider = ChatGptSubscriptionProvider(
        nativeAuth: native,
        now: () => _now,
        transport: _Transport((method, uri, headers, body) async {
          if (uri.path.endsWith('/models')) {
            reached.complete();
            return catalog.future;
          }
          sentSource = true;
          return _complete();
        }),
      );
      final result = _generate(provider);
      final assertion = expectLater(
        result,
        throwsA(isA<EnrichmentException>()),
      );
      await reached.future;
      provider.cancel();
      catalog.complete(_models());
      await assertion;
      expect(sentSource, isFalse);
      expect(native.values['chatgpt.session'], _session());
    },
  );

  test('concurrent requests cannot race rotating refresh tokens', () async {
    final native = _Native()
      ..values['chatgpt.session'] = _session(expired: true);
    final refresh = Completer<ChatGptHttpResponse>();
    final reached = Completer<void>();
    var refreshes = 0;
    final provider = ChatGptSubscriptionProvider(
      nativeAuth: native,
      now: () => _now,
      transport: _Transport((method, uri, headers, body) async {
        if (uri.path.endsWith('/token')) {
          refreshes++;
          final form = Uri.splitQueryString(body!);
          expect(form['refresh_token'], 'fixture-refresh');
          expect(form['resource'], 'https://api.openai.com/v1');
          expect(headers.containsKey('Authorization'), isFalse);
          reached.complete();
          return refresh.future;
        }
        expect(headers['Authorization'], 'Bearer replacement-access');
        return uri.path.endsWith('/models') ? _models() : _complete();
      }),
    );
    final first = _generate(provider);
    await reached.future;
    await expectLater(_generate(provider), throwsA(isA<EnrichmentException>()));
    refresh.complete(
      _json({
        'access_token': 'replacement-access',
        'refresh_token': 'replacement-refresh',
        'expires_in': 3600,
      }),
    );
    expect(await first, '<h1>Complete</h1>');
    expect(refreshes, 1);
    expect(
      jsonDecode(native.values['chatgpt.session']!)['refresh_token'],
      'replacement-refresh',
    );
  });

  test(
    'a different verified account cannot replace existing credentials',
    () async {
      final native = _Native()
        ..values['chatgpt.session'] = _session()
        ..values['chatgpt.registration'] = jsonEncode({
          'client_id': 'oaiapp_fixture',
          'host_id': 'urn:uuid:00000000-0000-4000-8000-000000000000',
          'subject': 'original-account',
        });
      late String nonce;
      native.open = (url) async {
        final query = url.queryParameters;
        nonce = query['nonce']!;
        expect(query['client_id'], 'oaiapp_fixture');
        expect(query.containsKey('agent_name_hint'), isFalse);
        final target = Uri.parse(query['redirect_uri']!).replace(
          queryParameters: {'state': query['state']!, 'code': 'synthetic-code'},
        );
        final client = HttpClient();
        try {
          final response = await (await client.getUrl(target)).close();
          await response.drain<void>();
        } finally {
          client.close(force: true);
        }
      };
      final provider = ChatGptSubscriptionProvider(
        nativeAuth: native,
        now: () => _now,
        transport: _Transport((method, uri, headers, body) async {
          expect(headers.containsKey('Authorization'), isFalse);
          return uri.path.endsWith('/jwks.json')
              ? _json({'keys': []})
              : _json({
                  'access_token': 'different-account-access',
                  'refresh_token': 'different-account-refresh',
                  'id_token': 'verified-by-fixture',
                  'scope': 'chatgpt.tokens.use.direct',
                  'expires_in': 3600,
                });
        }),
        verifyIdToken: (_, _) async => {
          'iss': 'https://auth.openai.com',
          'aud': 'oaiapp_fixture',
          'nonce': nonce,
          'sub': 'different-account',
          'exp': _now.millisecondsSinceEpoch ~/ 1000 + 3600,
        },
      );
      await expectLater(
        provider.connect(),
        throwsA(isA<EnrichmentException>()),
      );
      expect(native.closed, isTrue);
      expect(native.values['chatgpt.session'], _session());
      expect(
        jsonDecode(native.values['chatgpt.registration']!)['subject'],
        'original-account',
      );
    },
  );

  test(
    'sign-out never forwards a refresh token to an unexpected origin',
    () async {
      final native = _Native()..values['chatgpt.session'] = _session();
      var requests = 0;
      final provider = ChatGptSubscriptionProvider(
        nativeAuth: native,
        transport: _Transport((method, uri, headers, body) async {
          requests++;
          expect(method, 'GET');
          expect(body, isNull);
          return _json({
            'revocation_endpoint': 'https://attacker.invalid/revoke',
          });
        }),
      );
      await expectLater(
        provider.disconnect(),
        throwsA(isA<EnrichmentException>()),
      );
      expect(requests, 1);
      expect(native.values.containsKey('chatgpt.session'), isFalse);
    },
  );

  test(
    'real HTTP transport does not follow credential-bearing redirects',
    () async {
      final source = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final target = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final transport = IoChatGptTransport();
      var forwarded = false;
      final destination = target.listen((request) async {
        forwarded = true;
        request.response.write('Should never be reached');
        await request.response.close();
      });
      final origin = source.listen((request) async {
        expect(request.headers.value('Authorization'), 'Bearer fixture-only');
        request.response.statusCode = HttpStatus.temporaryRedirect;
        request.response.headers.set(
          'Location',
          'http://127.0.0.1:${target.port}/unexpected',
        );
        await request.response.close();
      });
      try {
        final response = await transport.request(
          'GET',
          Uri.parse('http://127.0.0.1:${source.port}/request'),
          headers: {'Authorization': 'Bearer fixture-only'},
        );
        await response.body.drain<void>();
        expect(response.statusCode, HttpStatus.temporaryRedirect);
        expect(forwarded, isFalse);
      } finally {
        transport.cancel();
        await origin.cancel();
        await destination.cancel();
        await source.close(force: true);
        await target.close(force: true);
      }
    },
  );

  test(
    'no rendition escapes before a completed event on an open stream',
    () async {
      final stream = StreamController<List<int>>();
      var returned = false;
      final result = readChatGptHtmlStream(stream.stream).then((value) {
        returned = true;
        return value;
      });
      stream.add(
        utf8.encode(_event('response.output_text.delta', delta: '<h1>α</h1>')),
      );
      await Future<void>.delayed(Duration.zero);
      expect(returned, isFalse);
      // The connection need not close once an explicit terminal event arrives.
      stream.add(
        utf8.encode(_event('response.completed').replaceAll('\n', '\r\n')),
      );
      expect(await result.timeout(const Duration(seconds: 1)), '<h1>α</h1>');
      await stream.close();
    },
  );

  for (final failure in ['response.incomplete', 'error']) {
    test('$failure after partial output never publishes HTML', () async {
      final source =
          '${_event('response.output_text.delta', delta: '<h1>Partial')}'
          '${_event(failure)}${_event('response.completed')}';
      await expectLater(
        readChatGptHtmlStream(Stream.value(utf8.encode(source))),
        throwsA(isA<EnrichmentException>()),
      );
    });
  }
}
