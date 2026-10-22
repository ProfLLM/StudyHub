import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../domain/lecture_content.dart';

abstract class LectureContentStore {
  Future<LectureContent> load(String lectureId);
  Future<void> save(LectureContent content);
  Future<void> delete(String lectureId);
}

/// A sidecar per Lecture; the existing library file and plain notes stay intact.
/// Operations on the same file serialize within this app process.
class JsonLectureContentStore implements LectureContentStore {
  JsonLectureContentStore(this.directory);

  final Directory directory;
  static const maxFileBytes = 50 * 1024 * 1024;
  static final _pending = <String, Future<void>>{};

  File _file(String lectureId) {
    LectureContent.validateLectureId(lectureId);
    // Lowercase hex stays distinct even on case-insensitive Apple filesystems.
    final name = utf8
        .encode(lectureId)
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return File('${directory.path}/$name.json');
  }

  Future<T> _serialized<T>(File file, Future<T> Function() action) {
    final key = Uri.file(file.absolute.path).normalizePath().toFilePath();
    final previous = _pending[key] ?? Future<void>.value();
    final result = previous.then((_) => action());
    // A failed operation must not poison subsequent retries.
    final settled = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _pending[key] = settled;
    settled.then((_) {
      if (identical(_pending[key], settled)) _pending.remove(key);
    });
    return result;
  }

  Future<void> _checkFileType(File file) async {
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw FileSystemException(
        'Content path is not a regular file.',
        file.path,
      );
    }
  }

  Future<LectureContent> _load(File file, String lectureId) async {
    await _checkFileType(file);
    if (!await file.exists()) return LectureContent(lectureId: lectureId);
    if (await file.length() > maxFileBytes) {
      throw const FormatException('Lecture content exceeds the size limit.');
    }
    try {
      final result = LectureContent.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
      if (result.lectureId != lectureId) {
        throw const FormatException('Lecture content identity does not match.');
      }
      return result;
    } on TypeError {
      throw const FormatException('Invalid lecture content structure.');
    }
  }

  @override
  Future<LectureContent> load(String lectureId) {
    final file = _file(lectureId);
    return _serialized(file, () => _load(file, lectureId));
  }

  @override
  Future<void> save(LectureContent content) {
    final file = _file(content.lectureId);
    return _serialized(file, () async {
      // Loading first protects unknown or damaged files from being overwritten.
      final current = await _load(file, content.lectureId);
      if (content.inkRevision < current.inkRevision ||
          content.inkRevision == current.inkRevision &&
              (!_sameBytes(content.drawing, current.drawing) ||
                  !_sameBytes(content.preview, current.preview))) {
        throw StateError(
          'A newer or conflicting ink revision is already saved.',
        );
      }
      final encoded = utf8.encode(jsonEncode(content.toJson()));
      if (encoded.length > maxFileBytes) {
        throw ArgumentError('Lecture content exceeds the stored size limit.');
      }
      await directory.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await _checkFileType(temporary);
      await temporary.writeAsBytes(encoded, flush: true);
      await temporary.rename(file.path);
    });
  }

  @override
  Future<void> delete(String lectureId) {
    final file = _file(lectureId);
    return _serialized(file, () async {
      await _checkFileType(file);
      if (await file.exists()) await file.delete();
    });
  }

  static bool _sameBytes(Uint8List? left, Uint8List? right) {
    if (left == null || right == null) return left == right;
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }
}
