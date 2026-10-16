# Decisions and open questions

Keep confirmed requirements separate from proposed implementation choices. Update this register when a decision is agreed upon, and update the related blueprint at the same time.

## Confirmed direction

| Topic | Decision |
| --- | --- |
| Framework | Build the app with Flutter. |
| Platforms | Cross-platform direction; begin implementation on macOS. |
| Organization | A Class contains Lectures; Lectures contain study content. Explicitly changed from the earlier hierarchy for the requested navigation prototype. |
| Capture | Typed notes and voice input are intended; ink follows later. |
| Learning | Go beyond text with a smart canvas, rich content, and animation. |
| Enrichment | Make notes easy to enrich through HTML, including future ink-based notes. |
| AI providers | Aim to work with the learner's own ChatGPT or Anthropic subscription. |
| AI editing | Let ChatGPT and Claude write and update app content at the learner's request, such as a study plan. |
| Community | Open source, AI friendly, and welcoming to everyone. |
| Merge approval | Changes to `main` require a pull request and at least one approving review from another human team member with write access. Repository administrators may merge their own pull requests without peer approval; the exception is limited to pull request merges. See [CONTRIBUTING.md](../CONTRIBUTING.md). |
| Open-source license | MIT, selected for its simple, permissive terms. See [LICENSE](../LICENSE). |
| Current scope | Navigation prototype: GUI CRUD for Classes and Lectures, a read-only notes canvas, and local JSON persistence. Broader V0 planning and GitHub issues remain separate. |
| Prototype storage | A single versioned local JSON file in application support; no database or cloud service. |
| Prototype tooling | Flutter 3.47.7 / Dart 3.13.5; macOS runner targets 12.0+. Built-in state/navigation; `path_provider` locates app storage. |
| Prototype deletion | Confirm deletion; deleting a Class also deletes its Lectures and notes. No undo in this prototype. |

The AI subscription entry records a product goal. Supported connection paths and technical feasibility remain unvalidated.

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
| Ink | Stroke representation, recognition, source preservation, and HTML enrichment links. |
| HTML and animation | Rendering technology, packaging, permitted scripts and network access, isolation, and fallbacks. |
| Long-term content storage | JSON is selected for the prototype; assets, migrations, export, backup, optional encryption, and any later database remain open. |
| Network and accounts | Offline expectations, sync, accounts, and whether collaboration belongs in the product. |
| Product details | Lecture ordering, moving content, cross-Lecture links, and what a study plan contains. |
| Platform expansion | Which platforms follow macOS and what behavior must be shared. |
| Future Flutter tooling | Prototype choices are recorded above; revisit state management, routing, and dependencies only when new behavior warrants it. |
| V0 | Feature scope and acceptance criteria, to be defined in a later planning discussion. |

## Recording future decisions

For each substantial decision, record its status, the choice, why it was made, and its consequences. Link to the relevant discussion when one exists. Replace stale proposals and keep the README and architecture consistent with the agreed result.

## Navigation prototype decision

**Status:** confirmed by the implementation request.

Use Class → Lectures → notes navigation, GUI CRUD, and simple local JSON files to make navigation playable. This explicitly supersedes the earlier Lecture → Classes terminology in the initial blueprints. Keep the notes canvas a placeholder so the prototype does not select a rich editor, capture policy, or AI integration.

The implementation keeps domain data separate from Flutter UI and file storage. Stable IDs and schema version 1 provide a modest foundation without choosing a database or expanding product scope. Native macOS build/launch validation requires full Xcode; the current development machine has only Command Line Tools.
