import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:studyhub/ai/class_generation_provider.dart';
import 'package:studyhub/ai/lecture_enrichment_provider.dart';
import 'package:studyhub/app/class_creator.dart';
import 'package:studyhub/app/lecture_html_view.dart';
import 'package:studyhub/app/lecture_workspace.dart';
import 'package:studyhub/app/study_hub_app.dart';
import 'package:studyhub/persistence/lecture_content_store.dart';
import 'package:studyhub/persistence/library_store.dart';

class _Provider implements LectureEnrichmentProvider, ClassGenerationProvider {
  int calls = 0;
  @override
  String get name => 'Synthetic ChatGPT';
  @override
  Future<bool> get isConnected async => true;
  @override
  Future<void> connect() async {}
  @override
  Future<void> disconnect() async {}
  @override
  void cancel() {}
  @override
  Future<String> generate({
    required images,
    required String lectureTitle,
    required String sourceNotes,
  }) async => throw UnimplementedError();
  @override
  Future<String> generateClass({required String request}) async {
    calls++;
    return jsonEncode({
      'title': 'Mechanics from first principles',
      'lectures': [
        {
          'title': 'Motion',
          'html': '<h1>Understand motion</h1><p>Velocity tells us how position changes.</p><svg width="160" height="60"><title>Motion to the right</title><path d="M10 30 H140 L130 20 M140 30 L130 40" stroke="black" fill="none"/></svg><h2>Worked example</h2><p>Travelling 10 metres in 2 seconds gives an average speed of 5 metres per second.</p>',
        },
        {
          'title': 'Force',
          'html': '<h1>Understand force</h1><p>The net force changes velocity.</p><math><mi>F</mi><mo>=</mo><mi>m</mi><mi>a</mi></math><details><summary>Check your reasoning</summary><p>Balanced forces give zero acceleration.</p></details>',
        },
      ],
    });
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'create, preview, save and reopen a populated class using native HTML',
    (tester) async {
      final dir = await Directory.systemTemp.createTemp(
        'studyhub-generated-class-',
      );
      final library = JsonLibraryStore(File('${dir.path}/library.json'));
      final content = JsonLectureContentStore(Directory('${dir.path}/content'));
      final provider = _Provider();
      addTearDown(() => dir.delete(recursive: true));
      Future<void> waitFor(bool Function() condition) async {
        final clock = Stopwatch()..start();
        while (!condition() && clock.elapsed < const Duration(seconds: 25)) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(condition(), true);
      }

      Future<void> mount() async {
        await tester.pumpWidget(
          StudyHubApp(
            openStore: () async => library,
            openContentStore: () async => content,
            providers: [provider],
          ),
        );
        await tester.pumpAndSettle();
      }

      await mount();
      await tester.tap(find.text('Create class with ChatGPT').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'Teach me mechanics with worked examples.',
      );
      await tester.pump();
      await tester.tap(find.text('Generate class'));
      await tester.pump(const Duration(milliseconds: 400));
      await waitFor(() => find.text('Save class').evaluate().isNotEmpty);
      await waitFor(
        () => find
            .byKey(const ValueKey('html-preview-loading'))
            .evaluate()
            .isEmpty,
      );
      expect(
        tester
            .widget<LectureHtmlView>(find.byType(LectureHtmlView))
            .content
            .plainText,
        contains('5 metres per second'),
      );
      expect((await library.load()).classes, isEmpty);
      await tester.tap(find.text('Save class'));
      await tester.pump(const Duration(milliseconds: 400));
      await waitFor(() => find.byType(ClassCreator).evaluate().isEmpty);
      await waitFor(
        () => find
            .byKey(const ValueKey('html-preview-loading'))
            .evaluate()
            .isEmpty,
      );
      final stored = (await library.load()).classes.single;
      expect(stored.lectures, hasLength(2));
      expect(provider.calls, 1);
      for (final lesson in stored.lectures) {
        expect((await content.load(lesson.id)).hasHtml, true);
        expect(lesson.notes, isNotEmpty);
      }
      expect(
        tester
            .widget<LectureHtmlView>(find.byType(LectureHtmlView))
            .content
            .plainText,
        contains('Velocity'),
      );
      final workspace = tester.state<LectureWorkspaceState>(
        find.byType(LectureWorkspace),
      );
      expect(await tester.runAsync(workspace.prepareToLeave), true);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await mount();
      await tester.tap(
        find.widgetWithText(ListTile, 'Mechanics from first principles'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Force'));
      await tester.pump(const Duration(milliseconds: 400));
      await waitFor(
        () => find
            .byKey(const ValueKey('html-preview-loading'))
            .evaluate()
            .isEmpty,
      );
      expect(
        tester
            .widget<LectureHtmlView>(find.byType(LectureHtmlView))
            .content
            .plainText,
        contains('Balanced forces'),
      );
      final reopened = tester.state<LectureWorkspaceState>(
        find.byType(LectureWorkspace),
      );
      expect(await tester.runAsync(reopened.prepareToLeave), true);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
    variant: TargetPlatformVariant.only(
      Platform.isMacOS ? TargetPlatform.macOS : TargetPlatform.iOS,
    ),
  );
}
