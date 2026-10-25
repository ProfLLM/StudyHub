# Lecture assignments

**Create assignment** sends a confirmed Lecture snapshot and the learner's request through the existing ChatGPT subscription connection. ChatGPT chooses activities around the material: prediction, explanation, multiple choice, written reasoning, drawing, or interactive demonstrations. Creating another assignment preserves earlier assignments, answers, original ink, and the static HTML rendition.

Interactive assignments require **iPadOS 16 or macOS 13 or later**. Older systems retain lecture and static HTML features but refuse to execute assignment scripts; saved assignments and answers are preserved.

## Workflow

1. Open a Lecture with ink or existing text notes and choose **Create assignment**. Describe what would help you understand, then confirm the lecture material to send.
2. Open **Assignments**, select an assignment, and work through its activities. Form responses, custom interaction state, and answer-canvas images save locally. Leaving or switching assignments flushes pending answers; save failures block navigation and offer retry.
3. Choose **Ask ChatGPT to review** to send a saved snapshot. The confirmation identifies the assignment, current lecture title/text, saved teaching HTML for a Lecture without ink, current ink preview when available, answer text/custom state, and ink-answer PNGs. These are sent only after confirmation.
4. Read feedback separately. Original answers remain editable. Editing after review marks feedback as belonging to earlier answers; changed lecture ink is also identified.

ChatGPT can inspect handwritten math reasoning and drawings; these are not graded by a deterministic checker. The review prompt asks for evidence, uncertainty, the first incorrect step, and useful guidance. Feedback can still be wrong. Embedded checks are for objective answers or self-comparison. No assignment script can trigger a provider request. Existing plan/credit settings apply; there is no additional API-billed fallback.

## Isolation

```text
App: lecture, provider connection, file storage
  └── App-owned WebKit host (nonpersistent storage)
       └── Opaque-origin iframe: generated HTML + JavaScript
             └── Bounded answer JSON → validation → current assignment only

App review action → confirmation → ChatGPT → separate static feedback
```

The assignment frame has `sandbox="allow-scripts"`, without same-origin access, popups, downloads, navigation privileges, or form submission. App-owned content-security policies precede scripts. Scripts use nonce-bearing inline tags; event attributes and externally loaded scripts are removed. Policies block network, external resources, workers, and files. Native WebKit independently blocks URL schemes other than in-memory `about:` documents and `data:` images, and rejects external navigation. The renderer also enables WebKit’s public per-view Lockdown preference before creating the view. This disables WebRTC throughout its frame tree, closing the ICE socket and DNS path that CSP and URL blockers do not cover. Systems without that preference fail closed. The device’s system-wide Lockdown setting is unchanged. Its message handler accepts only main-frame messages. The host accepts messages only from its assignment frame; Flutter validates JSON shape, size and depth. No library, credential or AI capability is exposed to generated code.

The **HTML** lecture viewer and feedback viewer remain static, script-disabled renderers.

## Generated interaction contract

The app supplies `window.studyhub` before assignment scripts execute:

| Interaction | Contract |
| --- | --- |
| Text, selection, radio, checkbox | A stable `data-answer-key` on each input. Radios in one group share a key. Values autosave and restore. Multiple selects save an array; existing scalar selections remain readable. |
| Ink | A `canvas` with a stable `data-answer-key`, fixed logical dimensions, and white background. Runtime supplies pointer/Pencil input and PNG persistence. Include an accessible text alternative. |
| Clear ink | Call `studyhub.clearInk(key)` from a labeled button. |
| Custom interaction | Restore with `studyhub.getAnswer(key)`; save JSON-safe values with `studyhub.setAnswer(key, value)`. |

Use inline `addEventListener` scripts, semantic HTML, keyboard-accessible controls, SVG/MathML, and reduced-motion support. Initialize controls on `DOMContentLoaded`. External libraries, network resources, uploads, local storage and AI calls are unavailable. Ink uses browser pointer input, independent of the native PencilKit lecture canvas. It saves raster images; clear/redraw is available, but stroke-level undo and pressure fidelity are not provided.

## Persistence and bounds

The library stays schema v1. Lecture sidecars without assignments keep their format; adding an assignment writes sidecar schema v2, which this app reads alongside v1. Older builds reject v2 rather than silently dropping assignments. Back up the complete support directory before moving between versions.

Each assignment has a stable ID, immutable generated HTML and learner request, source ink revision, answer JSON/revision, and optional feedback associated with an answer revision. Writes remain serialized and atomic. Stale writes cannot remove existing assignments or replace newer answers. Automatic regeneration, assignment deletion, history archives, cloud sync and cross-device merges are outside this increment.

Limits: 20 assignments per Lecture; 1 MiB of HTML per assignment or feedback; 4 MiB of answer JSON per assignment; 12 ink canvases at most 1600×1600 logical pixels each. The existing 50 MiB sidecar limit still applies. Limits produce errors instead of silently truncating answers. PNG serialization is debounced; navigation/review flush pending changes. Completed assignments and feedback enter the save queue independently of ink-view presentation, so a failed view pause cannot skip persistence. Review image attachments and their numbered references are built together from validated PNG entries; ordinary custom state is preserved.

## Verification

Use the builds and checks in [Ink and HTML](ink-and-html.md), plus:

```sh
flutter test integration_test/assignment_flow_test.dart -d macos
flutter test integration_test/assignment_flow_test.dart -d <IPAD_SIMULATOR_UDID>
```

The integration test uses synthetic content, local TCP and UDP traps, real WebKit, and a deterministic provider. It exercises creation, answer persistence, opaque-origin isolation, direct bridge rejection, network/file blocking (including WebRTC and new frames), multi-select save/restore, review consent and image submission, and reopening. Unit/widget tests cover migration, bounds, stale writes, cancellation, failed saves, provider payloads, and answers edited during review. These tests do not establish live ChatGPT assignment quality, physical Pencil feel, or handwriting assessment accuracy.

The assignment surface retains the full available width after its loading indicator disappears. A layout regression test checks the loaded iPad view, and the native flow checks that the ready WebKit surface has usable dimensions.
