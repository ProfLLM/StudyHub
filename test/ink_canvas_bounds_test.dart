import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyhub/ink/ink_canvas.dart';

// The actual bounds/rotation/export tests live in iOS RunnerTests and exercise
// the authoritative Swift geometry with PKDrawing. These tests validate the
// Flutter/platform-view boundary without pretending widget tests emulate ink.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final created = <Map<Object?, Object?>>[];
  final commands = <String>[];
  final initial = Uint8List.fromList([1, 2, 3]);
  final latest = Uint8List.fromList([4, 5, 6]);
  final preview = Uint8List.fromList([7, 8]);
  late InkCanvasController controller;
  PlatformException? initializeError;
  PlatformException? exportError;
  Object? flushResult;

  setUp(() {
    controller = InkCanvasController();
    initializeError = null;
    exportError = null;
    flushResult = {'drawing': latest, 'preview': preview, 'changeId': 1};
    created.clear();
    commands.clear();
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method == 'create') {
        final arguments = Map<Object?, Object?>.from(call.arguments as Map);
        created.add(arguments);
        final channel = MethodChannel('studyhub/ink/${arguments['id']}');
        messenger.setMockMethodCallHandler(channel, (call) async {
          commands.add(call.method);
          switch (call.method) {
            case 'initialize':
              if (initializeError != null) throw initializeError!;
              return null;
            case 'flush':
              return flushResult;
            case 'captureSnapshot':
              return {
                'drawing': latest,
                'preview': preview,
                'changeId': 1,
                'images': [preview],
              };
            case 'exportImages':
              if (exportError != null) throw exportError!;
              return [preview];
            default:
              return null;
          }
        });
      }
      return null;
    });
  });

  tearDown(() {
    for (final arguments in created) {
      messenger.setMockMethodCallHandler(
        MethodChannel('studyhub/ink/${arguments['id']}'),
        null,
      );
    }
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    controller.dispose();
  });

  Widget app({
    String lecture = 'lecture-a',
    Uint8List? drawing,
    ValueChanged<InkDrawingUpdate>? onChanged,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: InkCanvas(
          lectureId: lecture,
          initialDrawing: drawing,
          controller: controller,
          onChanged: onChanged ?? (_) {},
        ),
      ),
    );
  }

  void inkTest(String description, WidgetTesterCallback callback) {
    testWidgets(
      description,
      callback,
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  }

  test(
    'source protocol rejects missing, negative, and noninteger mutation ids',
    () {
      for (final id in [null, -1, 0.5, '1']) {
        expect(
          () => InkDrawingUpdate.fromPlatform({
            'drawing': latest,
            'preview': preview,
            'changeId': id,
          }),
          throwsA(isA<FormatException>()),
        );
      }
      expect(
        InkDrawingUpdate.fromPlatform({
          'drawing': latest,
          'preview': preview,
          'changeId': 0,
        }).changeId,
        0,
      );
      expect(
        () => InkSnapshot.fromPlatform({
          'drawing': latest,
          'preview': preview,
          'changeId': 1,
          'images': ['invalid'],
        }),
        throwsA(isA<FormatException>()),
      );
    },
  );

  inkTest('capture pairs one source revision with its ordered PNG pages', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final snapshot = await controller.captureSnapshot();
    expect(snapshot.drawing, latest);
    expect(snapshot.preview, preview);
    expect(snapshot.changeId, 1);
    expect(snapshot.images, [preview]);
    expect(() => snapshot.images.add(preview), throwsUnsupportedError);
    await controller.setActive(false);
    await controller.setActive(true);
    await controller.seedSyntheticDrawingForTesting();
    expect(
      commands,
      containsAllInOrder([
        'captureSnapshot',
        'setActive',
        'setActive',
        'seedSyntheticDrawing',
      ]),
    );
  });

  inkTest(
    'source loads once and flush delivers latest native source and preview',
    (tester) async {
      InkDrawingUpdate? changed;
      await tester.pumpWidget(
        app(drawing: initial, onChanged: (update) => changed = update),
      );
      await tester.pumpAndSettle();
      expect(controller.ready.value, isTrue);
      expect(created, hasLength(1));
      final params = (created.single['params'] as Uint8List);
      final decoded = const StandardMessageCodec().decodeMessage(
        ByteData.sublistView(params),
      ) as Map;
      expect(decoded['drawing'], initial);

      // A persistence rebuild carries old source, which must never replace ink.
      await tester.pumpWidget(
        app(
          drawing: Uint8List.fromList([99]),
          onChanged: (update) => changed = update,
        ),
      );
      await tester.pumpAndSettle();
      expect(created, hasLength(1));
      final update = await controller.flush();
      expect(update?.drawing, latest);
      expect(update?.preview, preview);
      expect(update?.changeId, 1);
      expect(changed?.drawing, latest);
      expect(await controller.exportImages(), [preview]);
    },
  );

  inkTest('commands surface native failures and malformed snapshots', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    exportError = PlatformException(code: 'large', message: 'Too many pages.');
    await expectLater(
      controller.exportImages(),
      throwsA(isA<PlatformException>()),
    );
    expect(controller.error.value, 'Too many pages.');
    await tester.pump();
    expect(find.text('Too many pages.'), findsOneWidget);
    flushResult = {'drawing': 'invalid', 'preview': preview};
    await expectLater(controller.flush(), throwsA(isA<FormatException>()));
    expect(controller.error.value, contains('invalid drawing'));
  });

  inkTest(
    'unreadable initial source blocks editing commands and reports error',
    (tester) async {
      initializeError = PlatformException(
        code: 'invalidInk',
        message: 'Saved source preserved.',
      );
      await tester.pumpWidget(app(drawing: initial));
      await tester.pumpAndSettle();
      expect(controller.ready.value, isFalse);
      expect(find.text('Saved source preserved.'), findsOneWidget);
      await expectLater(controller.clear(), throwsA(isA<StateError>()));
      expect(commands, ['initialize']);
    },
  );

  inkTest(
    'switching lectures creates a new native source without loading stale ink',
    (tester) async {
      await tester.pumpWidget(app(drawing: initial));
      await tester.pumpAndSettle();
      await tester.pumpWidget(app(lecture: 'lecture-b', drawing: latest));
      await tester.pumpAndSettle();
      expect(created, hasLength(2));
      expect(created[0]['id'], isNot(created[1]['id']));
      final params = created.last['params'] as Uint8List;
      final decoded = const StandardMessageCodec().decodeMessage(
        ByteData.sublistView(params),
      ) as Map;
      expect(decoded['lectureId'], 'lecture-b');
      expect(decoded['drawing'], latest);
      expect(controller.ready.value, isTrue);
    },
  );

  inkTest('background transition flushes a pending stroke', (tester) async {
    InkDrawingUpdate? changed;
    await tester.pumpWidget(app(onChanged: (update) => changed = update));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(commands, contains('flush'));
    expect(changed?.drawing, latest);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
