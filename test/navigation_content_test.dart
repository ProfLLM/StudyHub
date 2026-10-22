import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyhub/app/lecture_workspace.dart';
import 'package:studyhub/app/study_hub_app.dart';
import 'package:studyhub/domain/lecture_content.dart';
import 'package:studyhub/domain/library.dart';
import 'package:studyhub/ink/ink_canvas.dart';
import 'package:studyhub/persistence/lecture_content_store.dart';
import 'package:studyhub/persistence/library_store.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGP4DwQACfsD/fteaysAAAAASUVORK5CYII=',
);

StudyLibrary _library() => StudyLibrary(
  classes: [
    StudyClass(
      id: 'physics',
      title: 'Physics',
      lectures: const [
        Lecture(id: 'motion', title: 'Motion'),
        Lecture(id: 'energy', title: 'Energy'),
      ],
    ),
    StudyClass(
      id: 'history',
      title: 'History',
      lectures: const [Lecture(id: 'dates', title: 'Dates')],
    ),
  ],
);

class _LibraryStore implements LibraryStore {
  _LibraryStore(this.events);
  final List<String> events;
  StudyLibrary library = _library();
  bool failSave = false;
  int saves = 0;

  @override
  Future<StudyLibrary> load() async => library;

  @override
  Future<void> save(StudyLibrary next) async {
    saves++;
    events.add('library.save');
    if (failSave) throw StateError('Synthetic library disk failure');
    library = next;
  }
}

class _ContentStore implements LectureContentStore {
  _ContentStore(this.events);
  final List<String> events;
  final content = {
    for (final id in ['motion', 'energy', 'dates'])
      id: LectureContent(lectureId: id)
          .withInk(drawing: Uint8List.fromList([1]), preview: _png),
  };
  bool failSave = false;
  final failDelete = <String>{};
  Future<void>? pendingSave;
  final deleted = <String>[];
  int saveCalls = 0;

  @override
  Future<LectureContent> load(String lectureId) async =>
      content[lectureId] ?? LectureContent(lectureId: lectureId);

  @override
  Future<void> save(LectureContent next) async {
    saveCalls++;
    await pendingSave;
    if (failSave) throw StateError('Synthetic notes disk failure');
    content[next.lectureId] = next;
    events.add('content.save:${next.lectureId}');
  }

  @override
  Future<void> delete(String lectureId) async {
    events.add('content.delete:$lectureId');
    deleted.add(lectureId);
    if (failDelete.contains(lectureId)) {
      throw StateError('Synthetic delete failure');
    }
    content.remove(lectureId);
  }
}

// Parent navigation uses the production workspace/controller. Native channels
// are fixtures here; real PKDrawing and PencilKit behavior has native coverage.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final nativeChannels = <MethodChannel>[];
  final sources = <int, Map<String, Object>>{};
  final activity = <bool>[];
  late List<String> events;
  late _LibraryStore library;
  late _ContentStore notes;
  var failFlush = false;

  setUp(() {
    events = [];
    library = _LibraryStore(events);
    notes = _ContentStore(events);
    failFlush = false;
    sources.clear();
    activity.clear();
    nativeChannels.clear();
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method != 'create') return null;
      final args = call.arguments as Map;
      final id = args['id'] as int;
      final channel = MethodChannel('studyhub/ink/$id');
      nativeChannels.add(channel);
      sources[id] = {
        'drawing': Uint8List.fromList([1]),
        'preview': _png,
        'changeId': 0,
      };
      messenger.setMockMethodCallHandler(channel, (command) async {
        if (command.method == 'setActive') {
          activity.add(command.arguments as bool);
        }
        if (command.method == 'flush') {
          if (failFlush) {
            throw PlatformException(
              code: 'flush',
              message: 'Synthetic native flush failure',
            );
          }
          return sources[id];
        }
        return null;
      });
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    for (final channel in nativeChannels) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  void navigationTest(String description, WidgetTesterCallback callback) {
    testWidgets(
      description,
      callback,
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  }

  Future<void> mount(
    WidgetTester tester, {
    Future<LectureContentStore> Function()? openNotes,
  }) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      StudyHubApp(
        openStore: () async => library,
        openContentStore: openNotes ?? () async => notes,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openMotion(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(ListTile, 'Physics'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Motion'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<LectureWorkspace>(find.byType(LectureWorkspace)).lecture.id,
      'motion',
    );
  }

  void write(WidgetTester tester, {int changeId = 1, int byte = 9}) {
    final update = InkDrawingUpdate(
      drawing: Uint8List.fromList([byte]),
      preview: _png,
      changeId: changeId,
    );
    sources[sources.keys.last] = {
      'drawing': update.drawing,
      'preview': update.preview,
      'changeId': update.changeId,
    };
    tester.widget<InkCanvas>(find.byType(InkCanvas)).onChanged(update);
  }

  Future<void> advance(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
  }

  Future<void> confirmDelete(WidgetTester tester, String tooltip) async {
    await tester.tap(find.byTooltip(tooltip));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await advance(tester);
  }

  navigationTest(
    'content-store opening failure blocks edits and retries without rewriting either store',
    (tester) async {
      var failOpen = true;
      await mount(
        tester,
        openNotes: () async {
          if (failOpen) {
            throw StateError('Synthetic notes directory permission failure');
          }
          return notes;
        },
      );
      expect(find.text('Could not open your library.'), findsOneWidget);
      expect(find.text('New class'), findsNothing);
      expect(library.saves, 0);
      expect(notes.saveCalls, 0);
      expect(notes.deleted, isEmpty);
      failOpen = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      await openMotion(tester);
      expect(library.saves, 0);
      expect(notes.saveCalls, 0);
      expect(tester.widget<InkCanvas>(find.byType(InkCanvas)).initialDrawing, [
        1,
      ]);
    },
  );

  navigationTest(
    'sidebar navigation waits for durable ink and ignores a second navigation while leaving',
    (tester) async {
      await mount(tester);
      await openMotion(tester);
      final pending = Completer<void>();
      notes.pendingSave = pending.future;
      write(tester);
      await advance(tester);
      await tester.tap(find.widgetWithText(ListTile, 'History'));
      await advance(tester);
      // Metadata actions cannot race the pending navigation's library snapshot.
      await tester.tap(find.byTooltip('Class actions: Physics'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(library.saves, 0);
      await tester.tap(find.widgetWithText(TextButton, 'Classes'));
      await advance(tester);
      expect(find.byType(LectureWorkspace), findsOneWidget);
      expect(find.text('Saving…'), findsOneWidget);
      expect(notes.content['motion']!.drawing, [1]);
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.byType(LectureWorkspace), findsNothing);
      expect(find.text('Dates'), findsOneWidget);
      expect(notes.content['motion']!.drawing, [9]);
      expect(notes.content['motion']!.inkRevision, 2);
    },
  );

  navigationTest(
    'failed notes save prevents parent navigation until the latest source is retried',
    (tester) async {
      await mount(tester);
      await openMotion(tester);
      notes.failSave = true;
      write(tester, byte: 11);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'History'));
      await tester.pumpAndSettle();
      expect(find.byType(LectureWorkspace), findsOneWidget);
      expect(find.text('Not saved'), findsOneWidget);
      expect(notes.content['motion']!.drawing, [1]);
      notes.failSave = false;
      await tester.tap(find.text('Retry saving'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'History'));
      await tester.pumpAndSettle();
      expect(find.text('Dates'), findsOneWidget);
      expect(notes.content['motion']!.drawing, [11]);
    },
  );

  navigationTest('native final-flush failure keeps the selected lecture open', (
    tester,
  ) async {
    await mount(tester);
    await openMotion(tester);
    failFlush = true;
    await tester.tap(find.widgetWithText(ListTile, 'History'));
    await tester.pumpAndSettle();
    expect(find.byType(LectureWorkspace), findsOneWidget);
    expect(find.textContaining('Could not finish saving'), findsOneWidget);
    expect(notes.saveCalls, 0);
    failFlush = false;
    await tester.tap(find.widgetWithText(ListTile, 'History'));
    await tester.pumpAndSettle();
    expect(find.text('Dates'), findsOneWidget);
  });

  for (final cancel in [true, false]) {
    navigationTest(
      '${cancel ? 'canceling' : 'failing'} New class restores input to its retained lecture',
      (tester) async {
        await mount(tester);
        await openMotion(tester);
        await tester.tap(find.text('New class'));
        await tester.pumpAndSettle();
        expect(activity, contains(false));
        if (cancel) {
          await tester.tap(find.text('Cancel'));
        } else {
          library.failSave = true;
          await tester.enterText(find.byType(TextFormField), 'Biology');
          await tester.tap(find.widgetWithText(FilledButton, 'Create'));
        }
        await tester.pumpAndSettle();
        expect(find.byType(LectureWorkspace), findsOneWidget);
        expect(library.library.classes, hasLength(2));
        expect(activity.last, isTrue);
        write(tester, byte: 13);
        await tester.pumpAndSettle();
        expect(notes.content['motion']!.drawing, [13]);
      },
    );
  }

  navigationTest(
    'deleting another class resumes the retained lecture and preserves its sidecars',
    (tester) async {
      await mount(tester);
      await openMotion(tester);
      await confirmDelete(tester, 'Class actions: History');
      await tester.pumpAndSettle();
      expect(library.library.classes.single.id, 'physics');
      expect(notes.deleted, ['dates']);
      expect(find.byType(LectureWorkspace), findsOneWidget);
      expect(activity, contains(false));
      expect(activity.last, isTrue);
      write(tester, byte: 15);
      await tester.pumpAndSettle();
      expect(notes.content['motion']!.drawing, [15]);
      expect(notes.content['energy']!.drawing, [1]);
    },
  );

  navigationTest(
    'deleting the open lecture removes only its notes after library save',
    (tester) async {
      await mount(tester);
      await openMotion(tester);
      await confirmDelete(tester, 'Lecture actions: Motion');
      await tester.pumpAndSettle();
      expect(
        library.library.classes.first.lectures.map((lecture) => lecture.id),
        ['energy'],
      );
      expect(notes.deleted, ['motion']);
      expect(notes.content.keys, containsAll(['energy', 'dates']));
      expect(notes.content.containsKey('motion'), isFalse);
      expect(events, ['library.save', 'content.delete:motion']);
      expect(find.byType(LectureWorkspace), findsNothing);
    },
  );

  navigationTest(
    'class deletion waits for current ink then cleans all nested sidecars only',
    (tester) async {
      await mount(tester);
      await openMotion(tester);
      final pending = Completer<void>();
      notes.pendingSave = pending.future;
      write(tester);
      await advance(tester);
      await confirmDelete(tester, 'Class actions: Physics');
      expect(library.saves, 0);
      expect(notes.deleted, isEmpty);
      expect(find.byType(LectureWorkspace), findsOneWidget);
      pending.complete();
      await tester.pumpAndSettle();
      expect(library.library.classes.single.id, 'history');
      expect(notes.deleted, ['motion', 'energy']);
      expect(notes.content.keys, ['dates']);
      expect(events, [
        'content.save:motion',
        'library.save',
        'content.delete:motion',
        'content.delete:energy',
      ]);
    },
  );

  for (final kind in ['Lecture', 'Class']) {
    navigationTest(
      'failed $kind deletion leaves library and every sidecar untouched',
      (tester) async {
        await mount(tester);
        await openMotion(tester);
        library.failSave = true;
        await confirmDelete(
          tester,
          kind == 'Lecture'
              ? 'Lecture actions: Motion'
              : 'Class actions: Physics',
        );
        await tester.pumpAndSettle();
        expect(library.library.classes.first.lectures, hasLength(2));
        expect(notes.deleted, isEmpty);
        expect(notes.content.keys, containsAll(['motion', 'energy', 'dates']));
        expect(find.byType(LectureWorkspace), findsOneWidget);
        expect(
          find.text('Could not save. Your change was not applied. Try again.'),
          findsOneWidget,
        );
      },
    );
  }

  navigationTest(
    'one failed sidecar cleanup reports the retained file and continues remaining cleanup',
    (tester) async {
      await mount(tester);
      await openMotion(tester);
      notes.failDelete.add('motion');
      await confirmDelete(tester, 'Class actions: Physics');
      await tester.pumpAndSettle();
      expect(library.library.classes.single.id, 'history');
      expect(notes.deleted, ['motion', 'energy']);
      expect(notes.content.keys, containsAll(['motion', 'dates']));
      expect(notes.content.containsKey('energy'), isFalse);
      expect(
        find.text(
          'The item was deleted, but its local notes file could not be removed.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
