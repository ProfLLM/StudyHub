# Decisions and open questions

Keep confirmed requirements separate from proposed implementation choices. Update this register when a decision is agreed upon, and update the related blueprint at the same time.

## Confirmed direction

| Topic | Decision |
| --- | --- |
| Framework | Build the app with Flutter. |
| Platforms | Cross-platform direction; begin implementation on macOS. |
| Organization | A Lecture contains Classes; Classes contain study content. |
| Capture | Typed notes and voice input are intended; ink follows later. |
| Learning | Go beyond text with a smart canvas, rich content, and animation. |
| Enrichment | Make notes easy to enrich through HTML, including future ink-based notes. |
| AI providers | Aim to work with the learner's own ChatGPT or Anthropic subscription. |
| AI editing | Let ChatGPT and Claude write and update app content at the learner's request, such as a study plan. |
| Community | Open source, AI friendly, and welcoming to everyone. |
| Merge approval | Changes to `main` require a pull request and at least one approving review from another human team member with write access. Repository administrators may merge their own pull requests without peer approval; the exception is limited to pull request merges. See [CONTRIBUTING.md](../CONTRIBUTING.md). |
| Open-source license | MIT, selected for its simple, permissive terms. See [LICENSE](../LICENSE). |
| Current scope | Documentation and repository blueprints only. V0 planning and GitHub issues come later. |

The AI subscription entry records a product goal. Supported connection paths and technical feasibility remain unvalidated.

The license uses the [standard MIT terms published by the Open Source Initiative](https://opensource.org/license/mit).

## Proposed architectural defaults

These are starting points for discussion, not settled requirements:

| Proposal | Rationale |
| --- | --- |
| Shared, versioned content model with stable identifiers | Allow the app and external assistants to address the same study material. |
| Separate capture, domain, rendering, integration, and persistence boundaries | Keep core content portable while supporting platform capabilities. |
| HTML as an enrichment type | Support interactive explanations while preserving editable source material and structure. |
| Validated, scoped, reversible external edits | Make assistant-written content understandable and controllable by the learner. |
| Local-first persistence | Keep study material useful without an active AI connection. |
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
| Content storage | Database or file format, assets, migrations, export, backup, and optional encryption. |
| Network and accounts | Offline expectations, sync, accounts, and whether collaboration belongs in the product. |
| Product details | Class ordering, moving content, cross-Class links, and what a study plan contains. |
| Platform expansion | Which platforms follow macOS and what behavior must be shared. |
| Flutter tooling | SDK constraints, supported macOS versions, state management, routing, and dependency choices. |
| V0 | Feature scope and acceptance criteria, to be defined in a later planning discussion. |

## Recording future decisions

For each substantial decision, record its status, the choice, why it was made, and its consequences. Link to the relevant discussion when one exists. Replace stale proposals and keep the README and architecture consistent with the agreed result.
