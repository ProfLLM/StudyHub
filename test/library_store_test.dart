import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:studyhub/domain/library.dart';
import 'package:studyhub/persistence/library_store.dart';

void main() {
  late Directory directory;
  late JsonLibraryStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('studyhub-test-');
    store = JsonLibraryStore(File('${directory.path}/nested/library.json'));
  });

  tearDown(() async => directory.delete(recursive: true));

  test(
    'new library is empty; saves and reloads stable identities and notes',
    () async {
      expect((await store.load()).classes, isEmpty);
      final library = StudyLibrary(
        classes: [
          StudyClass(
            id: 'class-1',
            title: 'Physics',
            lectures: [
              const Lecture(
                id: 'lecture-1',
                title: 'Motion',
                notes: 'Keep this source note.',
              ),
            ],
          ),
        ],
      );
      await store.save(library);
      final reloaded = await JsonLibraryStore(store.file).load();
      expect(reloaded.toJson(), library.toJson());
      expect(await File('${store.file.path}.tmp').exists(), isFalse);

      await store.save(
        StudyLibrary(
          classes: [
            reloaded.classes.single.copyWith(
              title: 'Mechanics',
              lectures: [
                reloaded.classes.single.lectures.single.renamed('Forces'),
              ],
            ),
          ],
        ),
      );
      final renamed = (await store.load()).classes.single;
      expect(renamed.id, 'class-1');
      expect(renamed.title, 'Mechanics');
      expect(renamed.lectures.single.id, 'lecture-1');
      expect(renamed.lectures.single.notes, 'Keep this source note.');
      await store.save(StudyLibrary());
      expect((await store.load()).classes, isEmpty);
    },
  );

  test('invalid JSON and unsupported schemas stay untouched', () async {
    await store.file.parent.create(recursive: true);
    for (final source in [
      '{broken',
      '{"schemaVersion":2,"classes":[]}',
      '{"schemaVersion":1,"classes":"invalid"}',
      '{"schemaVersion":1,"classes":[{"id":"c","title":" ","lectures":[]}]}',
      '{"schemaVersion":1,"classes":[{"id":"c","title":"A","lectures":[{"id":"c","title":"B","notes":""}]}]}',
    ]) {
      await store.file.writeAsString(source);
      await expectLater(store.load(), throwsFormatException);
      expect(await store.file.readAsString(), source);
    }
  });

  test('a failed temporary write preserves the last saved library', () async {
    final original = StudyLibrary(
      classes: [StudyClass(id: 'c', title: 'Physics')],
    );
    await store.save(original);
    await Directory('${store.file.path}.tmp').create();
    await expectLater(
      store.save(StudyLibrary()),
      throwsA(isA<FileSystemException>()),
    );
    expect((await store.load()).toJson(), original.toJson());
  });
}
