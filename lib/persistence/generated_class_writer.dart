import '../domain/lecture_content.dart';
import '../domain/library.dart';
import '../enrichment/class_draft.dart';
import 'lecture_content_store.dart';
import 'library_store.dart';

class ClassSaveException implements Exception {
  const ClassSaveException({required this.cleanupComplete});
  final bool cleanupComplete;
  @override
  String toString() => cleanupComplete
      ? 'Could not save the class. Your library is unchanged. Retry saving this preview.'
      : 'Could not save the class. Your library is unchanged, but some unfinished lecture files could not be removed. Retry saving this preview.';
}

/// Write new, unreachable lecture files before committing the library. Only
/// newly allocated IDs are rolled back; existing classes and notes are safe.
class GeneratedClassWriter {
  GeneratedClassWriter(this.libraryStore, this.contentStore);
  final LibraryStore libraryStore;
  final LectureContentStore contentStore;

  Future<StudyLibrary> save(ClassDraft draft, StudyLibrary current) async {
    final used = <String>{
      for (final c in current.classes) ...[
        c.id,
        for (final l in c.lectures) l.id,
      ],
    };
    String id() {
      var result = newId();
      while (!used.add(result)) {
        result = newId();
      }
      return result;
    }

    final studyClass = StudyClass(
      id: id(),
      title: draft.title,
      lectures: [
        for (final lesson in draft.lessons)
          Lecture(id: id(), title: lesson.title, notes: lesson.notes),
      ],
    );
    final staged = <String>[];
    try {
      for (var i = 0; i < studyClass.lectures.length; i++) {
        final lecture = studyClass.lectures[i];
        final existing = await contentStore.load(lecture.id);
        if (existing.hasInk ||
            existing.hasHtml ||
            existing.assignments.isNotEmpty) {
          throw StateError('Generated lecture ID is already in use.');
        }
        staged.add(lecture.id);
        await contentStore.save(
          LectureContent(lectureId: lecture.id).withHtml(
            draft.lessons[i].content.document,
            sourceRevision: 0,
            provider: 'ChatGPT',
          ),
        );
      }
      final next = StudyLibrary(classes: [...current.classes, studyClass]);
      await libraryStore.save(next);
      return next;
    } catch (_) {
      var complete = true;
      for (final lectureId in staged) {
        try {
          await contentStore.delete(lectureId);
        } catch (_) {
          complete = false;
        }
      }
      throw ClassSaveException(cleanupComplete: complete);
    }
  }
}
