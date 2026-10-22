import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:studyhub/ai/lecture_enrichment_provider.dart';
import 'package:studyhub/app/study_hub_app.dart';
import 'package:studyhub/app/lecture_workspace.dart';
import 'package:studyhub/ink/ink_canvas.dart';
import 'package:studyhub/persistence/lecture_content_store.dart';
import 'package:studyhub/persistence/library_store.dart';

/// Exercises real PencilKit capture/export, files, and WebKit. Model output is a
/// deterministic fixture; this does not claim live inference or physical ink.
class FixtureAssistant implements LectureEnrichmentProvider {
  @override
  String get name => 'Test assistant';
  int requests = 0;
  List<Uint8List>? receivedImages;
  @override
  Future<bool> get isConnected async => true;
  @override
  Future<void> connect() async {}
  @override
  void cancel() {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<String> generate({
    required List<Uint8List> images,
    required String lectureTitle,
    required String sourceNotes,
  }) async {
    requests++;
    receivedImages = images;
    return '''<!doctype html><html><head><style>
body{font-family:-apple-system,sans-serif;} h1{color:#315b47;} section{margin:28px 0;}
figure{margin:0;} figcaption{color:#58665e;} svg text{font-family:-apple-system,sans-serif;}
</style></head><body><h1>Motion &amp; forces</h1><p>Synthetic integration-test result</p>
<section><h2>Newton’s second law</h2><p>The force acting on an object is its mass multiplied by its acceleration.</p>
<math display="block" aria-label="Force equals mass times acceleration"><mi>F</mi><mo>=</mo><mi>m</mi><mi>a</mi></math></section>
<section><h2>A force diagram</h2><figure><svg viewBox="0 0 520 180" role="img" aria-label="A block with a force acting to the right">
<rect x="70" y="50" width="130" height="90" rx="12" fill="#e4efe8" stroke="#315b47" stroke-width="2"/>
<text x="135" y="102" text-anchor="middle" fill="#193e2c" font-size="22">mass m</text>
<line x1="200" y1="95" x2="410" y2="95" stroke="#315b47" stroke-width="4"/>
<path d="M390 82 L414 95 L390 108" fill="none" stroke="#315b47" stroke-width="4"/>
<text x="310" y="65" text-anchor="middle" fill="#193e2c" font-size="22">force F →</text>
</svg><figcaption>The diagram is a vector illustration, separate from the original ink.</figcaption></figure></section>
</body></html>''';
  }
}

Future<void> waitFor(
  WidgetTester tester,
  bool Function() predicate,
  String description,
) async {
  final timer = Stopwatch()..start();
  while (!predicate() && timer.elapsed < const Duration(seconds: 25)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(predicate(), isTrue, reason: description);
}

Future<void> saveAndResume(WidgetTester tester) async {
  final workspace = tester.state<LectureWorkspaceState>(
    find.byType(LectureWorkspace),
  );
  expect(await tester.runAsync(workspace.prepareToLeave), isTrue);
  await tester.runAsync(workspace.resumeAfterNavigation);
  await tester.pumpAndSettle();
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('create, native ink, export, separate HTML, edit, and reopen', (
    tester,
  ) async {
    final directory = await Directory.systemTemp.createTemp('studyhub-flow-');
    final library = JsonLibraryStore(File('${directory.path}/library.json'));
    final content = JsonLectureContentStore(
      Directory('${directory.path}/content'),
    );
    final provider = FixtureAssistant();
    Widget app() => StudyHubApp(
      key: UniqueKey(),
      openStore: () async => library,
      openContentStore: () async => content,
      providers: [provider],
    );
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('New class'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Physics test');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New lecture'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Motion test');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
    await waitFor(
      tester,
      () => find.byType(InkCanvas).evaluate().isNotEmpty,
      'A new Lecture opens its ink canvas',
    );
    var ink = tester.widget<InkCanvas>(find.byType(InkCanvas)).controller;
    await waitFor(
      tester,
      () => ink.ready.value,
      'The real native canvas is ready',
    );
    await tester.runAsync(ink.seedSyntheticDrawingForTesting);
    await tester.runAsync(ink.flush);
    await tester.pumpAndSettle();
    final storedLibrary = (await tester.runAsync(library.load))!;
    final lectureId = storedLibrary.classes.single.lectures.single.id;
    await saveAndResume(tester);
    await tester.pumpAndSettle();
    final before = (await tester.runAsync(() => content.load(lectureId)))!;
    expect(before.hasInk, isTrue);
    expect(before.hasHtml, isFalse);
    await File('${directory.path}/ink.png')
        .writeAsBytes(await binding.takeScreenshot('studyhub-native-ink'));
    await tester.tap(find.text('Create HTML with Test assistant'));
    await waitFor(
      tester,
      () =>
          find.widgetWithText(FilledButton, 'Send notes').evaluate().isNotEmpty,
      'Snapshot confirmation opens before any content is sent',
    );
    expect(
      provider.requests,
      0,
      reason: 'A snapshot is not sent before confirmation',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Send notes'));
    await waitFor(
      tester,
      () => find.text('View HTML').evaluate().isNotEmpty,
      'A validated HTML result becomes available',
    );
    await tester.pumpAndSettle();
    expect(provider.requests, 1);
    expect(provider.receivedImages, isNotEmpty);
    await saveAndResume(tester);
    final after = (await tester.runAsync(() => content.load(lectureId)))!;
    expect(
      after.drawing,
      before.drawing,
      reason: 'Conversion preserves original editable ink',
    );
    expect(after.htmlSourceRevision, before.inkRevision);
    await tester.tap(find.text('View HTML'));
    await tester.pumpAndSettle();
    await waitFor(
      tester,
      () =>
          find.byKey(const ValueKey('html-preview-loading')).evaluate().isEmpty,
      'The actual native HTML renderer finished loading',
    );
    expect(
      find.text('The HTML preview could not open. Your notes are safe.'),
      findsNothing,
    );
    await File('${directory.path}/html.png')
        .writeAsBytes(await binding.takeScreenshot('studyhub-native-html'));
    await tester.tap(find.text('Ink'));
    await tester.pumpAndSettle();
    ink = tester.widget<InkCanvas>(find.byType(InkCanvas)).controller;
    await tester.runAsync(ink.clear);
    await tester.runAsync(ink.flush);
    await tester.pumpAndSettle();
    expect(find.text('HTML needs refresh'), findsOneWidget);
    await saveAndResume(tester);
    final cleared = (await tester.runAsync(() => content.load(lectureId)))!;
    expect(
      cleared.html,
      after.html,
      reason: 'Editing ink cannot discard its HTML rendition',
    );
    expect(cleared.inkRevision, greaterThan(after.inkRevision));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Physics test'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Motion test'));
    await tester.pumpAndSettle();
    await waitFor(
      tester,
      () =>
          find.byType(InkCanvas).evaluate().isNotEmpty &&
          tester
              .widget<InkCanvas>(find.byType(InkCanvas))
              .controller
              .ready
              .value,
      'Native source reopens after a new app instance',
    );
    expect(find.text('HTML needs refresh'), findsOneWidget);
    await tester.tap(find.text('HTML'));
    await tester.pumpAndSettle();
    expect(find.byType(AppKitView), findsNothing);
    expect(find.byType(UiKitView), findsWidgets);
    expect(tester.takeException(), isNull);
    // The host can retrieve screenshots from this disposable test directory.
    debugPrint('StudyHub synthetic-flow artifacts: ${directory.path}');
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
