import 'dart:convert';

/// Generated exercises are immutable; answers and feedback have their own
/// revisions. JSON is stored as text so callers cannot mutate a saved snapshot.
class LectureAssignment {
  LectureAssignment({
    required this.id,
    required this.request,
    required this.html,
    required this.sourceRevision,
    required this.provider,
    this.answersJson = '{}',
    this.answerRevision = 0,
    this.feedbackHtml,
    this.feedbackAnswerRevision,
  }) {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id) ||
        request.trim().isEmpty ||
        request.length > 4000 ||
        html.trim().isEmpty ||
        utf8.encode(html).length > maxHtmlBytes ||
        sourceRevision < 0 ||
        provider.isEmpty ||
        provider.length > 128 ||
        answerRevision < 0) {
      throw const FormatException('Invalid assignment.');
    }
    validateAnswers(answersJson);
    if ((feedbackHtml == null) != (feedbackAnswerRevision == null) ||
        feedbackHtml != null &&
            (feedbackHtml!.trim().isEmpty ||
                utf8.encode(feedbackHtml!).length > maxHtmlBytes ||
                feedbackAnswerRevision! < 0 ||
                feedbackAnswerRevision! > answerRevision)) {
      throw const FormatException('Invalid assignment feedback.');
    }
  }

  static const maxHtmlBytes = 1024 * 1024;
  static const maxAnswerBytes = 4 * 1024 * 1024;
  final String id, request, html, provider, answersJson;
  final int sourceRevision, answerRevision;
  final String? feedbackHtml;
  final int? feedbackAnswerRevision;
  bool get feedbackIsStale =>
      feedbackHtml != null && feedbackAnswerRevision != answerRevision;

  static void validateAnswers(String json) {
    if (utf8.encode(json).length > maxAnswerBytes) {
      throw const FormatException('Assignment answers exceed the size limit.');
    }
    final value = jsonDecode(json);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid answers.');
    }
    var nodes = 0;
    void visit(Object? value, int depth) {
      if (++nodes > 50000 || depth > 16) {
        throw const FormatException('Answers are too complex.');
      }
      if (value is Map) {
        for (final entry in value.entries) {
          if (entry.key is! String || (entry.key as String).length > 256) {
            throw const FormatException('Invalid answer key.');
          }
          visit(entry.value, depth + 1);
        }
      } else if (value is List) {
        for (final child in value) {
          visit(child, depth + 1);
        }
      } else if (value != null &&
          value is! String &&
          value is! bool &&
          value is! num) {
        throw const FormatException('Invalid answer value.');
      }
    }

    visit(value, 0);
  }

  LectureAssignment withAnswers(String json) {
    validateAnswers(json);
    final canonical = jsonEncode(jsonDecode(json));
    if (canonical == answersJson) return this;
    return LectureAssignment(
      id: id,
      request: request,
      html: html,
      sourceRevision: sourceRevision,
      provider: provider,
      answersJson: canonical,
      answerRevision: answerRevision + 1,
      feedbackHtml: feedbackHtml,
      feedbackAnswerRevision: feedbackAnswerRevision,
    );
  }

  LectureAssignment withFeedback(String html, int revision) =>
      LectureAssignment(
        id: id,
        request: request,
        html: this.html,
        sourceRevision: sourceRevision,
        provider: provider,
        answersJson: answersJson,
        answerRevision: answerRevision,
        feedbackHtml: html,
        feedbackAnswerRevision: revision,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'request': request,
    'html': html,
    'sourceRevision': sourceRevision,
    'provider': provider,
    'answersJson': answersJson,
    'answerRevision': answerRevision,
    'feedbackHtml': feedbackHtml,
    'feedbackAnswerRevision': feedbackAnswerRevision,
  };

  factory LectureAssignment.fromJson(Map<String, dynamic> json) {
    try {
      return LectureAssignment(
        id: json['id'] as String,
        request: json['request'] as String,
        html: json['html'] as String,
        sourceRevision: json['sourceRevision'] as int,
        provider: json['provider'] as String,
        answersJson: json['answersJson'] as String,
        answerRevision: json['answerRevision'] as int,
        feedbackHtml: json['feedbackHtml'] as String?,
        feedbackAnswerRevision: json['feedbackAnswerRevision'] as int?,
      );
    } on TypeError {
      throw const FormatException('Invalid assignment structure.');
    }
  }
}
