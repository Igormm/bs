---
name: bs-docs-sync
description: Keep the bilingual documentation (documentation/en and documentation/ru) and in-code comments in sync when changing documented behavior
type: prompt
whenToUse: When the user asks to update documentation, when a change alters documented behavior or public API, or when adding features that need docs in both languages
---

The project documentation is fully bilingual: `documentation/en/` and `documentation/ru/` mirror each other (guides `01-getting-started` … `09-migration`, plus `code-style-guide.md` and `best-practices.md`). Both versions MUST be updated together — never change only one language.

## Workflow

1. Identify which docs are affected: find the English file covering the changed topic, then its Russian mirror at the same relative path under `documentation/ru/`.
2. Apply the same structural change in both files: same sections, same code examples, same command outputs — only the prose language differs.
3. Code examples inside docs must follow the code style guide (they are user-facing templates): `#!/usr/bin/env bs` + `# shellcheck shell=bash`, `load "..."`, framework abstractions.
4. If the change affects conventions listed in `AGENTS.md` (module skeleton, testing rules, validation commands), update `AGENTS.md` too.
5. In-code comments are also bilingual ru/en in this project — keep comment pairs in sync when editing code.
6. If AI-facing prompts are affected (`ai/lib-prompt.md`, `ai/core-prompt.md`), update them as well.

## Pitfalls

- The en/ru files are not always byte-identical in structure — diff the section headings before editing to find the right anchor in the mirror file.
- Known drift example: the style guide §1.2 still shows manually sourcing `core/prereq.sh`, but real modules no longer do this (prereq is autoloaded first). When you find such drift, fix both languages and mention it to the user.
- Line counts of mirror files should stay close (currently ~481/484 for the style guides). A large divergence is a smell.
