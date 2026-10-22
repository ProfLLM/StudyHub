import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app/study_hub_app.dart';
import 'ai/chatgpt_subscription_provider.dart';
import 'persistence/lecture_content_store.dart';
import 'persistence/library_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // A separate development profile keeps automated runs away from real notes.
  const profile = String.fromEnvironment(
    'STUDYHUB_PROFILE',
    defaultValue: 'default',
  );
  if (!RegExp(r'^[a-zA-Z0-9_-]{1,64}$').hasMatch(profile)) {
    throw ArgumentError('Invalid StudyHub profile.');
  }
  final suffix = profile == 'default' ? '' : '-$profile';
  final directory = getApplicationSupportDirectory();
  runApp(
    StudyHubApp(
      openStore: () async {
        return JsonLibraryStore(
          File('${(await directory).path}/library$suffix.json'),
        );
      },
      openContentStore: () async => JsonLectureContentStore(
        Directory('${(await directory).path}/lecture-content$suffix'),
      ),
      providers: [ChatGptSubscriptionProvider()],
    ),
  );
}
