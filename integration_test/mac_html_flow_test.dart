import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:studyhub/app/study_hub_app.dart';
import 'package:studyhub/domain/lecture_content.dart';
import 'package:studyhub/domain/library.dart';
import 'package:studyhub/persistence/lecture_content_store.dart';
import 'package:studyhub/persistence/library_store.dart';

import 'lecture_flow_test.dart' show waitFor;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('macOS reads static native HTML and preserves its source', (
    tester,
  ) async {
    final directory = await Directory.systemTemp.createTemp('studyhub-mac-');
    final library = JsonLibraryStore(File('${directory.path}/library.json'));
    final content = JsonLectureContentStore(
      Directory('${directory.path}/content'),
    );
    const lecture = Lecture(
      id: 'native-html-test',
      title: 'Native HTML test',
      notes: 'Synthetic source: force equals mass times acceleration.',
    );
    await library.save(
      StudyLibrary(
        classes: [
          StudyClass(
            id: 'physics-test',
            title: 'Physics test',
            lectures: [lecture],
          ),
        ],
      ),
    );
    await content.save(
      LectureContent(lectureId: lecture.id).withHtml(
        '''<!doctype html><html><body><h1>Motion &amp; forces</h1>
<p>Synthetic native macOS rendering test.</p>
<math display="block" aria-label="Force equals mass times acceleration"><mi>F</mi><mo>=</mo><mi>m</mi><mi>a</mi></math>
<svg viewBox="0 0 520 180" role="img" aria-label="A block with a force to the right">
<rect x="50" y="40" width="120" height="90" rx="12" fill="#e4efe8" stroke="#315b47"/>
<text x="110" y="90" text-anchor="middle" fill="#193e2c">mass m</text>
<path d="M170 85 H410 M390 65 L410 85 L390 105" fill="none" stroke="#315b47" stroke-width="4"/>
<text x="300" y="60" text-anchor="middle" fill="#193e2c">force F</text></svg>
</body></html>''',
        sourceRevision: 0,
        provider: 'Synthetic fixture',
      ),
    );
    final support = await getApplicationSupportDirectory();
    expect(support.isAbsolute, isTrue);
    debugPrint('StudyHub native macOS support path: ${support.path}');
    await tester.pumpWidget(
      StudyHubApp(
        openStore: () async => library,
        openContentStore: () async => content,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Physics test'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Native HTML test'));
    await tester.pumpAndSettle();
    expect(find.text('Handwriting is available on iPad.'), findsOneWidget);
    await tester.tap(find.text('HTML'));
    await tester.pump();
    await waitFor(
      tester,
      () =>
          find.byKey(const ValueKey('html-preview-loading')).evaluate().isEmpty,
      'Native macOS WebKit finished loading',
    );
    expect(
      find.text('The HTML preview could not open. Your notes are safe.'),
      findsNothing,
    );
    expect(find.byType(AppKitView), findsOneWidget);
    expect(
      (await library.load()).classes.single.lectures.single.notes,
      lecture.notes,
    );
    expect((await content.load(lecture.id)).hasHtml, isTrue);
    expect(tester.takeException(), isNull);
    debugPrint('StudyHub synthetic macOS artifacts: ${directory.path}');
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
