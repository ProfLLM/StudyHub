import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:studyhub/domain/lecture_content.dart';
import 'package:studyhub/domain/library.dart';
import 'package:studyhub/persistence/lecture_content_store.dart';
import 'package:studyhub/persistence/library_store.dart';

void main() {
  late Directory directory;
  late JsonLectureContentStore store;

  LectureContent ink([String id = 'lecture-1']) => LectureContent(lectureId: id)
      .withInk(
        drawing: Uint8List.fromList([1, 2]),
        preview: Uint8List.fromList([3]),
      );

  Future<File> sidecar() async => (await store.directory.list().toList())
      .whereType<File>()
      .singleWhere((file) => file.path.endsWith('.json'));

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('studyhub-content-test-');
    store = JsonLectureContentStore(Directory('${directory.path}/content'));
  });
  tearDown(() async => directory.delete(recursive: true));

  for (final orphan in [false, true]) {
    test(
      'deletion removes ${orphan ? 'orphan' : 'committed and'} temporary source',
      () async {
        await store.save(
          ink().withHtml(
            '<p>Private synthetic rendition</p>',
            sourceRevision: 1,
            provider: 'ChatGPT',
          ),
        );
        final file = await sidecar();
        final temporary = await file.copy('${file.path}.tmp');
        if (orphan) await file.delete();
        await store.delete('lecture-1');
        expect(await file.exists(), isFalse);
        expect(await temporary.exists(), isFalse);
        expect((await store.load('lecture-1')).hasInk, isFalse);
      },
    );
  }
  test(
    'deletion rejects unsafe temporary paths and retains outside data',
    () async {
      await store.save(ink());
      final file = await sidecar();
      final outside = File('${directory.path}/outside')
          .writeAsString('Synthetic outside data');
      await Link('${file.path}.tmp').create((await outside).path);
      await expectLater(
        store.delete('lecture-1'),
        throwsA(isA<FileSystemException>()),
      );
      expect(await (await outside).readAsString(), 'Synthetic outside data');
      expect(await file.exists(), isTrue);
    },
  );
  test('missing content is empty without creating any files', () async {
    final content = await store.load('lecture-1');
    expect(content.lectureId, 'lecture-1');
    expect(content.hasInk, isFalse);
    expect(content.hasHtml, isFalse);
    expect(content.htmlIsStale, isFalse);
    expect(content.inkRevision, 0);
    expect(await store.directory.exists(), isFalse);
  });

  test('native ink, preview and HTML survive a store restart', () async {
    final content = ink().withHtml(
      '<html><body><svg></svg><p>∫ x dx</p></body></html>',
      sourceRevision: 1,
      provider: 'ChatGPT',
    );
    await store.save(content);
    final reloaded = await JsonLectureContentStore(store.directory)
        .load(content.lectureId);
    expect(reloaded.toJson(), content.toJson());
    expect(reloaded.hasInk, isTrue);
    expect(reloaded.hasHtml, isTrue);
    expect(reloaded.htmlIsStale, isFalse);
    expect(await File('${(await sidecar()).path}.tmp').exists(), isFalse);
  });

  test('ink bytes are defensive on construction and access', () {
    final drawing = Uint8List.fromList([1, 2]);
    final preview = Uint8List.fromList([3]);
    final content = LectureContent(
      lectureId: 'l',
      inkRevision: 1,
      drawing: drawing,
      preview: preview,
    );
    drawing[0] = 100;
    preview[0] = 100;
    content.drawing![0] = 200;
    content.preview![0] = 200;
    expect(content.drawing, [1, 2]);
    expect(content.preview, [3]);
  });

  test('later ink preserves HTML and records its staleness', () async {
    final original = ink().withHtml(
      '<p>Original</p>',
      sourceRevision: 1,
      provider: 'Claude',
    );
    final edited = original.withInk(
      drawing: Uint8List.fromList([4]),
      preview: Uint8List.fromList([5]),
    );
    await store.save(original);
    await store.save(edited);
    final reloaded = await store.load('lecture-1');
    expect(reloaded.html, original.html);
    expect(reloaded.htmlSourceRevision, 1);
    expect(reloaded.inkRevision, 2);
    expect(reloaded.htmlIsStale, isTrue);
    final lateResult = reloaded.withHtml(
      '<p>Generated from an earlier snapshot</p>',
      sourceRevision: 1,
      provider: 'ChatGPT',
    );
    expect(lateResult.inkRevision, 2);
    expect(lateResult.drawing, edited.drawing);
    expect(lateResult.htmlIsStale, isTrue);
    expect(
      () =>
          reloaded.withHtml('<p>Future</p>', sourceRevision: 3, provider: 'X'),
      throwsArgumentError,
    );
  });

  test('failed HTML save retains the previous ink and enrichment', () async {
    final original = ink().withHtml(
      '<p>Keep this</p>',
      sourceRevision: 1,
      provider: 'Claude',
    );
    await store.save(original);
    await Directory('${(await sidecar()).path}.tmp').create();
    await expectLater(
      store.save(
        original.withHtml(
          '<p>Replacement</p>',
          sourceRevision: 1,
          provider: 'X',
        ),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect((await store.load('lecture-1')).toJson(), original.toJson());
    // Retrying after fixing the failed temporary write remains possible.
    await Directory('${(await sidecar()).path}.tmp').delete();
    await store.save(original);
  });

  test(
    'corruption, unknown schema, and identity mismatch block overwrites',
    () async {
      final original = ink();
      await store.save(original);
      final file = await sidecar();
      final invalid = <String>[
        '{broken',
        '[]',
        jsonEncode({...original.toJson(), 'schemaVersion': 2}),
        jsonEncode({...original.toJson(), 'schemaVersion': 1.0}),
        jsonEncode({...original.toJson(), 'lectureId': 'different'}),
        jsonEncode({...original.toJson(), 'inkRevision': '1'}),
        jsonEncode({...original.toJson(), 'drawing': '?not base64'}),
        jsonEncode({...original.toJson(), 'preview': null}),
        jsonEncode({...original.toJson(), 'htmlSourceRevision': 2}),
      ];
      for (final source in invalid) {
        await file.writeAsString(source);
        await expectLater(store.load('lecture-1'), throwsFormatException);
        await expectLater(store.save(original), throwsFormatException);
        expect(await file.readAsString(), source);
      }
    },
  );

  test(
    'path-like and Unicode identities stay inside the content directory',
    () async {
      for (final id in [
        '../../outside',
        '/absolute/file',
        'l/é\\.📝',
        'A',
        'a',
      ]) {
        final content = ink(id);
        await store.save(content);
        expect((await store.load(id)).toJson(), content.toJson());
      }
      expect(await store.directory.list().length, 5);
      expect(await directory.list().length, 1);
      expect(() => store.load(' '), throwsArgumentError);
      expect(() => store.load('x' * 121), throwsArgumentError);
    },
  );

  test(
    'concurrent stores serialize and reject stale or conflicting ink',
    () async {
      final original = ink();
      final newer = original.withInk(
        drawing: Uint8List.fromList([8]),
        preview: Uint8List.fromList([9]),
      );
      final secondStore = JsonLectureContentStore(store.directory);
      final saveFirst = store.save(original);
      final saveSecond = secondStore.save(newer);
      final saveStale = store.save(original);
      final staleExpectation = expectLater(saveStale, throwsStateError);
      await Future.wait([saveFirst, saveSecond, staleExpectation]);
      expect((await store.load('lecture-1')).toJson(), newer.toJson());
      await expectLater(
        store.save(
          LectureContent(
            lectureId: 'lecture-1',
            inkRevision: 2,
            drawing: Uint8List.fromList([20]),
            preview: Uint8List.fromList([21]),
          ),
        ),
        throwsStateError,
      );
      expect((await store.load('lecture-1')).toJson(), newer.toJson());
    },
  );

  test('delete only removes the requested Lecture file', () async {
    await store.save(ink());
    await store.save(ink('lecture-2'));
    final unrelated = File('${store.directory.path}/unrelated.txt');
    await unrelated.writeAsString('keep');
    await store.delete('lecture-1');
    await store.delete('missing');
    expect((await store.load('lecture-1')).hasInk, isFalse);
    expect((await store.load('lecture-2')).hasInk, isTrue);
    expect(await unrelated.readAsString(), 'keep');
  });

  test('sidecar and temporary symlinks cannot write another file', () async {
    final content = ink();
    await store.save(content);
    final file = await sidecar();
    final other = File('${directory.path}/protected.txt');
    await other.writeAsString('keep');
    await Link('${file.path}.tmp').create(other.path);
    await expectLater(store.save(content), throwsA(isA<FileSystemException>()));
    expect(await other.readAsString(), 'keep');
    await Link('${file.path}.tmp').delete();
    await file.delete();
    await Link(file.path).create(other.path);
    await expectLater(
      store.load('lecture-1'),
      throwsA(isA<FileSystemException>()),
    );
    await expectLater(store.save(content), throwsA(isA<FileSystemException>()));
    await expectLater(
      store.delete('lecture-1'),
      throwsA(isA<FileSystemException>()),
    );
    expect(await other.readAsString(), 'keep');
  });

  test('oversized files fail before JSON parsing', () async {
    await store.save(ink());
    final file = await sidecar();
    final handle = await file.open(mode: FileMode.write);
    await handle.truncate(JsonLectureContentStore.maxFileBytes + 1);
    await handle.close();
    await expectLater(store.load('lecture-1'), throwsFormatException);
    await expectLater(store.save(ink()), throwsFormatException);
    expect(await file.length(), JsonLectureContentStore.maxFileBytes + 1);
  });

  test('payload bounds and incomplete metadata reject invalid snapshots', () {
    expect(
      () => LectureContent(lectureId: 'l', inkRevision: -1),
      throwsArgumentError,
    );
    expect(
      () => LectureContent(lectureId: 'l', drawing: Uint8List(1)),
      throwsArgumentError,
    );
    expect(
      () => ink().withInk(
        drawing: Uint8List(LectureContent.maxDrawingBytes + 1),
        preview: Uint8List(1),
      ),
      throwsArgumentError,
    );
    expect(
      () => ink().withHtml(
        'x' * (LectureContent.maxHtmlBytes + 1),
        sourceRevision: 1,
        provider: 'Claude',
      ),
      throwsArgumentError,
    );
    expect(
      () => LectureContent(lectureId: 'l', html: '<p>Missing source</p>'),
      throwsArgumentError,
    );
  });

  test(
    'content storage leaves the original library notes and schema intact',
    () async {
      final libraryFile = File('${directory.path}/library.json');
      final libraryStore = JsonLibraryStore(libraryFile);
      await libraryStore.save(
        StudyLibrary(
          classes: [
            StudyClass(
              id: 'class-1',
              title: 'Physics',
              lectures: [
                const Lecture(
                  id: 'lecture-1',
                  title: 'Motion',
                  notes: 'Original typed notes.',
                ),
              ],
            ),
          ],
        ),
      );
      final originalBytes = await libraryFile.readAsBytes();
      await store.save(ink());
      await store.delete('lecture-1');
      expect(await libraryFile.readAsBytes(), originalBytes);
      final library = await libraryStore.load();
      expect(library.toJson()['schemaVersion'], 1);
      expect(
        library.classes.single.lectures.single.notes,
        'Original typed notes.',
      );
    },
  );
}
