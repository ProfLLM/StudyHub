# Agent instructions

This is the canonical repository guidance for all coding agents, including Codex and Claude. `CLAUDE.md` points here so that instructions stay consistent.

## Understand the project

Read [README.md](README.md), [the product vision](docs/product-vision.md), [the architecture](docs/architecture.md), and [the decision register](docs/decisions.md) before making substantial changes. Read [CONTRIBUTING.md](CONTRIBUTING.md) when preparing a contribution.

StudyHub is a Flutter study app with macOS navigation, an iPad ink workspace, and local JSON persistence. The ink/HTML increment and provider limitations are documented in docs/ink-and-html.md. See README.md for the toolchain and checks.

## Preserve the product intent

- Preserve the hierarchy **Class → Lectures → study content**. A Class contains Lectures (changed explicitly for the navigation prototype). Do not silently rename, reverse, or add levels to this hierarchy.
- iPad ink and a separate static HTML rendition are explicitly authorized. Typed editing and voice input remain intended future capture methods. Do not infer further commitments from the long-term vision.
- Treat the learning canvas as a core experience. Text, visuals, HTML enrichment, interactive content, and animation should be able to coexist.
- Plan for interoperability with ChatGPT and Claude, including user-requested content edits and study plans.
- The intent is to use the learner's own ChatGPT or Anthropic subscription. Confirm supported access paths before selecting an integration. Do not silently substitute a developer-funded service or assume that a subscription provides API credentials.
- Keep the project welcoming to human and AI-assisted contributions.

## Work within the requested scope

- Distinguish confirmed requirements, proposed designs, and open questions. Record meaningful changes in the relevant blueprint and decision register.
- During blueprint work, do not generate application code, add dependencies, choose unresolved product policies, or turn the vision into a V0 plan unless requested.
- Create GitHub issues, publish changes, or make external updates only when authorized by the task.
- Changes to `main` require a pull request and approval from another human team member with write access. Repository administrators may merge their own pull requests without peer approval. Agents must not merge or use the administrator exception unless the user explicitly asks; see [CONTRIBUTING.md](CONTRIBUTING.md).
- Make focused, reviewable changes. Preserve unrelated work and avoid speculative abstractions.
- Update documentation when behavior, architecture, terminology, or setup changes.
- Keep these instructions in `AGENTS.md`; keep `CLAUDE.md` as a pointer rather than a second copy.

## Architecture guidance for future implementation

The architecture document describes proposed boundaries; it does not mandate a framework, package, storage engine, or integration protocol.

- Keep domain content independent of Flutter widgets and macOS APIs. Platform-specific functionality belongs behind explicit interfaces.
- Prefer structured, versioned content with stable identities so that the app and external assistants can operate on the same model.
- Keep captured source material usable when an enrichment or AI integration is unavailable.
- Route AI edits through the app's validated editing boundary. Design for scoped permission, conflict handling, and undo; do not let integrations bypass normal content rules.
- Treat imported or generated HTML and animation content as untrusted. Specify its execution permissions and isolation before enabling active content.
- Preserve accessibility and reduced-motion behavior when adding rich learning experiences.
- Keep credentials and private study material out of source control, logs, fixtures, and examples. External transmission of learner content should be explicit and limited to the requested task.

## Verification

Use checks appropriate to the change and report what actually ran.

For documentation changes, check internal links, terminology, consistency, and whether examples accurately reflect the repository. Do not invent build or test results; distinguish Flutter widget tests from native macOS validation.

After Flutter code exists, follow its documented toolchain and commands. Format changed Dart files, run static analysis, and run relevant tests for behavior changes. Add meaningful coverage for new behavior; avoid tests that merely repeat implementation details. Validate macOS-specific behavior on macOS and keep shared logic testable independently.

When a check cannot run, explain the limitation plainly. Do not claim unsupported platforms, integrations, or capabilities have been verified.

## Handoff

Summarize what changed, why, what was checked, and any unresolved decisions that affect the work. Use plain language and point to the relevant files.
