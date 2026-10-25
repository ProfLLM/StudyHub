import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/common.dart';

Future<void> main() async {
  final filePath = Platform.environment['STUDYHUB_LIVE_FIXTURES_FILE'] ?? '';
  if (!RegExp(r'^/private/tmp/studyhub-live-fixtures(?:-[a-f0-9]{32})?\.json$')
      .hasMatch(filePath)) {
    throw const FormatException(
      'Set STUDYHUB_LIVE_FIXTURES_FILE to the generated public fixture JSON under /private/tmp.',
    );
  }
  final fixture = File(filePath);
  if (await FileSystemEntity.type(filePath, followLinks: false) !=
          FileSystemEntityType.file ||
      await fixture.length() > 2 * 1024 * 1024) {
    throw const FormatException(
      'Expected bounded regular public fixture file.',
    );
  }
  final corpus = await fixture.readAsString();
  final driver = await FlutterDriver.connect(
    printCommunication: false,
    logCommunicationToFile: false,
  );
  Response? response;
  Map<String, dynamic> report = {'status': 'not_verified'};
  try {
    await driver.serviceClient.callServiceExtension(
      'ext.studyhub.loadLiveCorpus',
      isolateId: driver.appIsolate.id,
      args: {'corpus': corpus},
    );
    response = Response.fromJson(
      await driver.requestData(null, timeout: const Duration(minutes: 115)),
    );
    report = Map<String, dynamic>.from(response.data ?? report);
  } catch (error) {
    report['error_type'] = error.runtimeType.toString();
  } finally {
    await driver.close();
  }
  final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
  final output = Directory('build/provider-quality/$stamp');
  await output.create(recursive: true);
  for (final run in (report['runs'] as List? ?? [])) {
    final entry = run as Map<String, dynamic>;
    final id = entry['case_id'] as String;
    if (!RegExp(r'^\d{2}_[a-z_]+$').hasMatch(id)) {
      throw const FormatException('Unexpected evidence filename.');
    }
    for (final kind in ['raw', 'sanitized']) {
      final html = entry.remove('${kind}_html');
      if (html is String) {
        final name = '$id.$kind.html';
        await File('${output.path}/$name').writeAsString(html, flush: true);
        entry['${kind}_html_file'] = name;
      }
    }
  }
  await File('${output.path}/report.json').writeAsString(
    const JsonEncoder.withIndent('  ').convert(report),
    flush: true,
  );
  stdout.writeln('Synthetic provider evidence: ${output.absolute.path}');
  if (response?.allTestsPassed != true) exitCode = 1;
}
