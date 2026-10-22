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
| Current scope | GUI CRUD and local JSON persistence, plus the authorized iPad ink and separate HTML increment below. Broader V0 planning remains separate. |
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
| AI access | Both ChatGPT Pro and Claude Pro are requested with direct return. Existing plan allowance only; no additional API charges and no manual-import fallback. |
| ChatGPT | Implement documented open-source subscription OAuth/inference, Keychain token storage, image inputs, and completed-stream-only HTML results. Live account verification remains required. |
| Claude | Direct mobile return using the documented connector route requires a public HTTPS service. No service is approved/deployed yet; preserve this as a capability/access blocker, not a fake provider. |
| HTML | Static self-contained HTML with SVG and MathML. Sanitize markup; native WebKit additionally disables scripts, network/file subresources, navigation, and persistent site storage. |
| Validation | Agents own technical checks. Use simulator/native tests and synthetic fixtures; the owner's final review is the first physical Pencil test. Do not claim real-device or live-provider validation from simulation. |
| Delivery | Incremental PRs permitted. Straightforward PRs may be merged under repository rules and the owner's explicit merge authorization. |

See [Ink and HTML](ink-and-html.md) for behavior, limits, and checks.

The AI subscription entry records a product goal. Documented connection paths are recorded above; live account behavior and Claude hosting remain unvalidated.

The license uses the [standard MIT terms published by the Open Source Initiative](https://opensource.org/license/mit).

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
| Interactive HTML and animation | Any future active-content permissions and packaging; this increment uses isolated static WebKit rendering. |
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
