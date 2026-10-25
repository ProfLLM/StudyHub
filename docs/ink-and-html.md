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

On iPad, a modal system Safari controller keeps the app active during loopback sign-in. On macOS, the system browser returns through the loopback listener. macOS sign-in, stored-session reuse, and seven public synthetic conversions have completed through a real account with credit fallback disabled. The iPad account flow still needs device acceptance; mocked protocol tests do not establish that path. A connection can be initiated or disconnected from the workspace. Sign-in allows up to 15 minutes and closes its local callback on timeout or cancellation. If it expires, select Continue with ChatGPT to start a fresh session; reloading an expired callback URL cannot complete sign-in. **Continue with ChatGPT** starts sign-in; a first-success notice explains plan usage, and **Manage usage** opens the account’s app limits. Declined plan permission can be explicitly requested again; terminal refresh errors clear only the unusable session while retaining its registration.

OpenAI’s current plan-usage route can draw from included allowance or an existing credits balance according to account/app settings. There is no documented request parameter that forces included allowance only. Before live tests under the owner’s $0 requirement, verify credit fallback is disabled in ChatGPT usage settings, or set StudyHub’s credit limit to zero if that control is offered. The app does not buy credits, change billing, or substitute an API-billed route. See [OpenAI’s usage guidance](https://developers.openai.com/siwc/ui-ux-guidelines).

Claude support is deferred to [issue #6](https://github.com/ProfLLM/StudyHub/issues/6). There is no Claude setup, connector, hosting, or conversation flow in this delivery.

### Local connection storage

On iPad, credentials use non-synchronizing `WhenUnlockedThisDeviceOnly` Keychain records. On macOS, ChatGPT uses the standard encrypted local Keychain with an explicit calling-app ACL. Exact-item permission checks reject broad, foreign, duplicate, or changed-identity records before reading or overwriting secrets; operations suppress Keychain prompts and run on a shared background executor with completion on the UI thread. This supports ordinary local app builds without developer-device registration. No Apple account changes were made.

macOS file-based Keychain backup and migration follow OS policy; this choice does not provide iOS-style `ThisDeviceOnly` guarantees. Its APIs are legacy and may need revisiting for distribution. Ad hoc code-identity changes can require disconnecting with the original app or removing only its matching provider record in Keychain Access before reconnecting. Stable signing avoids that development limitation. These choices remain revisable; see [Apple TN3137](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains) and [calling-app ACL defaults](https://developer.apple.com/documentation/security/secaccesscreate(_:_:_:)).

## Static HTML isolation

The assistant is asked for self-contained HTML, inline vector diagrams, and MathML equations. Generated scripts and remote rendering libraries are not required. Unknown or ambiguous handwriting should be marked for review rather than silently invented. Static SVG patterns, exponent positioning, and semantic deletion/insertion markup preserve shaded regions, labels, and corrections. WebKit-incompatible SVG context paint uses the diagram’s current text color so marker arrowheads remain visible.

An HTML parser removes active elements, event attributes, remote resource references, and unsafe CSS. A restrictive content security policy is inserted before the content. Native WebKit prepends its own restrictive CSP, independently disables page JavaScript, uses nonpersistent website storage, blocks network/file loads, and cancels nonlocal navigation. No page-to-native message handler is installed.

This supports static study notes. Interactive scripts, animations, arbitrary external links, and remotely hosted fonts/assets are outside this increment.

## Build and validate

Use the README's Flutter 3.47.7 / Dart 3.13.5 toolchain and full Xcode. For a contribution, run the required builds before the final test suite, then formatting and analysis:

```sh
flutter pub get
flutter build macos --release
flutter build ios --simulator --debug --no-codesign
flutter test
# Use a Python environment with Pillow installed:
python3 test_fixtures/ai_quality/validate.py
dart format --output=none --set-exit-if-changed lib test integration_test test_driver live_test
flutter analyze
```

List simulators with `xcrun simctl list devices available`. Run native tests with the chosen iPad simulator identifier substituted below:

```sh
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner \
  -configuration Debug -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
```

Run macOS native image/credential tests without developer-account setup:

```sh
xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -parallel-testing-enabled NO test
```

Keychain tests use fresh UUID-scoped records with disposable synthetic values, validate actual stored ACLs and round trips, and delete only those exact records. They never inspect real provider credentials.

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
- The six-sheet synthetic semantic corpus in `test_fixtures/ai_quality/` covers equations, diagrams, corrections, order, and uncertainty. It is handwriting-style synthetic content, not evidence of physical handwriting recognition. Its report template records unrun provider cases as `not_run`.
- Live-provider accuracy and quota behavior require an authenticated account and representative image runs. Credentials and private notes must never enter fixtures or logs.
- A macOS build is a regression check; it is not an iPad or native renderer validation.

Record actual commands, devices, failures, and coverage gaps with each delivery. The first physical Pencil test is the owner's single final experience review, as explicitly requested.

### Optional stable macOS signing

When an Apple Development identity is already installed locally, optional stable signing can use it without portal updates or device registration. Replace the placeholder with that identity's team; do not commit local signing details:

```sh
xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY='Apple Development' \
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM='<YOUR_TEAM_ID>' build
```

The ordinary ad hoc contributor build path remains unchanged. A copied app with a fresh disposable bundle identifier and an existing local development identity passed the same UUID-only Keychain/ACL tests; no production credential records or Apple account settings were accessed. This validates local signing and storage, rather than distribution or notarization.
