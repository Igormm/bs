---
name: bs-check-artifacts
description: Check the repo for traces of unfinished AI generation (placeholders, style violations, template boilerplate) and for leakage of the user's request text into code/docs — verbatim request phrases must never appear in documentation or comments
type: prompt
whenToUse: Before committing generated code, after running parallel agents, when reviewing new/changed files, or when the user asks to check for AI artifacts or prompt leakage
arguments:
  - scope
---

Check `${scope}` (default: whole repo, excluding `.git/`, `.art/`, `review/`) for two classes of problems. Report ONLY what you find with `file:line`. Do not fix anything unless asked.

# Part 1 — Traces of unfinished AI generation

## 1.1 Placeholder / stub text (code and comments)

Search for these exact patterns (case-insensitive), inspect each hit:

```
your code here | your code goes | insert your | lorem ipsum | asdf | qwerty
foobar | placeholder | stub | dummy | fake data | sample usage
TODO: write | TODO: implement | FIXME | XXX | WIP | under construction
заглушк | в разработке | доделать | дописать | пример заглушки
```

Legitimate exceptions: `TODO_TASK_*` variable names, `log::warn "...not implemented for <platform>"` in platform branches, explicit `# SKIP:` test markers, dry-run "stub response" in mocked code, `str::format` placeholder tests. Anything else is a finding.

## 1.2 LLM template boilerplate (conversational filler that must not survive in code)

```
here is | here's | i hope | as an ai | as an llm | let's | of course | certainly
in conclusion | it's important to note | this code | the code below | feel free
happy to | by the way | i will | i've | we use | we need | we want | our framework
```

In prose docs `note that` / `key points` are acceptable; in code comments they are findings.

## 1.3 Style violations that betray bulk generation

- 4-space indentation in `lib/` or `core/` (project style is 2 spaces). Command:
  `rg -l "^    [a-z_]+\(\)" lib core --glob '*.sh'`
- Header not matching the module convention: missing `# lib/group/module.sh — one-line description` bilingual line pair, missing `@depends`, missing `@tier` (lib modules), `@author` / `@since` / `@version` boilerplate in the header.
- `@description` without a Russian pair (project convention: en + ru).
  Command: `rg -n "@description [A-Za-z]" lib --glob '*.sh' | rg -v " [А-Яа-яЁё]"`
- `echo`/`printf` to stdout in library functions instead of `streams::*` (§7); raw `2>/dev/null` instead of `utils::quiet_err` (§6).
- Calls to functions that do not exist in the loaded modules (generated code referencing imagined APIs): resolve every `module::func` call against the actual module definitions before trusting it.
- Stray files: `*.bak`, `*.tmp`, `*.orig`, `*.swp`, `~`, `.log`, `.txt` in tracked files.
  Command: `git ls-files | rg -i "\.(bak|tmp|old|orig|swp)$|~$|\.(txt|log)$"`

## 1.4 Encoding artifacts

- BOM, CRLF, UTF-16, zero-width chars (U+200B/U+200C/U+200D/U+FEFF/U+00AD), trailing whitespace on committed lines.
  Commands:
  `rg -l -U $'\r' --glob '*.sh' --glob '*.md'`
  `rg -n "[\x{200B}\x{200C}\x{200D}\x{FEFF}\x{00AD}]" --glob '*.sh' --glob '*.md'`

# Part 2 — Request-text leakage (the main task)

The goal: a user's request or a prompt passed to a coder must NOT end up in the repo in verbatim or near-verbatim form. Documentation and comments must describe WHAT the code does, not repeat WHAT WAS ASKED.

## 2.1 Collect the source text

Gather the request/prompt texts that produced the code under review (the user's message, the task description given to agents, example sentences in the prompt).

## 2.2 Extract distinctive phrases

From each request, extract:
- multi-word fragments of 3+ words that are not generic ("create a module", "write a script" are generic; "модуль интеграции фреймворков для BS" is distinctive),
- distinctive nouns/sample data from the request (e.g. example values, task names, URLs, product names),
- any sentence that reads like a task description rather than a fact.

## 2.3 Search for them in the repo

```
rg -n -i "<phrase1>|<phrase2>|..." --glob '!ai/**' --glob '!.agents/**' --glob '!review/**' --glob '!.art/**'
```

- `ai/*.md` and `.agents/skills/*/SKILL.md` are EXEMPT (they are prompts by design).
- Check not only verbatim matches but near-verbatim: same words with changed order, minor rewording, translation of the phrase (e.g. a Russian request phrase translated verbatim into English docs).

## 2.4 Prompt-style text in documentation (symptom of leakage)

Documentation lines that read like an instruction addressed to a coder/AI rather than a user-facing description:

```
Create a | Implement a | Add a | Write a | Make the | Should return | Must accept
The user wants | as requested | as per request | per your request | First, | Next, | Now, let's
This module will | This function will | We'll | I'll | Let me | Let's
```

A finding when the sentence structure is imperative/addressed-to-AI AND the text describes intent rather than behavior. E.g.:
- LEAK: "Create a function that returns the sum." (imperative, intent)
- OK: "`sum` returns the sum of two integers." (declarative, behavior)
- LEAK: "This module will handle tasks and should save them." ("will/should" intent speech)
- OK: "Saves tasks to `~/.tasks.tsv` on change."

Also check: comments that copy the request sentence verbatim instead of describing the code at that location.

## 2.5 Sample-data check

Sample data in docs/tests MUST NOT be the literal values from the user's request when those are task-specific (real server names, real paths from the request, personal data). Neutral examples ("example.com", "task1", "item_1") are fine.

# Output format

```
## bs-check-artifacts: <scope>

## Part 1: Generation traces
- <file>:<line> — <pattern> — <why it's a finding>
...

## Part 2: Request leakage
- <file>:<line> — <quoted text> — <which request phrase it mirrors>
...

## Verified clean
- <area> — checked, no findings (e.g. "docs en/ru sync", "no encoding artifacts")
```

Every finding MUST have file:line and a one-line reason. If the request text is not available (checking third-party code), say so instead of guessing.