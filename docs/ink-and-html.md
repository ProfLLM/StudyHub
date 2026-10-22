# iPad ink and HTML

This increment adds an iPad Lecture workspace to the existing Flutter library. It keeps Class → Lectures → study content and the existing library format.

## Workflow

1. Create a Class and Lecture. The new Lecture opens in Ink on iPad.
2. Write with Pencil; use a finger to pan vertically. For simulator or finger input, enable **Draw with finger** and use two fingers to pan.
3. The top is a hard stop. Scrolling cannot add blank paper: at most one usable viewport remains below the last ink. Rotation and Split View change the presentation without changing stored stroke coordinates.
4. Choose **Create HTML**, review the snapshot and transmission scope, and confirm **Send notes**. Only that Lecture's images, title, and existing text notes are sent to the selected provider.
5. A completed, validated result becomes a separate HTML rendition. **Ink / HTML** switches between them. More writing preserves the rendition and marks it **HTML needs refresh**.

Ink tools include the native palette, erasing, undo, and redo. Save failures remain visible and offer retry. Navigation waits for pending source saves. Native source continues to work without a provider connection.

## Simple local storage

`library.json` remains schema version 1. Each Lecture optionally has a file in `lecture-content/`, using its UTF-8 identity encoded as lowercase hex for a filesystem-safe name. A sidecar contains:

- Native editable PencilKit drawing bytes and portable PNG preview, encoded in JSON.
- A source revision, derived from the loaded revision plus native drawing mutations.
- Optional static HTML, provider name, and the source revision used to create it.

Source and enrichment are never the same field. Writes flush a temporary file before renaming it over the destination. In-process serialization rejects stale/conflicting source saves. Malformed files are preserved and block editing of that Lecture; a corrupt HTML rendition does not prevent opening its ink. There is no multiprocess locking or cloud synchronization.

Back up the whole application support directory, not only `library.json`. Native ink is deliberately an iPad-first choice: non-Apple editing may need a future conversion. macOS can display portable previews and HTML.

Bounds are explicit: 120 UTF-8 bytes for Lecture IDs, 16 MiB each for native drawing and preview, 4 MiB for HTML, and 50 MiB for the sidecar JSON. Snapshot export permits at most 32 overlapping image tiles and 32 MiB of PNG data; excessive output fails visibly and is not silently truncated.

For isolated development runs, use `--dart-define=STUDYHUB_PROFILE=some-test-name`. This selects separate library and content filenames in application support. Automated integration tests use their own disposable temporary directories and synthetic sources.

## Providers and authentication

ChatGPT uses the documented [open-source subscription route](https://developers.openai.com/siwc/token-sharing-open-source). The implementation uses a loopback OAuth callback, PKCE/state/nonce checks, signed ID-token verification, Keychain storage, account model discovery, token refresh, image inputs, and streaming inference. Only a completed response is committed; cancellation, quota errors, failed transport, and malformed results preserve source and previous HTML.

On iPad, a modal system Safari controller keeps the app active during loopback sign-in. On macOS, the system browser returns through the loopback listener. These paths still need live account verification; mocked protocol tests do not establish account access or successful inference. A connection can be initiated or disconnected from the workspace.

Claude Pro direct return is requested but not implemented. Its confirmed mobile connector path requires an internet-reachable authenticated service, as described in [Claude's remote connector documentation](https://support.claude.com/en/articles/11175166-get-started-with-custom-connectors-using-remote-mcp). Hosting/public access has not been approved or deployed. No consumer cookies, native-app tokens, undocumented endpoints, paid API fallback, or manual import are substituted.

## Static HTML isolation

The assistant is asked for self-contained HTML, inline vector diagrams, and MathML equations. Generated scripts and remote rendering libraries are not required. Unknown or ambiguous handwriting should be marked for review rather than silently invented.

An HTML parser removes active elements, event attributes, remote resource references, and unsafe CSS. A restrictive content security policy is inserted before the content. Native WebKit prepends its own restrictive CSP, independently disables page JavaScript, uses nonpersistent website storage, blocks network/file loads, and cancels nonlocal navigation. No page-to-native message handler is installed.

This supports static study notes. Interactive scripts, animations, arbitrary external links, and remotely hosted fonts/assets are outside this increment.

## Build and validate

Use the README's Flutter 3.47.7 / Dart 3.13.5 toolchain and full Xcode. For a contribution, run the required builds before the final test suite, then formatting and analysis:

```sh
flutter pub get
flutter build macos --release
flutter build ios --simulator --debug --no-codesign
flutter test
dart format --output=none --set-exit-if-changed lib test integration_test test_driver
flutter analyze
```

List simulators with `xcrun simctl list devices available`. Run native tests with the chosen iPad simulator identifier substituted below:

```sh
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner \
  -configuration Debug -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
```

Run the synthetic full-flow test on that simulator:

```sh
flutter test integration_test/lecture_flow_test.dart -d <SIMULATOR_UDID>
flutter test integration_test/mac_html_flow_test.dart -d macos

# Preserve iPad screenshots on the host, including native surfaces:
flutter drive --driver=test_driver/lecture_flow_driver.dart \
  --target=integration_test/lecture_flow_test.dart -d <SIMULATOR_UDID>
```

The integration test creates a library in a disposable temporary directory. It uses a DEBUG-only native stroke seed, real PencilKit source/export, actual file storage, a deterministic assistant fixture, and the native HTML renderer. It checks consent, separate renditions, editing/staleness, and reopening. The seed hook is absent from Release. The ordinary simulator test runner may remove its app container after completion. The host driver preserves screenshots in `build/review-screenshots/`; all fixtures and screenshots contain only synthetic study content. The macOS integration test separately exercises actual AppKit/WebKit loading, source preservation, and the native support-directory lookup.

### Evidence boundaries

- Dart tests cover persistence faults, revision/lifecycle races, navigation, narrow layouts, sanitization, and synthetic provider protocol responses.
- Native simulator tests cover bounds, rotation geometry, source round trips, export, undo, and WebKit isolation behavior.
- Synthetic stroke playback does not prove Pencil latency, pressure, palm rejection, or physical handwriting feel.
- Live-provider accuracy and quota behavior require an authenticated account and representative image runs. Credentials and private notes must never enter fixtures or logs.
- A macOS build is a regression check; it is not an iPad or native renderer validation.

Record actual commands, devices, failures, and coverage gaps with each delivery. The first physical Pencil test is the owner's single final experience review, as explicitly requested.
