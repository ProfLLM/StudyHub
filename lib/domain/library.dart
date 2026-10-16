import 'dart:math';

String newId() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

String _text(Object? value, {bool allowEmpty = false}) {
  if (value is! String || (!allowEmpty && value.trim().isEmpty)) {
    throw const FormatException('Invalid text field.');
  }
  return value;
}

class Lecture {
  const Lecture({required this.id, required this.title, this.notes = ''});

  final String id;
  final String title;
  final String notes;

  Lecture renamed(String title) => Lecture(id: id, title: title, notes: notes);

  Map<String, Object> toJson() => {'id': id, 'title': title, 'notes': notes};

  factory Lecture.fromJson(Map<String, dynamic> json) => Lecture(
    id: _text(json['id']),
    title: _text(json['title']),
    notes: _text(json['notes'], allowEmpty: true),
  );
}

class StudyClass {
  StudyClass({
    required this.id,
    required this.title,
    List<Lecture> lectures = const [],
  }) : lectures = List.unmodifiable(lectures);

  final String id;
  final String title;
  final List<Lecture> lectures;

  StudyClass copyWith({String? title, List<Lecture>? lectures}) => StudyClass(
    id: id,
    title: title ?? this.title,
    lectures: lectures ?? this.lectures,
  );

  Map<String, Object> toJson() => {
    'id': id,
    'title': title,
    'lectures': lectures.map((lecture) => lecture.toJson()).toList(),
  };

  factory StudyClass.fromJson(Map<String, dynamic> json) => StudyClass(
    id: _text(json['id']),
    title: _text(json['title']),
    lectures: (json['lectures'] as List)
        .map((item) => Lecture.fromJson(item as Map<String, dynamic>))
        .toList(),
  );
}

class StudyLibrary {
  StudyLibrary({List<StudyClass> classes = const []})
    : classes = List.unmodifiable(classes);

  final List<StudyClass> classes;

  Map<String, Object> toJson() => {
    'schemaVersion': 1,
    'classes': classes.map((studyClass) => studyClass.toJson()).toList(),
  };

  factory StudyLibrary.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != 1) {
      throw const FormatException('Unsupported library version.');
    }
    final classes = (json['classes'] as List)
        .map((item) => StudyClass.fromJson(item as Map<String, dynamic>))
        .toList();
    final ids = <String>{};
    for (final studyClass in classes) {
      if (!ids.add(studyClass.id)) {
        throw const FormatException('Duplicate identity.');
      }
      for (final lecture in studyClass.lectures) {
        if (!ids.add(lecture.id)) {
          throw const FormatException('Duplicate identity.');
        }
      }
    }
    return StudyLibrary(classes: classes);
  }
}
