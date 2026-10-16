# Product vision

## Purpose

Help people understand and retain what they study. Capturing notes is an entry point; the broader goal is to turn study material into explanations and experiences that make concepts easier to grasp.

Text alone is often an insufficient representation for learning. StudyHub should make room for diagrams, interactive demonstrations, animation, and other visual explanations alongside written notes.

## Organization and terminology

```text
Class
├── Lecture
│   └── Study content
└── Lecture
    └── Study content
```

- **Class:** the parent container for a set of Lectures.
- **Lecture:** a child of a Class and the place where related study content lives.
- **Study content:** the learner's notes and learning material within a Lecture.
- **Learning canvas:** the experience used to view, arrange, edit, and interact with that content. Its exact layout is undecided.
- **Enrichment:** additional learning material connected to existing content, such as an HTML explanation, a diagram, or an animation.

The navigation prototype explicitly changes the earlier Lecture → Classes hierarchy to Class → Lectures, as requested by the project owner. Details such as reordering, moving Lectures, and linking content across Lectures remain open design questions.

## Capture and enrichment

The intended capture methods are typing and voice input, with ink added later. Captured content should become useful study material without requiring people to re-enter it for every representation.

Text and ink should be easy to enrich through HTML. For example, a learner could select a note about a physical process and ask for an interactive explanation connected to that note. The original material should remain available when the enrichment is changed or removed.

Voice capture still needs a precise definition: dictation, retained recordings, transcription, or a combination. Ink storage and recognition are also undecided. These are product questions, not implied implementation commitments.

## A smart learning canvas

The canvas should accommodate both quick capture and richer ways to understand a topic. It should support animations that ChatGPT or Claude can generate quickly, alongside HTML-based interactive content.

The term “canvas” does not yet commit the app to an infinite spatial surface, a page, a block editor, or a specific hybrid. Choose the interaction model around learning and editing needs.

Rich content should have useful fallbacks. Consider keyboard interaction, screen-reader access, reduced motion, and static explanations as part of the experience.

## AI as a collaborator

Learners should be able to work with ChatGPT or Claude using their own subscription through a supported connection. The integration mechanism has not been validated or selected.

Two complementary experiences are intended:

- **Ask from StudyHub:** use selected study content as context for an explanation or enrichment.
- **Edit from an assistant:** let ChatGPT or Claude read relevant app content and create or modify it when the learner asks.

For example, a learner might ask an assistant for a study plan on a topic. The assistant should eventually be able to write the plan into the relevant Lecture, where the learner can inspect and edit it. Copying content by hand should not be the only interaction available.

AI-created content should behave like other editable app content. Learners should be able to understand what changed, retain control over shared context, and undo unwanted edits.

## Platform and community

Use Flutter for the application. Begin with a macOS implementation while keeping the shared product model portable. The next platforms and their delivery order have not been chosen.

StudyHub is an open-source project under the [MIT License](../LICENSE) that welcomes contributions from everyone and works well with AI-assisted development. Keep repository instructions, domain concepts, and future integration contracts clear enough for both people and agents to understand.

## Navigation prototype scope

The first implementation is intentionally small: GUI creation, browsing, renaming, and deletion of Classes and their Lectures, with a read-only notes canvas per Lecture. A sidebar and breadcrumbs support navigation. The library persists locally as versioned JSON files; deleting a Class deletes its nested Lectures and notes after confirmation.

Note editing, capture, enrichment, AI integration, and synchronization are not part of this prototype. The longer-term canvas interaction and broader V0 scope remain open. See the [README](../README.md) for build and run instructions.
