# StudyHub

StudyHub is a Flutter study app, starting with macOS. This first prototype focuses on navigation and saves your library to a local JSON file.

```text
Class
└── Lectures
    └── Notes canvas
```

Create, browse, rename, and delete Classes and Lectures through the GUI. Select a Class to see its Lectures; select a Lecture to open its notes canvas. Use the breadcrumbs to return, or select another Class in the sidebar. Narrow windows use a navigation drawer. Names are required; deletion asks for confirmation and deleting a Class also deletes its Lectures and notes.

The canvas is a read-only placeholder. Note editing, voice input, rich content, AI connections, accounts, and sync are future work.

## Build and open on macOS

### 1. Install the tools

- Install [Flutter](https://docs.flutter.dev/install/manual) and add its `bin` directory to your PATH. This project was generated and checked with **Flutter 3.47.7 / Dart 3.13.5**; use that version for reproducibility. The SDK constraints are in [pubspec.yaml](pubspec.yaml) and dependency versions are in [pubspec.lock](pubspec.lock).
- Install the full **Xcode** application from the Mac App Store, open it once, and complete its setup. Command Line Tools alone cannot build a macOS Flutter app. Follow [Flutter's macOS setup guide](https://docs.flutter.dev/platform-integration/macos/setup), including CocoaPods if requested by `flutter doctor` for native plugins.
- The generated runner targets **macOS 12 or later**. Other platform runners have not been added or tested.

If Xcode is installed at its usual location, select and initialize its tools:

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
flutter doctor -v
```

Resolve issues under Flutter and Xcode reported by `flutter doctor`. Android and iOS device setup are unnecessary for this macOS prototype.

### 2. Run while developing

From the repository root:

```sh
flutter pub get
flutter run -d macos
```

This builds and opens a desktop window. In the terminal, press `r` to hot reload, `R` to restart, or `q` to quit. The first dependency download and build require internet access; using the app does not.

To try the navigation: click **New class**, give it a name, click **New lecture**, and open that Lecture. Use the three-dot menus to rename or delete either kind of item. Quit and reopen to check that your library persists.

### 3. Build a standalone app

```sh
flutter pub get
flutter build macos --release
open "build/macos/Build/Products/Release/StudyHub.app"
```

You can also open that `StudyHub.app` bundle in Finder. It is a local build; signing/notarization for distribution is not configured. To inspect the native runner in Xcode after dependency setup:

```sh
open macos/Runner.xcworkspace
```

## Local data

The app uses `path_provider` to locate its application support directory and writes **`library.json`** there. With the checked-in sandbox and bundle ID, the expected location is:

```text
~/Library/Containers/org.profllm.studyhub/Data/Library/Application Support/org.profllm.studyhub/library.json
```

A build without sandboxing would instead use `~/Library/Application Support/org.profllm.studyhub/library.json`. The native path lookup has not yet been verified in a running macOS build. Data is outside the repository and survives app rebuilds.

The single file contains schema version 1, stable IDs, Classes with nested Lectures, and each Lecture's notes string. New Lectures have empty notes. A minimal example is:

```json
{
  "schemaVersion": 1,
  "classes": [
    {
      "id": "example-class",
      "title": "Physics",
      "lectures": [
        {"id": "example-lecture", "title": "Motion", "notes": ""}
      ]
    }
  ]
}
```

Each change is saved immediately by flushing a temporary file and renaming it over the library. Failed saves leave the displayed library unchanged. Invalid JSON or an unsupported schema blocks editing and offers Retry; the app does not replace an unreadable library with an empty one.

For a backup or reset, quit the app first, then copy or move `library.json`. Moving it aside starts an empty library next launch. Use one app instance at a time; concurrent writers, migrations, automatic backups, and sync are outside this prototype. Avoid editing the file while the app is open.

## Checks

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

Tests cover file round trips, schema errors, failed writes, class/lecture CRUD, parent navigation, save/load errors, and narrow-window navigation. Native macOS build and launch still need validation on a machine with full Xcode installed.

## Project direction and contributions

The longer-term goal is a learning canvas for notes, visuals, interaction, and animation, with supported connections to the learner's own ChatGPT or Anthropic subscription. Those connections are not implemented or validated.

| Document | Purpose |
| --- | --- |
| [Product vision](docs/product-vision.md) | Terminology, prototype scope, and long-term direction. |
| [Architecture](docs/architecture.md) | Implemented boundaries and future proposals. |
| [Decisions](docs/decisions.md) | Confirmed choices and unresolved questions. |
| [Contributing](CONTRIBUTING.md) | Human and AI-assisted contribution guidance. |
| [AGENTS.md](AGENTS.md) | Shared coding-agent instructions. |
| [CLAUDE.md](CLAUDE.md) | Pointer to the shared instructions. |

Contributions are welcome. StudyHub is licensed under the [MIT License](LICENSE).
