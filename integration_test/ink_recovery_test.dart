import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:studyhub/app/study_hub_app.dart';
import 'package:studyhub/app/lecture_workspace.dart';
import 'package:studyhub/domain/lecture_content.dart';
import 'package:studyhub/domain/library.dart';
import 'package:studyhub/ink/ink_canvas.dart';
import 'package:studyhub/persistence/lecture_content_store.dart';
import 'package:studyhub/persistence/library_store.dart';

import 'lecture_flow_test.dart' show waitFor;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'unreadable native ink permits safe leave, retry and confirmed deletion',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'studyhub-ink-recovery-',
      );
      final library = JsonLibraryStore(File('${directory.path}/library.json'));
      final content = JsonLectureContentStore(
        Directory('${directory.path}/content'),
      );
      const lecture = Lecture(
        id: 'broken-ink',
        title: 'Unreadable synthetic ink',
      );
      await library.save(
        StudyLibrary(
          classes: [
            StudyClass(
              id: 'recovery',
              title: 'Recovery test',
              lectures: [lecture],
            ),
          ],
        ),
      );
      final source = LectureContent(lectureId: lecture.id).withInk(
        drawing: Uint8List.fromList([0xde, 0xad]),
        preview: base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGP4DwQACfsD/fteaysAAAAASUVORK5CYII=',
        ),
      );
      await content.save(source);
      Widget app() => StudyHubApp(
        openStore: () async => library,
        openContentStore: () async => content,
        providers: const [],
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Recovery test'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(lecture.title));
      await waitFor(
        tester,
        () =>
            find.byType(InkCanvas).evaluate().isNotEmpty &&
            tester
                .widget<InkCanvas>(find.byType(InkCanvas))
                .controller
                .initializationFailed
                .value,
        'Actual PencilKit rejects the invalid drawing',
      );
      await tester.pumpAndSettle();
      expect(find.text('Retry opening ink'), findsOneWidget);
      await binding.takeScreenshot('studyhub-ink-recovery');
      await tester.tap(find.text('Retry opening ink'));
      await waitFor(
        tester,
        () => tester
            .widget<InkCanvas>(find.byType(InkCanvas))
            .controller
            .initializationFailed
            .value,
        'Retry safely rejects the same invalid source',
      );
      await tester.tap(find.widgetWithText(TextButton, 'Recovery test'));
      await waitFor(
        tester,
        () => find.byType(LectureWorkspace).evaluate().isEmpty,
        'Leaving unreadable source does not require a flush',
      );
      final saved = (await tester.runAsync(() => content.load(lecture.id)))!;
      expect(saved.toJson(), source.toJson());
      await tester.tap(find.text(lecture.title));
      await waitFor(
        tester,
        () =>
            find.byType(InkCanvas).evaluate().isNotEmpty &&
            tester
                .widget<InkCanvas>(find.byType(InkCanvas))
                .controller
                .initializationFailed
                .value,
        'Unmodified unreadable source can reopen',
      );
      await tester.tap(find.byTooltip('Lecture actions: ${lecture.title}'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await waitFor(
        tester,
        () => find.byType(LectureWorkspace).evaluate().isEmpty,
        'Confirmed deletion can leave the failed native view',
      );
      expect(
        (await tester.runAsync(library.load))!.classes.single.lectures,
        isEmpty,
      );
      expect(
        (await tester.runAsync(() => content.load(lecture.id)))!.hasInk,
        isFalse,
      );
      expect(await content.directory.list().toList(), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
