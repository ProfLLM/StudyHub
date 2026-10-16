import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyhub/app/study_hub_app.dart';
import 'package:studyhub/domain/library.dart';
import 'package:studyhub/persistence/library_store.dart';

class MemoryStore implements LibraryStore {
  StudyLibrary library = StudyLibrary();
  bool failSave = false;
  bool failLoad = false;
  int saves = 0;

  @override
  Future<StudyLibrary> load() async {
    if (failLoad) throw const FormatException('Invalid file');
    return library;
  }

  @override
  Future<void> save(StudyLibrary library) async {
    saves++;
    if (failSave) throw Exception('Disk unavailable');
    this.library = library;
  }
}

Future<void> enterName(
  WidgetTester tester,
  String name, {
  String action = 'Create',
}) async {
  await tester.enterText(find.byType(TextFormField), name);
  await tester.tap(find.widgetWithText(FilledButton, action));
  await tester.pumpAndSettle();
}

Future<void> menuAction(
  WidgetTester tester,
  String tooltip,
  String action,
) async {
  await tester.tap(find.byTooltip(tooltip));
  await tester.pumpAndSettle();
  await tester.tap(find.text(action));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('class and lecture CRUD, parent navigation, and reopening', (
    tester,
  ) async {
    final store = MemoryStore();
    await tester.pumpWidget(StudyHubApp(openStore: () async => store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New class'));
    await tester.pumpAndSettle();
    await enterName(tester, 'Physics');
    final classId = store.library.classes.single.id;
    await tester.tap(find.text('New lecture'));
    await tester.pumpAndSettle();
    await enterName(tester, 'Motion');
    final lectureId = store.library.classes.single.lectures.single.id;
    await tester.tap(find.text('Motion'));
    await tester.pumpAndSettle();
    expect(find.text('Your notes start here.'), findsOneWidget);
    await menuAction(tester, 'Lecture actions: Motion', 'Rename');
    await enterName(tester, 'Forces', action: 'Save');
    expect(store.library.classes.single.lectures.single.id, lectureId);
    expect(find.text('Forces'), findsOneWidget);

    // A second class has its own empty lecture list.
    await tester.tap(find.text('New class'));
    await tester.pumpAndSettle();
    await enterName(tester, 'History');
    expect(find.text('Forces'), findsNothing);
    expect(
      find.text('No lectures yet. Add your first lecture above.'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(ListTile, 'Physics'));
    await tester.pumpAndSettle();
    expect(find.text('Forces'), findsOneWidget);
    await menuAction(tester, 'Class actions: Physics', 'Rename');
    await enterName(tester, 'Mechanics', action: 'Save');
    expect(store.library.classes.first.id, classId);

    // Rebuild a new app against the saved library, like a fresh launch.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(StudyHubApp(openStore: () async => store));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Mechanics'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forces'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Mechanics'));
    await tester.pumpAndSettle();
    expect(find.text('Open notes canvas'), findsOneWidget);
    await menuAction(tester, 'Lecture actions: Forces', 'Delete');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.library.classes.first.lectures, hasLength(1));
    await menuAction(tester, 'Lecture actions: Forces', 'Delete');
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(store.library.classes.first.lectures, isEmpty);

    // Deleting the selected class while its canvas is open returns to the library.
    await tester.tap(find.text('New lecture'));
    await tester.pumpAndSettle();
    await enterName(tester, 'Energy');
    await tester.tap(find.text('Energy'));
    await tester.pumpAndSettle();
    await menuAction(tester, 'Class actions: Mechanics', 'Delete');
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(store.library.classes.single.title, 'History');
    expect(find.text('Your notes start here.'), findsNothing);
    expect(find.text('Make space for your next idea.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty names and failed saves do not change the library', (
    tester,
  ) async {
    final store = MemoryStore();
    await tester.pumpWidget(StudyHubApp(openStore: () async => store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New class'));
    await tester.pumpAndSettle();
    await enterName(tester, '   ');
    expect(find.text('Enter a name.'), findsOneWidget);
    expect(store.saves, 0);
    store.failSave = true;
    await enterName(tester, 'Physics');
    expect(
      find.text('Could not save. Your change was not applied. Try again.'),
      findsOneWidget,
    );
    expect(store.library.classes, isEmpty);
    store.failSave = false;
    await tester.tap(find.text('New class'));
    await tester.pumpAndSettle();
    await enterName(tester, 'Physics');
    expect(store.library.classes.single.title, 'Physics');
  });

  testWidgets('failed load blocks editing and can retry without overwriting', (
    tester,
  ) async {
    final store = MemoryStore()..failLoad = true;
    await tester.pumpWidget(StudyHubApp(openStore: () async => store));
    await tester.pumpAndSettle();
    expect(find.text('Could not open your library.'), findsOneWidget);
    expect(find.text('New class'), findsNothing);
    expect(store.saves, 0);
    store.failLoad = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('New class'), findsOneWidget);
  });

  testWidgets('narrow window uses a drawer and opens the selected class', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = MemoryStore()
      ..library = StudyLibrary(
        classes: [StudyClass(id: 'c', title: 'Physics')],
      );
    await tester.pumpWidget(StudyHubApp(openStore: () async => store));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Physics'));
    await tester.pumpAndSettle();
    expect(find.text('New lecture'), findsOneWidget);
    expect(
      find.text('No lectures yet. Add your first lecture above.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
