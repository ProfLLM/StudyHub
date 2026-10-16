# Architecture blueprint

The first implementation is a small Flutter macOS navigation prototype using Class → Lectures → study content and local JSON files. The sections below distinguish that implementation from proposals for the richer learning experience.

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

Candidate content types include written notes, voice-derived material, future ink, images or diagrams, HTML learning content, and animations. Their schemas and exact representation should be selected when the editing experience is clearer.

Design the model so that:

- Items can be addressed without relying on screen coordinates or widget state.
- Text and other source material can retain links to their enrichments.
- Stored content has an explicit schema version and a migration path.
- Unknown or unavailable content types can show a useful fallback.
- Rich content can reference assets through controlled identifiers rather than unrestricted file paths.
- The app can identify the current revision when an external tool proposes an edit.

Do not make a single HTML document the implicit source of truth for every kind of content. HTML should be a supported enrichment representation with its own rendering boundary; the underlying study structure should remain addressable and portable.

## Capture

Typed input, voice input, and future ink capture should feed the shared model through editing operations. Platform adapters can provide device or operating-system capabilities without leaking those APIs into the domain model.

Voice behavior needs a product decision about dictation, recordings, transcription, retention, and processing location. Ink needs decisions about stroke storage and optional recognition. Neither requires storing raw source media by default at this stage.

## Canvas and rich content

Separate content meaning from its presentation. The canvas should combine ordinary editable notes with rich learning material while keeping their relationships clear.

A rendering boundary should define:

- How each content type is displayed and edited across platforms.
- How HTML, animations, and their assets are packaged.
- Which interactions or permissions an embed may request.
- How loading failures, unsupported content, and unavailable network resources appear.
- How accessibility, reduced motion, and static fallbacks work.

Treat imported and AI-generated HTML as untrusted input. Any support for scripts, network requests, navigation, local files, or native bridges needs an explicit policy and isolation design. An embed should not gain access to the learner's full library or the app's credentials merely by appearing on the canvas.

The choice of HTML renderer, animation format, and sandboxing mechanism remains open. Validate that choice on macOS and against the intended cross-platform direction before committing to it.

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

Integration discovery, authentication, transport, and permission UX are open questions. The goal of using a learner's own subscription must be tested against the providers' supported connection paths; this blueprint does not establish that any particular subscription can power a third-party app. Do not base the design on credential scraping, unsupported access, or an assumed API entitlement.

## Persistence and privacy

The navigation prototype uses local JSON storage, so learners can browse their library without an AI connection. `JsonLibraryStore` implements the `LibraryStore` boundary; `path_provider` selects the macOS application support directory. The file has `schemaVersion: 1`, Classes with nested Lectures, stable random IDs, titles, and a notes string for each Lecture.

Writes flush a temporary file before renaming it over the library. UI state changes only after a successful save. Missing files mean a new empty library; malformed files and unsupported versions block editing without overwriting data. There is no migration, multi-process locking, automatic backup, or sync implementation. Deleting a Class cascades to its Lectures after GUI confirmation. See the [README](../README.md) for location, backup/reset guidance, and the JSON shape.

This is an interim storage choice for the navigation prototype. Long-term asset storage and portability remain open.

Keep a persistence interface between the model and storage. Evaluate serialization, asset storage, schema migration, backup, and portable export together. Cloud sync, accounts, collaboration, and encryption policies remain undecided.

External AI processing should have an explicit context boundary: share only content authorized for the requested task. Define credential handling, voice retention, and recording consent before implementation. Avoid leaking private study material into diagnostics or repository fixtures.

## Implemented Flutter layout

```text
lib/
├── main.dart                   # Native path lookup and composition
├── app/study_hub_app.dart       # Material UI, navigation, CRUD dialogs, placeholder canvas
├── domain/library.dart         # Flutter-independent model, IDs, JSON schema validation
└── persistence/library_store.dart # Storage interface and local JSON adapter
test/                           # File persistence and navigation widget tests
macos/                          # Generated Flutter macOS runner
```

The prototype uses Flutter's built-in state and navigation mechanisms. Its only direct runtime package beyond Flutter is `path_provider`. Schema versioning and stable identities are implemented; structured rich-content items, external editing rules, history, and undo remain proposals. The notes canvas displays stored plain text when present and an empty-state message otherwise; editing is not implemented.

Future platform adapters should keep capture, rendering, and OS capabilities behind explicit boundaries. Add other platform runners when their implementation is authorized; extract packages only when concrete reuse justifies them.

## Validation

The [README](../README.md) documents formatting, analysis, tests, and native build commands. Automated tests exercise persistence round trips, invalid schemas, failed writes, GUI CRUD, navigation, and error states. Widget tests do not validate the native path provider, sandbox, runner, or window behavior; build and launch on macOS with full Xcode to validate those boundaries.

Future HTML isolation, capture, external edits, and richer content rendering require targeted tests when implemented.
