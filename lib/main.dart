import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app/study_hub_app.dart';
import 'persistence/library_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    StudyHubApp(
      openStore: () async {
        final directory = await getApplicationSupportDirectory();
        return JsonLibraryStore(File('${directory.path}/library.json'));
      },
    ),
  );
}
