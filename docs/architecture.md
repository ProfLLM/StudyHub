# Architecture blueprint

StudyHub implements Class → Lectures → study content with local JSON storage, macOS navigation, and an iPad ink workspace with a separate static HTML rendition. The sections below distinguish this increment from proposals for the broader learning experience. See [Ink and HTML](ink-and-html.md) for its concrete boundaries and validation commands.

## Boundaries

```text
Flutter app
├── Lecture and Class navigation
├── Note capture
└── Learning canvas
         │
         ▼
Shared content model and editing rules
         ▲                         │
         │                         ▼
AI integration boundary       Persistence boundary

Platform adapters provide capture, rendering, and OS capabilities.
```

The app and external assistants should use the same content model and editing rules. Platform-specific capture and rendering should not determine the stored identity or meaning of a note.

## Proposed content model

| Concept | Responsibility |
| --- | --- |
| Class | Stable identity, metadata, and references to its Lectures. |
| Lecture | Stable identity, parent Class, metadata, and study content. |
| Content item | An identifiable, typed unit of study content with a versioned payload. |
| Enrichment | A content item linked to the material it explains or extends. |
| Asset | Referenced media or other resources used by content, subject to access rules. |
| Edit | A validated content change made by the learner or an authorized integration. |

Content items are a proposed way to give notes and rich material stable identities. They are not a commitment to a particular editor or storage engine.

Candidate content types include written notes, voice-derived material, ink, images or diagrams, HTML learning content, and animations. Their schemas and exact representation should be selected when the editing experience is clearer.

Design the model so that:

- Items can be addressed without relying on screen coordinates or widget state.
- Text and other source material can retain links to their enrichments.
- Stored content has an explicit schema version and a migration path.
- Unknown or unavailable content types can show a useful fallback.
- Rich content can reference assets through controlled identifiers rather than unrestricted file paths.
- The app can identify the current revision when an external tool proposes an edit.

Do not make a single HTML document the implicit source of truth for every kind of content. HTML should be a supported enrichment representation with its own rendering boundary; the underlying study structure should remain addressable and portable.

## Capture

The iPad adapter captures editable PencilKit source and portable PNG previews. A fixed logical width preserves stroke coordinates across rotation and Split View. Atomic snapshots bind drawing bytes, preview, exported image tiles, and a mutation counter to the same source revision. Scrolling is vertical with a hard top and at most one blank viewport below the last ink; scrolling alone cannot extend it.

Typed editing and voice input remain future capture methods. They should feed the shared model through editing operations. Platform adapters can provide device or operating-system capabilities without leaking those APIs into the domain model.

Voice behavior needs a product decision about dictation, recordings, transcription, retention, and processing location. Ink recognition is delegated to an explicitly requested enrichment; original strokes remain editable. Voice does not require storing raw source media by default at this stage.

## Canvas and rich content

Separate content meaning from its presentation. The canvas should combine ordinary editable notes with rich learning material while keeping their relationships clear.

A rendering boundary should define:

- How each content type is displayed and edited across platforms.
- How HTML, animations, and their assets are packaged.
- Which interactions or permissions an embed may request.
- How loading failures, unsupported content, and unavailable network resources appear.
- How accessibility, reduced motion, and static fallbacks work.

Treat imported and AI-generated HTML as untrusted input. Any support for scripts, network requests, navigation, local files, or native bridges needs an explicit policy and isolation design. An embed should not gain access to the learner's full library or the app's credentials merely by appearing on the canvas.

The current static rendition uses native WebKit on iPad and macOS. Parsed HTML is sanitized and wrapped in a restrictive CSP; WebKit independently disables page scripts, blocks network/file loads, uses nonpersistent storage, and cancels external navigation. Inline SVG and MathML support diagrams and equations. There is no page-to-native bridge. Animation and interactive content remain future work. Renderer failure retains source and offers a readable text fallback.

## AI interoperability

Design an app-owned editing boundary that both the UI and authorized external tools can use. Keep the contract independent of a particular assistant or model provider.

The future contract should cover:

- Discovering and reading authorized Classes, Lectures, and content items.
- Creating and updating supported study content, including study plans.
- Attaching enrichments and required assets.
- Reporting validation failures, unsupported content, and edit conflicts clearly.
- Returning stable identifiers and resulting revisions so the assistant can describe its work accurately.

Edits should be scoped to the learner's request, checked against the content schema, and applied through normal app rules. A grouped change should either apply coherently or report failure without leaving partial content. Plan for undo and a clear review or confirmation experience where the action warrants one.

Use revision checks to avoid silently overwriting content changed since an assistant read it. Exact transaction, history, and conflict-resolution mechanisms are still undecided.

The current provider boundary accepts only a confirmed Lecture snapshot and returns HTML through app-owned sanitization and revision checks. A newer source is preserved and marks an older result stale. Cancellation and failed conversion retain the previous rendition.

ChatGPT uses its documented open-source subscription route with browser OAuth, PKCE, signed token validation, Keychain storage, model discovery, and streaming inference. macOS account access and seven public synthetic conversions have completed; iPad sign-in and physical handwriting remain device acceptance checks. Account settings may allow existing-credit consumption; verify credit fallback is disabled (or an app credit limit is zero) before the owner’s allowance-only live tests. Claude support is deferred to [issue #6](https://github.com/ProfLLM/StudyHub/issues/6); no connector service or Claude adapter is included. No API billing or manual import fallback is substituted. General external editing, history, and integration discovery remain proposals. Do not use credential scraping or assume subscription API entitlement.

## Persistence and privacy

The navigation prototype uses local JSON storage, so learners can browse their library without an AI connection. `JsonLibraryStore` implements the `LibraryStore` boundary; `path_provider` selects the native application support directory. The file has `schemaVersion: 1`, Classes with nested Lectures, stable random IDs, titles, and a notes string for each Lecture.

Writes flush a temporary file before renaming it over the library. UI state changes only after a successful save. Missing files mean a new empty library; malformed files and unsupported versions block editing without overwriting data. There is no migration, multi-process locking, automatic backup, or sync implementation. Deleting a Class cascades to its Lectures after GUI confirmation. See the [README](../README.md) for location, backup/reset guidance, and the JSON shape.

Per-Lecture sidecars hold versioned editable ink, a PNG preview, and optional HTML with its source revision, leaving the existing library format unchanged. Source saves are serialized within the process and reject stale/conflicting revisions. Navigation awaits pending saves; failed saves remain visible and retryable. See [Ink and HTML](ink-and-html.md) for size limits and portability tradeoffs.

Connection credentials stay in OS Keychain, separate from Lecture files. iPad uses device-only records; macOS uses encrypted local Keychain with calling-app ACL validation, allowing ordinary builds without developer-device registration. macOS backup and code-signing tradeoffs are documented in [Ink and HTML](ink-and-html.md).

This is an interim storage choice. Long-term asset storage and portability remain open.

Keep a persistence interface between the model and storage. Evaluate serialization, asset storage, schema migration, backup, and portable export together. Cloud sync, accounts, collaboration, and encryption policies remain undecided.

External AI processing should have an explicit context boundary: share only content authorized for the requested task. Define credential handling, voice retention, and recording consent before implementation. Avoid leaking private study material into diagnostics or repository fixtures.

## Implemented Flutter layout

```text
lib/
├── main.dart                    # Native paths, isolated development profile, composition
├── app/                         # Library navigation and Lecture Ink / HTML workspace
├── domain/                      # Library and versioned Lecture content
├── persistence/                 # Atomic JSON library and per-Lecture sidecars
├── ink/                         # Platform-independent capture interface and geometry
├── ai/                          # Provider interface and ChatGPT subscription adapter
└── enrichment/                  # Static HTML validation and sanitization
ios/Runner/                      # PencilKit, isolated WebKit, browser auth and Keychain
macos/Runner/                    # Isolated WebKit, browser auth and Keychain
test/                            # Domain, persistence, protocol and widget tests
integration_test/                # Native synthetic Lecture flow
```

The app uses Flutter's built-in state and navigation mechanisms. Direct runtime dependencies are `path_provider`, `html`, `crypto`, and `jose`. Rich content-item schemas, generalized external editing, history, and cross-platform ink editing remain proposals. Platform adapters remain behind explicit interfaces; packages are extracted only when concrete reuse justifies them.

## Validation

The [README](../README.md) and [Ink and HTML](ink-and-html.md) document build, test, formatting, and analysis commands. Dart tests cover persistence, revision races, provider protocols, sanitization, navigation, and narrow layouts. Native simulator tests cover PencilKit geometry/export and WebKit isolation; the synthetic full-flow test combines real native capture, storage, consent, separate HTML, staleness, and reopening.

Fixtures do not establish live account access or model accuracy. Simulator strokes do not establish Pencil latency, pressure, or palm rejection. Record actual device and command evidence; keep physical Pencil acceptance and live-provider verification explicit.
