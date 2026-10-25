import 'dart:convert';
import 'dart:typed_data';

/// Editable source ink and a separate, optional enrichment of one ink revision.
class LectureContent {
  LectureContent({
    required this.lectureId,
    this.inkRevision = 0,
    Uint8List? drawing,
    Uint8List? preview,
    this.html,
    this.htmlSourceRevision,
    this.htmlProvider,
  }) : _drawing = drawing == null ? null : Uint8List.fromList(drawing),
       _preview = preview == null ? null : Uint8List.fromList(preview) {
    validateLectureId(lectureId);
    if (inkRevision < 0 || (drawing == null) != (preview == null)) {
      throw ArgumentError('Ink requires a revision, drawing, and preview.');
    }
    if (drawing == null && inkRevision != 0 ||
        drawing != null && inkRevision == 0) {
      throw ArgumentError('Ink revision does not match the source ink.');
    }
    if (drawing != null &&
        (drawing.isEmpty || drawing.length > maxDrawingBytes)) {
      throw ArgumentError('Drawing is empty or exceeds the size limit.');
    }
    if (preview != null &&
        (preview.isEmpty || preview.length > maxPreviewBytes)) {
      throw ArgumentError('Preview is empty or exceeds the size limit.');
    }
    if (html == null) {
      if (htmlSourceRevision != null || htmlProvider != null) {
        throw ArgumentError('HTML metadata requires HTML content.');
      }
    } else if (html!.trim().isEmpty ||
        utf8.encode(html!).length > maxHtmlBytes ||
        htmlSourceRevision == null ||
        htmlSourceRevision! < 0 ||
        htmlSourceRevision! > inkRevision ||
        htmlProvider == null ||
        htmlProvider!.trim().isEmpty ||
        utf8.encode(htmlProvider!).length > 128) {
      throw ArgumentError('Invalid HTML content or source metadata.');
    }
  }

  static const maxDrawingBytes = 16 * 1024 * 1024;
  static const maxPreviewBytes = 16 * 1024 * 1024;
  static const maxHtmlBytes = 4 * 1024 * 1024;

  final String lectureId;
  final int inkRevision;
  final Uint8List? _drawing;
  final Uint8List? _preview;
  final String? html;
  final int? htmlSourceRevision;
  final String? htmlProvider;

  // Callers cannot modify an existing content snapshot through its byte buffers.
  Uint8List? get drawing =>
      _drawing == null ? null : Uint8List.fromList(_drawing);
  Uint8List? get preview =>
      _preview == null ? null : Uint8List.fromList(_preview);
  bool get hasInk => _drawing != null;
  bool get hasHtml => html != null;
  bool get htmlIsStale => hasHtml && htmlSourceRevision != inkRevision;

  static void validateLectureId(String lectureId) {
    if (lectureId.trim().isEmpty || utf8.encode(lectureId).length > 120) {
      throw ArgumentError('Invalid lecture identity.');
    }
  }

  LectureContent withInk({
    required Uint8List drawing,
    required Uint8List preview,
  }) => LectureContent(
    lectureId: lectureId,
    inkRevision: inkRevision + 1,
    drawing: drawing,
    preview: preview,
    html: html,
    htmlSourceRevision: htmlSourceRevision,
    htmlProvider: htmlProvider,
  );

  LectureContent withHtml(
    String html, {
    required int sourceRevision,
    required String provider,
  }) => LectureContent(
    lectureId: lectureId,
    inkRevision: inkRevision,
    drawing: _drawing,
    preview: _preview,
    html: html,
    htmlSourceRevision: sourceRevision,
    htmlProvider: provider,
  );

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'lectureId': lectureId,
    'inkRevision': inkRevision,
    'drawing': _drawing == null ? null : base64Encode(_drawing),
    'preview': _preview == null ? null : base64Encode(_preview),
    'html': html,
    'htmlSourceRevision': htmlSourceRevision,
    'htmlProvider': htmlProvider,
  };

  factory LectureContent.fromJson(Map<String, dynamic> json) {
    try {
      if (json['schemaVersion'] is! int || json['schemaVersion'] != 1) {
        throw const FormatException('Unsupported lecture content version.');
      }
      Uint8List? bytes(String key, int limit) {
        final encoded = json[key];
        if (encoded == null) return null;
        if (encoded is! String || encoded.length > ((limit + 2) ~/ 3) * 4) {
          throw const FormatException('Invalid ink payload.');
        }
        return base64Decode(encoded);
      }

      return LectureContent(
        lectureId: json['lectureId'] as String,
        inkRevision: json['inkRevision'] as int,
        drawing: bytes('drawing', maxDrawingBytes),
        preview: bytes('preview', maxPreviewBytes),
        html: json['html'] as String?,
        htmlSourceRevision: json['htmlSourceRevision'] as int?,
        htmlProvider: json['htmlProvider'] as String?,
      );
    } on ArgumentError {
      throw const FormatException('Invalid lecture content.');
    } on TypeError {
      throw const FormatException('Invalid lecture content structure.');
    }
  }
}
