# Create a Class with ChatGPT

**Create class with ChatGPT** is available on the library screen and in the sidebar. Describe what you want to learn, including your starting level, goals, and preferred examples. **Generate class** uses the existing ChatGPT connection (or starts sign-in) and sends only that description. Existing Classes, notes and answers are not included.

One request asks for a coherent sequence of fully populated Lectures, usually 4–8 and at most 12. Lessons include explanations, worked examples, misconceptions, practice prompts, and diagrams or equations where useful. This is teaching material, not an outline with empty Lectures. The generated material is AI-authored and may contain errors; generation does not claim external research or verified citations.

## Preview and save

The complete response is validated before preview. Use the Lecture selector to read each lesson. **Change request** returns to the prompt; **Close** discards the unsaved draft. **Save class** adds the Class with all its Lectures and opens the first lesson. Nothing is added to the library during generation or preview.

The app validates titles, lesson counts and response sizes, assigns its own IDs, and sanitizes every lesson with the existing static HTML boundary. Lessons support SVG, MathML and collapsible hint/solution sections. Scripts, remote assets and active input controls are not part of the teaching-page renderer. **Create assignment** within each Lecture remains the way to generate interactive practice and request review of answers.

Generated Lectures open in HTML while they have no source ink. Their separate Ink view remains available for the learner's notes. A text rendition with section breaks is retained in the Lecture's existing notes field for readable fallback and assignment context. For a Lecture without ink, assignment creation and review also receive its saved HTML so diagrams and equations remain available to ChatGPT. No library or sidecar schema change is required.

## Saving and recovery

New Lecture sidecars are written first. A single atomic library save then publishes the Class and its Lectures together. The app does not publish a partially written Class. If a write fails, it attempts to remove only the newly allocated sidecars and keeps the draft available for **Save class** retry, without another model request. Existing Class identities, notes, and content files are untouched.

This uses the current local JSON storage, not the proposed database migration. A process crash before the library commit, or a failed cleanup, can leave unreachable sidecar files. They are never displayed as a partial Class. There is no cross-file journal or automatic orphan cleanup in this increment. Normal confirmed Class deletion removes its published Lecture files.

Bounds are 8,000 characters for the learner request, 120 characters per title, 12 Lectures, 256 KiB of returned HTML per Lecture and 2 MiB for the complete response. Larger or invalid responses fail visibly rather than being silently truncated. The existing plan/credit settings and cancellation rules apply; there is no API-billed fallback or automatic per-Lecture model fan-out.

Request failures identify the phase (connection, model discovery, or generation) without recording credentials, prompts, or response bodies. Request bodies use UTF-8 so Unicode text in learning goals and generation instructions is transmitted correctly.

## Checks

In addition to the standard builds, full tests, formatting and analysis:

```sh
flutter test test/class_generation_test.dart
flutter test integration_test/class_creation_flow_test.dart -d macos
flutter test integration_test/class_creation_flow_test.dart -d <IPAD_SIMULATOR_UDID>
```

Unit/widget tests cover validation, sanitization, preview before mutation, complete persistence, rollback, retry without regeneration, cancellation, late account callbacks and narrow layouts. Native tests use a deterministic provider with the real static renderer, local files and reopening. These tests do not establish live ChatGPT teaching quality.
