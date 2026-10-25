import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyhub/app/assignment_view.dart';
import 'package:studyhub/domain/lecture_assignment.dart';

void main() {
  testWidgets('assignment retains its full width after loading completes', (
    tester,
  ) async {
    final controller = AssignmentController();
    final messenger = tester.binding.defaultBinaryMessenger;
    final channels = <MethodChannel>[];
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map)['id'];
        final channel = MethodChannel('studyhub/assignment/$id');
        channels.add(channel);
        messenger.setMockMethodCallHandler(channel, (_) async => null);
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
      for (final channel in channels) {
        messenger.setMockMethodCallHandler(channel, null);
      }
      controller.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 500,
            child: AssignmentView(
              assignment: LectureAssignment(
                id: '0123456789abcdef0123456789abcdef',
                request: 'Practice',
                html: '<h1>Practice</h1><textarea data-answer-key="reason"></textarea>',
                sourceRevision: 0,
                provider: 'Synthetic',
              ),
              controller: controller,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    controller.ready.value = true;
    await tester.pump();
    final surface = find.byType(UiKitView);
    expect(tester.getSize(surface), const Size(600, 500));
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
