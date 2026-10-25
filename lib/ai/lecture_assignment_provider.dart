import 'dart:typed_data';

/// Optional capability alongside ordinary static lecture enrichment.
abstract interface class LectureAssignmentProvider {
  Future<String> createAssignment({
    required List<Uint8List> images,
    required String lectureTitle,
    required String sourceNotes,
    required String request,
  });
  Future<String> reviewAssignment({
    required List<Uint8List> images,
    required String lectureTitle,
    required String sourceNotes,
    required String assignmentHtml,
    required String answersJson,
  });
}
