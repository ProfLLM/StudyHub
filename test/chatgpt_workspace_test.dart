import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyhub/ai/chatgpt_subscription_provider.dart';
import 'package:studyhub/app/lecture_workspace.dart';
import 'package:studyhub/domain/lecture_content.dart';
import 'package:studyhub/domain/library.dart';
import 'package:studyhub/ink/ink_canvas.dart';
import 'package:studyhub/persistence/lecture_content_store.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGP4DwQACfsD/fteaysAAAAASUVORK5CYII=',
);

class _Provider extends ChatGptSubscriptionProvider {
  bool connected = false;
  bool noticeShown = false;
  int usageOpens = 0;
  int generations = 0;
  @override
  Future<bool> get isConnected async => connected;
  @override
  Future<void> connect() async => connected = true;
  @override
  Future<void> disconnect() async => connected = false;
  @override
  Future<bool> get needsPlanNotice async => !noticeShown;
  @override
  Future<void> markPlanNoticeShown() async => noticeShown = true;
  @override
  Future<void> openUsage() async => usageOpens++;
  @override
  Future<String> generate({
    required List<Uint8List> images,
    required String lectureTitle,
    required String sourceNotes,
  }) async {
    generations++;
    return '<h1>Synthetic ChatGPT result</h1>';
  }
}

class _Ink extends InkCanvasController {
  _Ink() {
    ready.value = true;
  }
  @override
  Future<InkDrawingUpdate?> flush() async => null;
  @override
  Future<void> setActive(bool active) async {}
  @override
  Future<InkSnapshot> captureSnapshot() async => InkSnapshot(
    drawing: Uint8List.fromList([1]),
    preview: _png,
    changeId: 0,
    images: [_png],
  );
}

class _Store implements LectureContentStore {
  LectureContent content = LectureContent(lectureId: 'synthetic-lecture')
      .withInk(drawing: Uint8List.fromList([1]), preview: _png);
  @override
  Future<LectureContent> load(String id) async => content;
  @override
  Future<void> save(LectureContent next) async => content = next;
  @override
  Future<void> delete(String id) async {}
}

Future<void> _mount(
  WidgetTester tester,
  _Provider provider, [
  _Store? store,
]) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: LectureWorkspace(
          lecture: const Lecture(id: 'synthetic-lecture', title: 'Physics'),
          store: store ?? _Store(),
          providers: [provider],
          inkController: _Ink(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

void main() {
  testWidgets(
    'first connection explains plan and credits once, with usage access',
    (tester) async {
      final provider = _Provider();
      await _mount(tester, provider);
      await _tap(tester, 'Continue with ChatGPT');
      expect(find.text('You’re using your ChatGPT plan'), findsOneWidget);
      expect(find.textContaining('turn off credit fallback'), findsOneWidget);
      expect(provider.noticeShown, isFalse);
      final usage = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Manage usage'),
      );
      await tester.tap(usage);
      await tester.pump();
      expect(provider.usageOpens, 1);
      await _tap(tester, 'Got it');
      expect(provider.noticeShown, isTrue);
      expect(find.text('Using ChatGPT plan'), findsOneWidget);
      await _tap(tester, 'Disconnect ChatGPT');
      await _tap(tester, 'Continue with ChatGPT');
      expect(find.text('You’re using your ChatGPT plan'), findsNothing);
      expect(provider.generations, 0);
    },
  );

  testWidgets(
    'first generation waits for source consent and first-plan notice',
    (tester) async {
      final provider = _Provider()..connected = true;
      final store = _Store();
      await _mount(tester, provider, store);
      await _tap(tester, 'Create HTML with ChatGPT');
      expect(find.text('Create HTML with ChatGPT?'), findsOneWidget);
      expect(
        find.textContaining('according to your account settings'),
        findsOneWidget,
      );
      expect(provider.generations, 0);
      await _tap(tester, 'Send notes');
      expect(find.text('You’re using your ChatGPT plan'), findsOneWidget);
      expect(provider.generations, 0);
      await _tap(tester, 'Got it');
      await tester.pumpAndSettle();
      expect(provider.generations, 1);
      expect(store.content.html, contains('Synthetic ChatGPT result'));
      expect(store.content.drawing, [1]);
    },
  );

  testWidgets('plan notice and usage controls fit a narrow workspace', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final provider = _Provider();
    await _mount(tester, provider);
    await _tap(tester, 'Continue with ChatGPT');
    expect(find.text('You’re using your ChatGPT plan'), findsOneWidget);
    await _tap(tester, 'Got it');
    await _tap(tester, 'Manage usage');
    expect(provider.usageOpens, 1);
    expect(tester.takeException(), isNull);
  });
}
