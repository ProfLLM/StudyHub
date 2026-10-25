import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as parser;

import 'safe_lecture_html.dart';

/// An unsaved proposal, sanitized before it can be displayed or committed.
class ClassDraft {
  ClassDraft._(this.title, List<LessonDraft> lessons)
    : lessons = List.unmodifiable(lessons);
  final String title;
  final List<LessonDraft> lessons;
  static const maxResponseBytes = 2 * 1024 * 1024;
  static const maxLessonBytes = 256 * 1024;
  static const maxLessons = 12;

  factory ClassDraft.parse(String source) {
    if (utf8.encode(source).length > maxResponseBytes) {
      throw const FormatException(
        'The generated class is too large. Try a narrower topic.',
      );
    }
    var json = source.trim();
    if (json.startsWith('```json') && json.endsWith('```')) {
      json = json.substring(7, json.length - 3).trim();
    }
    String title(Object? value) {
      if (value is! String ||
          value.trim().isEmpty ||
          value.trim().length > 120) {
        throw const FormatException(
          'The generated class has an invalid title.',
        );
      }
      return value.trim();
    }

    final value = jsonDecode(json);
    if (value is! Map<String, dynamic> || value['lectures'] is! List) {
      throw const FormatException('ChatGPT did not return a complete class.');
    }
    final lectures = value['lectures'] as List;
    if (lectures.isEmpty || lectures.length > maxLessons) {
      throw const FormatException(
        'A generated class must contain 1–12 complete lectures.',
      );
    }
    final lessons = <LessonDraft>[];
    for (final lecture in lectures) {
      if (lecture is! Map<String, dynamic> ||
          lecture['html'] is! String ||
          utf8.encode(lecture['html'] as String).length > maxLessonBytes) {
        throw const FormatException(
          'A generated lecture is missing or too large.',
        );
      }
      final html = SafeLectureHtml.parse(lecture['html'] as String);
      if (html.plainText.trim().isEmpty) {
        throw const FormatException(
          'A generated lecture contains no readable teaching material.',
        );
      }
      final body = parser.parse(html.document).body!;
      for (final block in body.querySelectorAll(
        'h1,h2,h3,h4,p,li,pre,blockquote,tr,figcaption,summary',
      )) {
        block.nodes.add(Text('\n\n'));
      }
      lessons.add(
        LessonDraft._(title(lecture['title']), html, body.text.trim()),
      );
    }
    return ClassDraft._(title(value['title']), lessons);
  }
}

class LessonDraft {
  const LessonDraft._(this.title, this.content, this.notes);
  final String title;
  final SafeLectureHtml content;
  final String notes;
}
