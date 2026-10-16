import 'dart:convert';
import 'dart:io';

import '../domain/library.dart';

abstract class LibraryStore {
  Future<StudyLibrary> load();
  Future<void> save(StudyLibrary library);
}

class JsonLibraryStore implements LibraryStore {
  JsonLibraryStore(this.file);

  final File file;

  @override
  Future<StudyLibrary> load() async {
    if (!await file.exists()) return StudyLibrary();
    try {
      return StudyLibrary.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
    } on FormatException {
      rethrow;
    } on TypeError {
      throw const FormatException('Invalid library structure.');
    }
  }

  @override
  Future<void> save(StudyLibrary library) async {
    await file.parent.create(recursive: true);
    // Replace only after the full file is flushed; a failed write keeps the old file.
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(library.toJson())}\n',
      flush: true,
    );
    await temporary.rename(file.path);
  }
}
