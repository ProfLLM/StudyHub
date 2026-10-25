import 'dart:typed_data';

abstract class LectureEnrichmentProvider {
  String get name;
  Future<bool> get isConnected;
  Future<void> connect();
  Future<String> generate({
    required List<Uint8List> images,
    required String lectureTitle,
    required String sourceNotes,
  });
  void cancel();
  Future<void> disconnect();
}

class EnrichmentException implements Exception {
  const EnrichmentException(this.message);
  final String message;
  @override
  String toString() => message;
}
