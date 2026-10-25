import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final output = Directory('build/review-screenshots');
  await output.create(recursive: true);
  await integrationDriver(
    responseDataCallback: null,
    onScreenshot: (name, bytes, [arguments]) async {
      if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(name)) return false;
      await File('${output.path}/$name.png').writeAsBytes(bytes, flush: true);
      return bytes.isNotEmpty;
    },
  );
}
