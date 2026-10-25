import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyhub/ai/lecture_enrichment_provider.dart';
import 'package:studyhub/app/lecture_workspace.dart';
import 'package:studyhub/domain/lecture_content.dart';
import 'package:studyhub/domain/library.dart';
import 'package:studyhub/ink/ink_canvas.dart';
import 'package:studyhub/persistence/lecture_content_store.dart';

// A real, white 1x1 RGBA PNG keeps Image.memory on its ordinary decoding path.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGP4DwQACfsD/fteaysAAAAASUVORK5CYII=',
);
const _lecture = Lecture(
  id: 'lecture-1',
  title: 'Forces and motion',
  notes: 'The learner’s existing typed source notes.',
);

LectureContent _ink({String? html}) {
  final content = LectureContent(lectureId: _lecture.id)
      .withInk(drawing: Uint8List.fromList([1, 2, 3]), preview: _png);
  return html == null
      ? content
      : content.withHtml(html, sourceRevision: 1, provider: 'Claude');
}

InkSnapshot _snapshot({
  int changeId = 0,
  List<int> drawing = const [1, 2, 3],
}) => InkSnapshot(
  drawing: Uint8List.fromList(drawing),
  preview: _png,
  images: [_png],
  changeId: changeId,
);

class _MemoryStore implements LectureContentStore {
  _MemoryStore(this.content);

  LectureContent content;
  bool failLoad = false;
  bool failSave = false;
  Future<void>? pendingSave;
  Future<void> Function(LectureContent)? beforeSave;
  final saved = <LectureContent>[];

  @override
  Future<LectureContent> load(String lectureId) async {
    if (failLoad) throw StateError('Synthetic read failure');
    expect(lectureId, content.lectureId);
    return content;
  }

  @override
  Future<void> save(LectureContent next) async {
    await pendingSave;
    await beforeSave?.call(next);
    if (failSave) throw StateError('Synthetic disk failure');
    content = next;
    saved.add(next);
  }

  @override
  Future<void> delete(String lectureId) async {
    content = LectureContent(lectureId: lectureId);
  }
}

class _InkController extends InkCanvasController {
  _InkController() {
    ready.value = true;
  }

  InkSnapshot snapshot = _snapshot();
  Future<InkSnapshot>? pendingSnapshot;
  bool failFlush = false;
  bool active = true;

  @override
  Future<void> setActive(bool value) async => active = value;

  @override
  Future<InkDrawingUpdate?> flush() async {
    if (failFlush) throw StateError('Synthetic flush failure');
    return null;
  }

  @override
  Future<InkSnapshot> captureSnapshot() async => pendingSnapshot ?? snapshot;

  @override
  Future<List<Uint8List>> exportImages() async => snapshot.images;
}

class _Provider implements LectureEnrichmentProvider {
  _Provider({this.name = 'ChatGPT'});

  @override
  final String name;
  String result = '<h1>Beautiful notes</h1>';
  Object? failure;
  Future<String>? pendingResult;
  Future<void>? pendingDisconnect;
  Object? disconnectFailure;
  bool connected = true;
  Future<bool>? pendingConnectionStatus;
  int connects = 0;
  int calls = 0;
  int cancels = 0;
  List<Uint8List>? receivedImages;
  String? receivedTitle;
  String? receivedNotes;

  @override
  Future<bool> get isConnected async => pendingConnectionStatus ?? connected;

  @override
  Future<void> connect() async {
    connects++;
    connected = true;
  }

  @override
  Future<String> generate({
    required List<Uint8List> images,
    required String lectureTitle,
    required String sourceNotes,
  }) async {
    calls++;
    receivedImages = images.map(Uint8List.fromList).toList();
    receivedTitle = lectureTitle;
    receivedNotes = sourceNotes;
    final error = failure;
    if (error != null) throw error;
    return pendingResult ?? result;
  }

  @override
  void cancel() => cancels++;

  @override
  Future<void> disconnect() async {
    await pendingDisconnect;
    connected = false;
    final error = disconnectFailure;
    if (error != null) throw error;
  }
}

Future<void> _mount(
  WidgetTester tester, {
  required _MemoryStore store,
  required _InkController ink,
  List<LectureEnrichmentProvider> providers = const [],
  GlobalKey<LectureWorkspaceState>? key,
  Lecture lecture = _lecture,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: LectureWorkspace(
          key: key,
          lecture: lecture,
          store: store,
          providers: providers,
          inkController: ink,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _write(WidgetTester tester, {int changeId = 1, int byte = 9}) {
  tester
      .widget<InkCanvas>(find.byType(InkCanvas))
      .onChanged(
        InkDrawingUpdate(
          drawing: Uint8List.fromList([byte]),
          preview: _png,
          changeId: changeId,
        ),
      );
}

// Indeterminate progress indicators intentionally keep ticking during a request.
Future<void> _advance(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

Future<void> _send(WidgetTester tester, {String provider = 'ChatGPT'}) async {
  await tester.tap(find.text('Create HTML with $provider'));
  await _advance(tester);
  expect(find.text('Create HTML with $provider?'), findsOneWidget);
  await tester.tap(find.text('Send notes'));
  await _advance(tester);
}

void main() {
  testWidgets(
    'reopens source ink and saved HTML, with independent view switching',
    (tester) async {
      final store = _MemoryStore(_ink(html: '<h1>Old version</h1>'));
      await _mount(tester, store: store, ink: _InkController());
      expect(tester.widget<InkCanvas>(find.byType(InkCanvas)).initialDrawing, [
        1,
        2,
        3,
      ]);
      expect(find.text('Old version'), findsNothing);
      await tester.tap(find.text('HTML'));
      await tester.pumpAndSettle();
      expect(find.text('Old version'), findsOneWidget);
      await tester.tap(find.text('Ink'));
      await tester.pumpAndSettle();
      expect(find.text('Old version'), findsNothing);
      expect(store.saved, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      await _mount(tester, store: store, ink: _InkController());
      await tester.tap(find.text('HTML'));
      await tester.pumpAndSettle();
      expect(find.text('Old version'), findsOneWidget);
      expect(store.content.drawing, [1, 2, 3]);
    },
  );

  testWidgets(
    'successful generation preserves ink and exposes its separate rendition',
    (tester) async {
      final store = _MemoryStore(_ink());
      final original = store.content;
      final provider = _Provider()..connected = false;
      await _mount(
        tester,
        store: store,
        ink: _InkController(),
        providers: [provider],
      );
      await _send(tester);
      expect(provider.calls, 1);
      expect(provider.connects, 1);
      expect(provider.receivedImages!.single, _png);
      expect(provider.receivedTitle, _lecture.title);
      expect(provider.receivedNotes, _lecture.notes);
      expect(store.content.drawing, original.drawing);
      expect(store.content.preview, original.preview);
      expect(store.content.inkRevision, original.inkRevision);
      expect(store.content.htmlSourceRevision, original.inkRevision);
      expect(store.content.htmlProvider, 'ChatGPT');
      expect(
        find.text('HTML is ready. Your ink is unchanged.'),
        findsOneWidget,
      );
      expect(find.text('Beautiful notes'), findsNothing);
      await tester.tap(find.text('View HTML'));
      await tester.pumpAndSettle();
      expect(find.text('Beautiful notes'), findsOneWidget);
    },
  );

  testWidgets(
    'selects Claude and requires confirmation before sending any source',
    (tester) async {
      final chatgpt = _Provider();
      final claude = _Provider(name: 'Claude');
      await _mount(
        tester,
        store: _MemoryStore(_ink()),
        ink: _InkController(),
        providers: [chatgpt, claude],
      );
      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Claude').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create HTML with Claude'));
      await _advance(tester);
      expect(chatgpt.calls, 0);
      expect(claude.calls, 0);
      expect(find.textContaining('1 image from this Lecture'), findsOneWidget);
      await tester.tap(find.text('Cancel').last);
      await _advance(tester);
      expect(claude.calls, 0);
      await _send(tester, provider: 'Claude');
      expect(claude.calls, 1);
      expect(chatgpt.calls, 0);
    },
  );

  testWidgets(
    'new ink makes saved HTML stale without replacing either source',
    (tester) async {
      const html = '<h1>Old version</h1>';
      final store = _MemoryStore(_ink(html: html));
      await _mount(tester, store: store, ink: _InkController());
      _write(tester);
      await tester.pumpAndSettle();
      expect(store.content.inkRevision, 2);
      expect(store.content.drawing, [9]);
      expect(store.content.html, html);
      expect(store.content.htmlSourceRevision, 1);
      expect(find.text('HTML needs refresh'), findsOneWidget);
      await tester.tap(find.text('HTML'));
      await tester.pumpAndSettle();
      expect(find.text('Old version'), findsOneWidget);
    },
  );

  testWidgets(
    'sign-out disables account changes and new conversion until complete',
    (tester) async {
      final pending = Completer<void>();
      final provider = _Provider()..pendingDisconnect = pending.future;
      await _mount(
        tester,
        store: _MemoryStore(_ink()),
        ink: _InkController(),
        providers: [
          provider,
          _Provider(name: 'Claude'),
        ],
      );
      await tester.tap(find.text('Disconnect ChatGPT'));
      await _advance(tester);
      expect(find.text('Disconnecting…'), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
      expect(
        tester
            .widget<DropdownButton<int>>(find.byType(DropdownButton<int>))
            .onChanged,
        isNull,
      );
      final generateButton = find.ancestor(
        of: find.text('Create HTML with ChatGPT'),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton),
      );
      expect(tester.widget<FilledButton>(generateButton).onPressed, isNull);
      expect(provider.calls, 0);
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('Connect ChatGPT'), findsOneWidget);
      expect(find.text('Disconnecting…'), findsNothing);
    },
  );

  testWidgets('local sign-out preserves a remote-revocation warning', (
    tester,
  ) async {
    const warning =
        'Signed out on this device. Remote revocation could not be confirmed; disconnect StudyHub in ChatGPT settings.';
    final provider = _Provider()
      ..disconnectFailure = const EnrichmentException(warning);
    final store = _MemoryStore(_ink());
    await _mount(
      tester,
      store: store,
      ink: _InkController(),
      providers: [provider],
    );
    await tester.tap(find.text('Disconnect ChatGPT'));
    await tester.pumpAndSettle();
    expect(find.text(warning), findsOneWidget);
    expect(find.text('Connect ChatGPT'), findsOneWidget);
    expect(store.content.drawing, [1, 2, 3]);
    expect(store.saved, isEmpty);
  });

  for (final invalidHtml in [false, true]) {
    testWidgets(
      '${invalidHtml ? 'invalid HTML' : 'provider failure'} retains previous HTML and editable ink',
      (tester) async {
        const html = '<h1>Old version</h1>';
        final store = _MemoryStore(_ink(html: html));
        final provider = _Provider();
        if (invalidHtml) {
          provider.result = '<script>Only executable content</script>';
        } else {
          provider.failure = StateError('Synthetic network failure');
        }
        await _mount(
          tester,
          store: store,
          ink: _InkController(),
          providers: [provider],
        );
        await _send(tester);
        expect(store.content.drawing, [1, 2, 3]);
        expect(store.content.html, html);
        expect(store.saved, isEmpty);
        expect(
          find.textContaining(
            invalidHtml
                ? 'did not return usable HTML'
                : 'Could not create HTML',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('View HTML'));
        await tester.pumpAndSettle();
        expect(find.text('Old version'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'late capture and response preserve newer ink and mark HTML stale',
    (tester) async {
      final capture = Completer<InkSnapshot>();
      final result = Completer<String>();
      final controller = _InkController()..pendingSnapshot = capture.future;
      final provider = _Provider()..pendingResult = result.future;
      final store = _MemoryStore(_ink());
      await _mount(
        tester,
        store: store,
        ink: controller,
        providers: [provider],
      );
      await tester.tap(find.text('Create HTML with ChatGPT'));
      await _advance(tester);
      _write(tester, changeId: 1, byte: 8);
      await _advance(tester);
      capture.complete(_snapshot());
      await _advance(tester);
      expect(store.content.drawing, [8]);
      expect(store.content.inkRevision, 2);
      await tester.tap(find.text('Send notes'));
      await _advance(tester);
      _write(tester, changeId: 2, byte: 10);
      await _advance(tester);
      result.complete('<h1>Snapshot rendition</h1>');
      await _advance(tester);
      expect(store.content.drawing, [10]);
      expect(store.content.inkRevision, 3);
      expect(store.content.htmlSourceRevision, 1);
      expect(store.content.htmlIsStale, isTrue);
      expect(find.text('HTML needs refresh'), findsOneWidget);
    },
  );

  testWidgets('canceled generation ignores an eventual response', (
    tester,
  ) async {
    final pending = Completer<String>();
    const html = '<h1>Old version</h1>';
    final store = _MemoryStore(_ink(html: html));
    final provider = _Provider()..pendingResult = pending.future;
    await _mount(
      tester,
      store: store,
      ink: _InkController(),
      providers: [provider],
    );
    await _send(tester);
    expect(find.text('Cancel conversion'), findsOneWidget);
    await tester.tap(find.text('Cancel conversion'));
    await _advance(tester);
    expect(provider.cancels, 1);
    pending.complete('<h1>Must be ignored</h1>');
    await _advance(tester);
    expect(store.content.html, html);
    expect(store.saved, isEmpty);
    expect(find.text('HTML is ready. Your ink is unchanged.'), findsNothing);
    expect(find.text('Create HTML with ChatGPT'), findsOneWidget);
  });

  testWidgets('an older canceled response cannot replace a newer request', (
    tester,
  ) async {
    final first = Completer<String>();
    final second = Completer<String>();
    final provider = _Provider()..pendingResult = first.future;
    final store = _MemoryStore(_ink());
    await _mount(
      tester,
      store: store,
      ink: _InkController(),
      providers: [provider],
    );
    await _send(tester);
    await tester.tap(find.text('Cancel conversion'));
    await _advance(tester);
    provider.pendingResult = second.future;
    await _send(tester);
    first.complete('<h1>Older canceled result</h1>');
    await _advance(tester);
    expect(store.content.hasHtml, isFalse);
    expect(find.text('Creating HTML…'), findsOneWidget);
    second.complete('<h1>Latest result</h1>');
    await _advance(tester);
    expect(store.content.html, contains('Latest result'));
    expect(store.content.html, isNot(contains('Older canceled result')));
  });

  testWidgets(
    'disposing a workspace cancels its provider and ignores late results',
    (tester) async {
      final pending = Completer<String>();
      final provider = _Provider()..pendingResult = pending.future;
      final store = _MemoryStore(_ink());
      await _mount(
        tester,
        store: store,
        ink: _InkController(),
        providers: [provider],
      );
      await _send(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(provider.cancels, 1);
      pending.complete('<h1>Must be ignored</h1>');
      await _advance(tester);
      expect(store.content.hasHtml, isFalse);
      expect(store.saved, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('read failure preserves the file and supports retry', (
    tester,
  ) async {
    final store = _MemoryStore(_ink())..failLoad = true;
    await _mount(tester, store: store, ink: _InkController());
    expect(find.textContaining('Could not open these notes'), findsOneWidget);
    expect(find.byType(InkCanvas), findsNothing);
    expect(store.saved, isEmpty);
    store.failLoad = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byType(InkCanvas), findsOneWidget);
    expect(tester.widget<InkCanvas>(find.byType(InkCanvas)).initialDrawing, [
      1,
      2,
      3,
    ]);
  });

  testWidgets('save failure blocks leaving until retry saves the latest ink', (
    tester,
  ) async {
    final key = GlobalKey<LectureWorkspaceState>();
    final store = _MemoryStore(_ink())..failSave = true;
    await _mount(tester, key: key, store: store, ink: _InkController());
    _write(tester, byte: 11);
    await tester.pumpAndSettle();
    expect(find.text('Not saved'), findsOneWidget);
    expect(find.text('Retry saving'), findsOneWidget);
    expect(store.content.drawing, [1, 2, 3]);
    expect(await key.currentState!.prepareToLeave(), isFalse);
    store.failSave = false;
    await tester.tap(find.text('Retry saving'));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsOneWidget);
    expect(store.content.drawing, [11]);
    expect(store.content.inkRevision, 2);
    expect(await key.currentState!.prepareToLeave(), isTrue);
  });

  testWidgets(
    'leaving waits for the final durable save and cancels generation',
    (tester) async {
      final key = GlobalKey<LectureWorkspaceState>();
      final saved = Completer<void>();
      final store = _MemoryStore(_ink())..pendingSave = saved.future;
      final pending = Completer<String>();
      final provider = _Provider()..pendingResult = pending.future;
      await _mount(
        tester,
        key: key,
        store: store,
        ink: _InkController(),
        providers: [provider],
      );
      _write(tester);
      await _advance(tester);
      var resolved = false;
      final leaving = key.currentState!.prepareToLeave().then((value) {
        resolved = true;
        return value;
      });
      await _advance(tester);
      expect(resolved, isFalse);
      expect(find.text('Saving…'), findsOneWidget);
      expect(store.content.drawing, [1, 2, 3]);
      saved.complete();
      await _advance(tester);
      expect(await leaving, isTrue);
      expect(store.content.drawing, [9]);

      // A pending conversion is cancelable once its source is durably saved.
      await key.currentState!.resumeAfterNavigation();
      await tester.pumpAndSettle();
      await _send(tester);
      expect(await key.currentState!.prepareToLeave(), isTrue);
      expect(provider.cancels, 1);
      pending.complete('<h1>Arrived after leaving was approved</h1>');
      await _advance(tester);
      expect(store.content.hasHtml, isFalse);
    },
  );

  testWidgets(
    'leaving drains updates already in flight and resumes retained lectures',
    (tester) async {
      final key = GlobalKey<LectureWorkspaceState>();
      final first = Completer<void>();
      final second = Completer<void>();
      final ink = _InkController();
      final store = _MemoryStore(_ink())
        ..beforeSave = (content) =>
            content.inkRevision == 2 ? first.future : second.future;
      await _mount(tester, key: key, store: store, ink: ink);
      _write(tester, byte: 9);
      await _advance(tester);
      var resolved = false;
      final leaving = key.currentState!.prepareToLeave().then((value) {
        resolved = true;
        return value;
      });
      await _advance(tester);
      expect(ink.active, isFalse);
      // A native callback queued before input suspension can still arrive late.
      _write(tester, changeId: 2, byte: 10);
      first.complete();
      await _advance(tester);
      expect(resolved, isFalse);
      second.complete();
      await _advance(tester);
      expect(await leaving, isTrue);
      expect(store.content.inkRevision, 3);
      expect(store.content.drawing, [10]);
      expect(ink.active, isFalse);
      await key.currentState!.resumeAfterNavigation();
      await tester.pumpAndSettle();
      expect(ink.active, isTrue);
    },
  );

  testWidgets(
    'native flush failure blocks navigation and leaves source intact',
    (tester) async {
      final key = GlobalKey<LectureWorkspaceState>();
      final ink = _InkController()..failFlush = true;
      final store = _MemoryStore(_ink());
      await _mount(tester, key: key, store: store, ink: ink);
      expect(await key.currentState!.prepareToLeave(), isFalse);
      expect(ink.active, isTrue);
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not finish saving'), findsOneWidget);
      expect(store.content.drawing, [1, 2, 3]);
      ink.failFlush = false;
      expect(await key.currentState!.prepareToLeave(), isTrue);
    },
  );

  testWidgets('empty capture is never sent to a provider', (tester) async {
    final ink = _InkController()
      ..snapshot = InkSnapshot(
        drawing: Uint8List(1),
        preview: Uint8List(0),
        images: [],
        changeId: 0,
      );
    final provider = _Provider();
    await _mount(
      tester,
      store: _MemoryStore(LectureContent(lectureId: _lecture.id)),
      ink: ink,
      providers: [provider],
    );
    await tester.tap(find.text('Create HTML with ChatGPT'));
    await _advance(tester);
    expect(find.text('Write some notes before creating HTML.'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(provider.calls, 0);
  });

  testWidgets('long notes and messages remain usable in a narrow workspace', (
    tester,
  ) async {
    final previousHitTestPolicy = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(() {
      WidgetController.hitTestWarningShouldBeFatal = previousHitTestPolicy;
    });
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final provider = _Provider()
      ..failure = const EnrichmentException(
        'The assistant connection is temporarily unavailable. Your original notes and previous HTML remain safely stored. Please try again.',
      );
    final sourceNotes = 'A long typed source line.\n' * 100;
    await _mount(
      tester,
      store: _MemoryStore(
        _ink(
          html: '<h1>Long notes</h1><p>${'Equation and diagram. ' * 500}</p>',
        ),
      ),
      ink: _InkController(),
      providers: [
        provider,
        _Provider(name: 'Claude'),
      ],
      lecture: Lecture(
        id: _lecture.id,
        title: _lecture.title,
        notes: sourceNotes,
      ),
    );
    await _send(tester);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Existing text notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Existing text notes'));
    await tester.pumpAndSettle();
    expect(find.text(sourceNotes), findsOneWidget);
    await tester.ensureVisible(find.text(sourceNotes));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('HTML'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('HTML'));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText &&
            widget.data?.startsWith('Long notes') == true,
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  for (final leave in [false, true]) {
    testWidgets(
      'canceled conversion never starts sign-in after delayed status (${leave ? 'disposed' : 'cancel'})',
      (tester) async {
        final status = Completer<bool>();
        final provider = _Provider();
        final store = _MemoryStore(_ink());
        await _mount(
          tester,
          store: store,
          ink: _InkController(),
          providers: [provider],
        );
        provider.pendingConnectionStatus = status.future;
        await _send(tester);
        expect(provider.connects, 0);
        if (leave) {
          await tester.pumpWidget(const SizedBox.shrink());
        } else {
          await tester.tap(find.text('Cancel conversion'));
          await _advance(tester);
        }
        expect(provider.cancels, 1);
        status.complete(false);
        await _advance(tester);
        expect(provider.connects, 0);
        expect(provider.calls, 0);
        expect(store.content.hasHtml, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
