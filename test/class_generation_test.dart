import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyhub/ai/class_generation_provider.dart';
import 'package:studyhub/ai/lecture_enrichment_provider.dart';
import 'package:studyhub/app/class_creator.dart';
import 'package:studyhub/app/study_hub_app.dart';
import 'package:studyhub/domain/lecture_content.dart';
import 'package:studyhub/domain/library.dart';
import 'package:studyhub/enrichment/class_draft.dart';
import 'package:studyhub/persistence/generated_class_writer.dart';
import 'package:studyhub/persistence/lecture_content_store.dart';
import 'package:studyhub/persistence/library_store.dart';

String draftJson() => jsonEncode({
  'title': 'Learn mechanics',
  'lectures': [
    {
      'title': 'Motion',
      'html': '<h1>Motion</h1><p>Velocity describes change in position.</p><h2>Worked example</h2><p>A 10 m trip in 2 seconds has average speed 5 m/s.</p>',
    },
    {
      'title': 'Forces',
      'html': '<h1>Forces</h1><p>A net force changes velocity.</p><details><summary>Check your understanding</summary><p>Balanced forces do not change velocity.</p></details>',
    },
  ],
});

class _Library implements LibraryStore {
  StudyLibrary value = StudyLibrary(
    classes: [StudyClass(id: 'existing', title: 'Keep me')],
  );
  bool fail = false;
  int saves = 0;
  @override
  Future<StudyLibrary> load() async => value;
  @override
  Future<void> save(StudyLibrary next) async {
    saves++;
    if (fail) throw StateError('Synthetic write failure');
    value = next;
  }
}

class _Content implements LectureContentStore {
  final data = <String, LectureContent>{};
  int saves = 0;
  int? failAt;
  bool failDelete = false;
  @override
  Future<LectureContent> load(String id) async =>
      data[id] ?? LectureContent(lectureId: id);
  @override
  Future<void> save(LectureContent value) async {
    saves++;
    if (saves == failAt) throw StateError('Synthetic content failure');
    data[value.lectureId] = value;
  }

  @override
  Future<void> delete(String id) async {
    if (failDelete) throw StateError('Synthetic cleanup failure');
    data.remove(id);
  }
}

class _Provider implements LectureEnrichmentProvider, ClassGenerationProvider {
  int calls = 0, cancels = 0, connects = 0;
  bool connected = true;
  String? request;
  Completer<String>? pending;
  Completer<bool>? status;
  @override
  String get name => 'ChatGPT';
  @override
  Future<bool> get isConnected async => status?.future ?? connected;
  @override
  Future<void> connect() async {
    connects++;
    connected = true;
  }

  @override
  Future<void> disconnect() async {
    connected = false;
  }

  @override
  void cancel() {
    cancels++;
  }

  @override
  Future<String> generateClass({required String request}) async {
    calls++;
    this.request = request;
    return pending?.future ?? draftJson();
  }

  @override
  Future<String> generate({
    required images,
    required String lectureTitle,
    required String sourceNotes,
  }) async => throw UnimplementedError();
}

Future<void> _advance(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

Future<void> _start(
  WidgetTester tester,
  _Provider provider,
  _Library library,
  _Content content,
) async {
  await tester.pumpWidget(
    StudyHubApp(
      openStore: () async => library,
      openContentStore: () async => content,
      providers: [provider],
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Create class with ChatGPT').first);
  await _advance(tester);
  await tester.enterText(
    find.byType(TextField),
    'Teach me mechanics with worked examples.',
  );
  await tester.pump();
  await tester.tap(find.text('Generate class'));
  await _advance(tester);
}

void main() {
  test(
    'parser validates all lessons and removes active content before preview',
    () {
      final map = jsonDecode(draftJson()) as Map<String, dynamic>;
      (map['lectures'] as List).first['html'] +=
          '<script>steal()</script><input value="unsafe">';
      final draft = ClassDraft.parse(jsonEncode(map));
      expect(draft.lessons, hasLength(2));
      expect(draft.lessons.first.content.document, isNot(contains('steal()')));
      expect(draft.lessons.first.content.plainText, contains('5 m/s'));
      expect(draft.lessons.first.notes, contains('Motion\n\nVelocity'));
      expect(() => ClassDraft.parse('{broken'), throwsFormatException);
      for (final lectures in [
        [],
        [
          {'title': 'X', 'html': '<script>nothing()</script>'},
        ],
        List.filled(13, {'title': 'X', 'html': '<p>Lesson</p>'}),
      ]) {
        expect(
          () => ClassDraft.parse(
            jsonEncode({'title': 'Test', 'lectures': lectures}),
          ),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'new class commits complete lessons without changing library schema',
    () async {
      final dir = await Directory.systemTemp.createTemp('studyhub-class-');
      addTearDown(() => dir.delete(recursive: true));
      final library = JsonLibraryStore(File('${dir.path}/library.json'));
      final content = JsonLectureContentStore(Directory('${dir.path}/content'));
      final original = StudyLibrary(
        classes: [StudyClass(id: 'keep', title: 'Existing')],
      );
      await library.save(original);
      final saved = await GeneratedClassWriter(
        library,
        content,
      ).save(ClassDraft.parse(draftJson()), original);
      expect(saved.classes, hasLength(2));
      expect(saved.toJson()['schemaVersion'], 1);
      final added = saved.classes.last;
      expect(added.id, isNot('keep'));
      expect(added.lectures, hasLength(2));
      for (final lecture in added.lectures) {
        final page = await content.load(lecture.id);
        expect(page.hasHtml, true);
        expect(page.hasInk, false);
        expect(page.htmlSourceRevision, 0);
        expect(lecture.notes, isNotEmpty);
        expect(lecture.notes, isNot(contains('<h1>')));
      }
      expect((await library.load()).toJson(), saved.toJson());
    },
  );
  test('content and library failures never publish partial classes; retry needs no regeneration', () async {
    for (final failContent in [true, false]) {
      final library = _Library()..fail = !failContent;
      final content = _Content()..failAt = failContent ? 2 : null;
      final writer = GeneratedClassWriter(library, content);
      final draft = ClassDraft.parse(draftJson());
      await expectLater(
        writer.save(draft, library.value),
        throwsA(isA<ClassSaveException>()),
      );
      expect(library.value.classes.single.id, 'existing');
      expect(content.data, isEmpty);
      library.fail = false;
      content.failAt = null;
      final saved = await writer.save(draft, library.value);
      expect(saved.classes, hasLength(2));
    }
  });
  testWidgets(
    'prompt generates a populated preview, saves and opens teaching material',
    (tester) async {
      final provider = _Provider()..connected = false;
      final library = _Library();
      final content = _Content();
      await _start(tester, provider, library, content);
      await tester.pumpAndSettle();
      expect(provider.calls, 1);
      expect(provider.connects, 1);
      expect(provider.request, 'Teach me mechanics with worked examples.');
      expect(library.value.classes, hasLength(1));
      expect(content.data, isEmpty);
      expect(find.textContaining('average speed 5 m/s'), findsOneWidget);
      await tester.tap(find.text('Save class'));
      await tester.pumpAndSettle();
      expect(find.byType(ClassCreator), findsNothing);
      expect(library.value.classes, hasLength(2));
      expect(content.data, hasLength(2));
      expect(find.textContaining('average speed 5 m/s'), findsOneWidget);
      expect(find.text('Keep me'), findsOneWidget);
    },
  );

  test('failed cleanup reports unfinished files without touching existing lectures', () async {
    final library = _Library()..fail = true;
    final content = _Content()..failDelete = true;
    content.data['keep-lecture'] = LectureContent(
      lectureId: 'keep-lecture',
    ).withHtml('<p>Keep original</p>', sourceRevision: 0, provider: 'Original');
    await expectLater(
      GeneratedClassWriter(
        library,
        content,
      ).save(ClassDraft.parse(draftJson()), library.value),
      throwsA(
        isA<ClassSaveException>().having(
          (e) => e.cleanupComplete,
          'cleanup',
          false,
        ),
      ),
    );
    expect(library.value.classes.single.id, 'existing');
    expect(content.data['keep-lecture']!.html, contains('Keep original'));
  });
  testWidgets(
    'save failure keeps the preview and retry does not call ChatGPT again',
    (tester) async {
      final provider = _Provider();
      final library = _Library()..fail = true;
      final content = _Content();
      await _start(tester, provider, library, content);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save class'));
      await tester.pumpAndSettle();
      expect(find.byType(ClassCreator), findsOneWidget);
      expect(content.data, isEmpty);
      expect(library.value.classes, hasLength(1));
      library.fail = false;
      await tester.tap(find.text('Save class'));
      await tester.pumpAndSettle();
      expect(provider.calls, 1);
      expect(library.value.classes, hasLength(2));
    },
  );
  testWidgets(
    'cancel ignores a late result and delayed account status never starts sign-in',
    (tester) async {
      for (final delayStatus in [false, true]) {
        final provider = _Provider();
        if (delayStatus) {
          provider.status = Completer<bool>();
        } else {
          provider.pending = Completer<String>();
        }
        final library = _Library();
        final content = _Content();
        await _start(tester, provider, library, content);
        await tester.tap(find.text('Cancel generation'));
        await _advance(tester);
        if (delayStatus) {
          provider.status!.complete(false);
        } else {
          provider.pending!.complete(draftJson());
        }
        await tester.pumpAndSettle();
        expect(find.text('Save class'), findsNothing);
        expect(provider.connects, 0);
        expect(library.saves, 0);
        expect(content.data, isEmpty);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
  testWidgets('creator fits a narrow screen', (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final p = _Provider();
    await _start(tester, p, _Library(), _Content());
    await tester.pumpAndSettle();
    expect(find.text('Save class'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
