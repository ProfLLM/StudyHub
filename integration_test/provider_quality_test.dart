import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:studyhub/ai/chatgpt_subscription_provider.dart';
import 'package:studyhub/app/lecture_html_view.dart';
import 'package:studyhub/enrichment/safe_lecture_html.dart';

const _enabled = bool.fromEnvironment('STUDYHUB_LIVE_CHATGPT');
const _replay = bool.fromEnvironment('STUDYHUB_REPLAY_CHATGPT');
const _runsOnMac = _enabled || _replay;
String _hash(List<int> bytes) => sha256.convert(bytes).toString();

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Establish accessibility before testWidgets records its handle baseline.
  // OS accessibility clients may otherwise enable it halfway through the run.
  if (_runsOnMac && Platform.isMacOS) {
    final semantics = binding.ensureSemantics();
    tearDownAll(semantics.dispose);
    final previousPointerPolicy = binding.shouldPropagateDevicePointerEvents;
    binding.shouldPropagateDevicePointerEvents = true;
    tearDownAll(() {
      binding.shouldPropagateDevicePointerEvents = previousPointerPolicy;
    });
  }
  final corpus = Completer<String>();
  if (_runsOnMac && Platform.isMacOS) {
    developer.registerExtension('ext.studyhub.loadLiveCorpus', (_, args) async {
      final value = args['corpus'];
      if (corpus.isCompleted ||
          value == null ||
          utf8.encode(value).length > 2 * 1024 * 1024) {
        return developer.ServiceExtensionResponse.error(
          -32602,
          'Expected one bounded public corpus.',
        );
      }
      corpus.complete(value);
      return developer.ServiceExtensionResponse.result('{"accepted":true}');
    });
  }
  testWidgets(
    _runsOnMac && Platform.isMacOS
        ? '${_replay ? 'Saved' : 'Live'} ChatGPT: seven synthetic conversions; semantic review required'
        : 'SKIPPED: macOS requires explicit STUDYHUB_LIVE_CHATGPT opt-in',
    (tester) async {
      // Opt-in and public inputs precede provider construction and Keychain access.
      if (!_runsOnMac || !Platform.isMacOS) return;
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: Text(
                'Waiting for public synthetic fixtures from test driver.',
              ),
            ),
          ),
        ),
      );
      await _wait(tester, () => corpus.isCompleted, const Duration(minutes: 2));
      final fixtureJson = await corpus.future;
      final sheets = (jsonDecode(fixtureJson) as List)
          .cast<Map<String, dynamic>>();
      expect(sheets.length, 6);
      final images = <Uint8List>[];
      for (final sheet in sheets) {
        final image = base64Decode(sheet['png_base64'] as String);
        expect(_hash(image), sheet['sha256']);
        expect(image.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
        images.add(image);
      }
      final provider = _replay
          ? null
          : ChatGptSubscriptionProvider(
              authTimeout: const Duration(minutes: 30),
            );
      final connect = Completer<void>();
      final start = Completer<void>();
      final runs = <Map<String, dynamic>>[];
      final report = <String, dynamic>{
        'status': 'not_verified',
        'provider': 'ChatGPT',
        'mode': _replay ? 'saved_response_replay_no_provider_calls' : 'live',
        'model_if_disclosed': null,
        'date_utc': DateTime.now().toUtc().toIso8601String(),
        'app_commit': const String.fromEnvironment('STUDYHUB_LIVE_COMMIT'),
        'instruction_sha256': _hash(utf8.encode(lectureHtmlInstructions)),
        'synthetic_inputs_only': true,
        'credentials_recorded': false,
        'semantic_review': 'not_run',
        'runs': runs,
      };
      binding.reportData = report;
      var status = 'Connect through StudyHub’s own native sign-in.';
      var connected = false;
      var busy = false;
      SafeLectureHtml? preview;
      late StateSetter refresh;
      Future<void> signIn() async {
        if (provider == null) return;
        refresh(() => busy = true);
        try {
          if (!await provider.isConnected) await provider.connect();
          connected = true;
          status =
              'Paused. Verify credit fallback is off in OpenAI '
              'settings before starting. No conversion has been sent.';
          connect.complete();
        } catch (error) {
          status = error is EnrichmentException
              ? 'No conversion was sent. ${error.message}'
              : 'Sign-in did not complete. No conversion was sent; retry or stop this run.';
        } finally {
          refresh(() => busy = false);
        }
      }

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              refresh = setState;
              return Scaffold(
                appBar: AppBar(
                  title: const Text('Synthetic ChatGPT quality run'),
                ),
                body: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Text(status),
                          Wrap(
                            spacing: 12,
                            children: [
                              FilledButton(
                                onPressed: busy || connected ? null : signIn,
                                child: const Text('Continue with ChatGPT'),
                              ),
                              TextButton(
                                onPressed: connected && !start.isCompleted
                                    ? () async {
                                        try {
                                          await provider?.openUsage();
                                        } catch (_) {
                                          refresh(
                                            () => status = 'Usage settings could not open. Do not start until the limit is verified.',
                                          );
                                        }
                                      }
                                    : null,
                                child: const Text('Open OpenAI usage settings'),
                              ),
                              FilledButton(
                                onPressed: connected && !start.isCompleted
                                    ? () {
                                        report['credit_spending_disabled_confirmed'] =
                                            true;
                                        start.complete();
                                        refresh(() {});
                                      }
                                    : null,
                                child: const Text(
                                  'Start 7 synthetic conversions',
                                ),
                              ),
                              TextButton(
                                onPressed: provider?.cancel,
                                child: const Text('Cancel current operation'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (preview != null)
                      Expanded(
                        child: LectureHtmlView(
                          key: ValueKey(runs.length),
                          content: preview!,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      );
      if (_replay) {
        connect.complete();
        start.complete();
      }
      try {
        await _wait(
          tester,
          () => connect.isCompleted,
          const Duration(minutes: 45),
        );
        await _wait(
          tester,
          () => start.isCompleted,
          const Duration(minutes: 20),
        );
        report['status'] = 'running';
        for (var i = 0; i < 7; i++) {
          final indexes = i < 6 ? [i] : [0, 1];
          final selected = [for (final index in indexes) images[index]];
          final before = selected.map(_hash).toList();
          final run = <String, dynamic>{
            'case_id': i < 6 ? sheets[i]['id'] : '07_ordered_pair',
            'sheet_ids': [for (final index in indexes) sheets[index]['id']],
            'input_sha256': before,
            'status': 'running',
            'semantic_review': 'not_run',
          };
          runs.add(run);
          refresh(
            () => status = 'Converting ${i + 1} of 7. Synthetic notes only.',
          );
          await tester.pump();
          final clock = Stopwatch()..start();
          try {
            String? raw;
            Object? requestError;
            var returned = false;
            final request = _replay
                ? Future<String>.value(
                    sheets[i < 6 ? i : 0][i < 6
                            ? 'recorded_html'
                            : 'ordered_pair_html']
                        as String,
                  )
                : provider!.generate(
                    images: selected,
                    lectureTitle: indexes
                        .map((index) => sheets[index]['title'])
                        .join(' / '),
                    sourceNotes: '',
                  );
            request.then(
              (value) {
                raw = value;
                returned = true;
              },
              onError: (Object error) {
                requestError = error;
                returned = true;
              },
            );
            await _wait(tester, () => returned, const Duration(minutes: 5));
            run['latency_ms'] = clock.elapsedMilliseconds;
            if (requestError != null) throw requestError!;
            run['raw_html'] = raw;
            final safe = SafeLectureHtml.parse(raw!);
            run['sanitized_html'] = safe.document;
            run['source_bytes_preserved'] =
                selected.map(_hash).join(',') == before.join(',');
            expect(run['source_bytes_preserved'], isTrue);
            refresh(() => preview = safe);
            await tester.pump();
            await _wait(
              tester,
              () => find
                  .byKey(const ValueKey('html-preview-loading'))
                  .evaluate()
                  .isEmpty,
              const Duration(seconds: 30),
            );
            expect(
              find.byType(AppKitView).evaluate().isNotEmpty ||
                  find.byType(UiKitView).evaluate().isNotEmpty,
              isTrue,
            );
            expect(
              find.text(
                'The HTML preview could not open. Your notes are safe.',
              ),
              findsNothing,
            );
            run['native_preview'] = 'loaded; visual review still required';
            run['status'] = 'returned_pending_semantic_review';
          } catch (error) {
            run['status'] = 'failed';
            run['error_type'] = error.runtimeType.toString();
            if (error is EnrichmentException) run['message'] = error.message;
            rethrow;
          } finally {
            run.putIfAbsent('latency_ms', () => clock.elapsedMilliseconds);
          }
        }
        report['status'] = 'returned_pending_semantic_review';
        report['completed_case_count'] = runs.length;
        refresh(
          () => status = 'Seven results returned. Semantic and visual review is still required.',
        );
        await tester.pump();
      } catch (error) {
        report['status'] = 'not_verified';
        report['error_type'] = error.runtimeType.toString();
        if (error is EnrichmentException) report['message'] = error.message;
        fail(
          'Live ChatGPT validation did not complete. See local evidence; this is not a quality pass.',
        );
      } finally {
        provider?.cancel();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
    skip: !_runsOnMac || !Platform.isMacOS,
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    timeout: const Timeout(Duration(minutes: 110)),
  );
}

Future<void> _wait(
  WidgetTester tester,
  bool Function() done,
  Duration limit,
) async {
  final clock = Stopwatch()..start();
  while (!done() && clock.elapsed < limit) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(
    done(),
    isTrue,
    reason: 'Timed out waiting for visible user action or native rendering.',
  );
}
