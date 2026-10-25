# Decisions and open questions

Keep confirmed requirements separate from proposed implementation choices. Update this register when a decision is agreed upon, and update the related blueprint at the same time.

## Confirmed direction

| Topic | Decision |
| --- | --- |
| Framework | Build the app with Flutter. |
| Branding | Use the white-background StudyHub logo; use its book-and-connections symbol alone for the macOS app icon. |
| Platforms | Cross-platform direction; begin implementation on macOS. |
| Organization | A Class contains Lectures; Lectures contain study content. Explicitly changed from the earlier hierarchy for the requested navigation prototype. |
| Capture | Typed notes, voice, and ink are intended. Ink is brought forward for the explicitly requested iPad increment; typed-note editing and voice remain future work. |
| Learning | Go beyond text with a smart canvas, rich content, and animation. |
| Enrichment | Make notes easy to enrich through HTML, including ink-based notes. |
| AI providers | Aim to work with the learner's own ChatGPT or Anthropic subscription. |
| AI editing | Let ChatGPT and Claude write and update app content at the learner's request, such as a study plan. |
| Community | Open source, AI friendly, and welcoming to everyone. |
| Merge approval | Changes to `main` require a pull request and at least one approving review from another human team member with write access. Repository administrators may merge their own pull requests without peer approval; the exception is limited to pull request merges. See [CONTRIBUTING.md](../CONTRIBUTING.md). |
| Open-source license | MIT, selected for its simple, permissive terms. See [LICENSE](../LICENSE). |
| Current scope | GUI CRUD and local JSON persistence, plus the authorized iPad ink, separate HTML and Lecture assignment increments below. Broader V0 planning remains separate. |
| Prototype storage | A single versioned local JSON file in application support; no database or cloud service. |
| Prototype tooling | Flutter 3.47.7 / Dart 3.13.5; macOS runner targets 12.0+. Built-in state/navigation; `path_provider` locates app storage. |
| Prototype deletion | Confirm deletion; deleting a Class also deletes its Lectures and notes. No undo in this prototype. |

## iPad ink and HTML increment

**Status:** implementation authorized by the owner on October 22, 2026. These storage choices are intentionally simple and revisable.

| Topic | Decision |
| --- | --- |
| Canvas | iPad native editable ink. Vertical pan only, hard top stop, at most one blank viewport beyond the last ink; content grows from drawing rather than scrolling. |
| Input | Pencil drawing with finger pan by default; explicit finger-drawing mode for simulator and finger use. |
| Preservation | Keep editable ink and HTML as separate renditions within the same Lecture. Existing text notes stay available. |
| Storage | Keep library schema v1 intact. Add one versioned JSON sidecar per Lecture with native ink, PNG preview, revision, and optional HTML. No database or speculative cross-platform stroke schema. |
| Snapshot | Derive source bytes, preview, ordered images, and mutation identity from one immutable native drawing snapshot. Associate HTML with that source revision; reject stale callbacks. |
| AI access | Current delivery: ChatGPT Pro with direct return. Claude is deferred by the owner on October 24, 2026. Existing plan allowance only; no additional API charges and no manual-import fallback. |
| ChatGPT | Implement documented open-source subscription OAuth/inference, Keychain token storage, image inputs, and completed-stream-only HTML results. macOS sign-in and seven public synthetic conversions completed; iPad account sign-in remains a device acceptance check. Verify credit fallback is off, or an app credit limit is zero, before allowance-only live inference; the supported wire route itself does not force included allowance only. |
| Claude | Deferred by the owner on October 24, 2026; tracked in [issue #6](https://github.com/ProfLLM/StudyHub/issues/6). This supersedes the earlier connector/hosting approval. No Claude adapter or public connector is included in the current delivery. |
| Credentials | OS Keychain only: iPad device-only records; macOS encrypted local Keychain with calling-app ACL validation, supporting ordinary builds without developer-device registration. No plaintext credential files. macOS backup/signing tradeoffs are documented and revisable. |
| HTML | Static self-contained HTML with SVG and MathML. Sanitize markup; native WebKit additionally disables scripts, network/file subresources, navigation, and persistent site storage. |
| Validation | Agents own technical checks. Use simulator/native tests and synthetic fixtures; the owner's final review is the first physical Pencil test. Do not claim real-device or live-provider validation from simulation. |
| Delivery | Incremental PRs permitted. Straightforward PRs may be merged under repository rules and the owner's explicit merge authorization. |

See [Ink and HTML](ink-and-html.md) for behavior, limits, and checks.

The AI subscription entry records a product goal. The ChatGPT connection path is recorded above; live account behavior remains unvalidated. Claude hosting is outside the current scope.

The license uses the [standard MIT terms published by the Open Source Initiative](https://opensource.org/license/mit).

## Lecture assignments

**Status:** implementation authorized by the owner on October 24, 2026, including isolated JavaScript, blocked network access, scoped answer saving, and ChatGPT review of handwritten answers.

| Topic | Decision |
| --- | --- |
| Experience | Create an assignment from a Lecture and a learner request. ChatGPT chooses interactions to support understanding; assignments are separate from source notes and the static HTML rendition. |
| Runtime | Interactive assignments require iPadOS 16+/macOS 13+ for per-view WebKit Lockdown, which disables WebRTC socket/DNS access. Older systems refuse script execution; other app minimums are unchanged. Separate WebKit host and opaque-origin sandboxed iframe. Inline scripts are permitted only inside the assignment; network/files/navigation are blocked. No credentials, library operations or AI calls are exposed. |
| Answers | App-owned, bounded JSON persistence for form values, custom state and PNG ink. Existing data survives failures. Creation adds an assignment rather than replacing earlier attempts. |
| Review | Explicit confirmation sends the assignment, saved answer snapshot, ink images and current lecture context through the existing ChatGPT connection. Feedback is static and advisory; it never overwrites answers and is marked stale after edits. |
| Storage | Upgrade the per-Lecture sidecar to v2 when adding assignments; read existing v1. Preserve library v1. Older app versions reject v2. Keep simple local atomic writes and explicit size limits. |
| Evidence | Unit/widget checks and synthetic native WebKit integration cover technical behavior. Live generated-assignment quality, handwriting assessment accuracy and physical Pencil feel remain separate acceptance checks. |

See [Lecture assignments](assignments.md) for the supported interaction contract, limits and checks.

## Class generation

**Status:** authorized by the owner on October 24, 2026: describe a learning goal and create a Class with Lectures populated with teaching material.

| Topic | Decision |
| --- | --- |
| Entry | Library/sidebar action available before any Class or Lecture exists. Reuse the learner's ChatGPT connection. |
| Content | Generate a coherent Class with complete static HTML lessons, explanations, examples, visuals and practice. Interactive assignments remain a separate Lecture action. |
| Control | Preview all lessons before saving. Only the learning request is sent; existing library content is not included. One bounded request, with no automatic per-Lecture calls. |
| Persistence | Reuse library v1 notes and existing HTML sidecars. Write new lesson files before the atomic library commit; failed saves retain the draft and attempt cleanup. No database/schema migration. |
| Evidence | Validate synthetic native creation, HTML preview, local persistence and reopening. Live educational quality remains separate from fixture tests. |

See [Class generation](class-generation.md) for limits and recovery behavior.

## Schema and persistence planning — October 24, 2026

The owner confirmed **durable local storage first**, with Mac–iPad synchronization outside the next storage implementation, and **bounded source notes/ink and answer snapshots** so the basis of new assignments and reviews remains inspectable. The [schema and persistence plan](data-persistence-plan.html) recommends SQLite with in-database binary assets, domain-specific records, referenced snapshots, and verified migration/backup. The storage engine, schema and migration are **proposals**, not approved implementation decisions. Snapshot quota and detailed cleanup policy, backup policy, the database binding, and device durability/performance gates remain to be resolved before implementation. Existing JSON formats and current product behavior remain authoritative; these planning decisions do not authorize application implementation.

## Proposed architectural defaults

These are starting points for discussion, not settled requirements:

| Proposal | Rationale |
| --- | --- |
| Rich, structured content model | Extend the prototype's versioned IDs and notes strings so future assistants can address richer study material. |
| Separate capture, domain, rendering, integration, and persistence boundaries | Keep core content portable while supporting platform capabilities. |
| HTML as an enrichment type | Support interactive explanations while preserving editable source material and structure. |
| Validated, scoped, reversible external edits | Make assistant-written content understandable and controllable by the learner. |
| Long-term local-first persistence | Extend the prototype's local JSON approach to richer content and assets as needed. |
| One Flutter app initially | Avoid creating packages before a concrete reuse need exists. |

## Open decisions

| Question | What needs to be resolved |
| --- | --- |
| Canvas interaction | Page, blocks, spatial canvas, or a hybrid; how rich material is selected and edited. |
| AI subscription access | Which supported paths allow the desired ChatGPT and Claude workflows with the learner's subscription. |
| External editing contract | Discovery, transport, authentication, capabilities, schemas, and permissions. |
| Voice input | Dictation versus recordings, transcription location, retention, and consent. |
| Future ink portability | Cross-platform editable stroke representation and optional recognition beyond this native iPad increment. |
| Interactive HTML and animation | Broader canvas permissions and packaging; active content is currently limited to isolated Lecture assignments. |
| Long-term content storage | JSON is selected for the prototype; assets, migrations, export, backup, optional encryption, and any later database remain open. |
| Network and accounts | Offline expectations, sync, accounts, and whether collaboration belongs in the product. |
| Product details | Lecture ordering, moving content, cross-Lecture links, and what a study plan contains. |
| Platform expansion | Which platforms follow macOS and what behavior must be shared. |
| Future Flutter tooling | Prototype choices are recorded above; revisit state management, routing, and dependencies only when new behavior warrants it. |
| V0 | Feature scope and acceptance criteria, to be defined in a later planning discussion. |

## Recording future decisions

For each substantial decision, record its status, the choice, why it was made, and its consequences. Link to the relevant discussion when one exists. Replace stale proposals and keep the README and architecture consistent with the agreed result.

## Navigation prototype decision

**Status:** historical initial scope, extended by the iPad ink and HTML increment above.

Use Class → Lectures → notes navigation, GUI CRUD, and simple local JSON files to make navigation playable. This explicitly supersedes the earlier Lecture → Classes terminology in the initial blueprints. The initial prototype kept its canvas a placeholder; the separately authorized increment now adds ink capture and static HTML.

The implementation keeps domain data separate from Flutter UI and file storage. Stable IDs and schema version 1 provide a modest foundation without choosing a database or expanding product scope. The macOS release build has passed with full Xcode installed; native window behavior and the Dock icon still need visual validation.
