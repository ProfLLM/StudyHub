# StudyHub

StudyHub is a study app being designed with Flutter for multiple platforms, starting with macOS. The goal is to help people understand what they are learning through notes, visuals, interaction, and animation.

The project is open source under the MIT license, friendly to AI tools, and welcoming to contributions from everyone.

**Status:** blueprint stage. This repository currently contains product direction, a proposed architecture, and contributor guidance. There is no application to run yet. V0 scope and GitHub issues will be defined separately.

## How learning is organized

```text
Lecture
└── Classes
    └── Study content
```

A **Lecture** is the parent container. It contains **Classes**, where learners capture and explore study content. This is the project's chosen hierarchy; do not reverse the terms based on other academic conventions.

## Product direction

- **Capture naturally.** Support typed notes and voice input, with ink input later.
- **Learn beyond text.** Build a smart canvas for visual explanations, interactive material, and animations that help people understand concepts.
- **Enrich existing notes.** Make text and, eventually, ink easy to enrich with HTML-based learning content.
- **Work with the learner's AI.** Aim to use the learner's own ChatGPT or Anthropic subscription through supported integration paths. The connection mechanism still needs investigation.
- **Let AI contribute directly.** Enable ChatGPT and Claude to create or update study content when the learner asks—for example, writing a study plan into a Class.
- **Stay portable.** Use Flutter and keep core content independent of platform-specific input and rendering details.

These describe the long-term direction, not an agreed V0 feature list. Subscription access, HTML execution, and external editing contracts are design questions, not implemented capabilities.

## Repository blueprint

| Document | Purpose |
| --- | --- |
| [Product vision](docs/product-vision.md) | Learning experience, terminology, and product requirements. |
| [Architecture](docs/architecture.md) | Proposed content model, canvas, AI editing boundaries, and Flutter structure. |
| [Decisions and questions](docs/decisions.md) | Confirmed choices, proposals, and unresolved decisions. |
| [Contributing](CONTRIBUTING.md) | How humans and AI-assisted contributors can participate. |
| [AGENTS.md](AGENTS.md) | Shared instructions for coding agents working in this repository. |
| [CLAUDE.md](CLAUDE.md) | Entry point directing Claude to the shared agent instructions. |

## Development

No Flutter project, dependencies, or platform runners have been generated yet. Once implementation begins, this section should document the actual toolchain, setup commands, and checks used by the repository.

For now, start with the product vision and architecture, and keep confirmed requirements distinct from proposed implementation choices.

## Contributions and licensing

Contributions are welcome from people of all backgrounds and experience levels, including contributors using AI tools. See [CONTRIBUTING.md](CONTRIBUTING.md).

StudyHub is licensed under the [MIT License](LICENSE).
