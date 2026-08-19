---
name: bs-commit-style
description: Create git commits for the BS framework following its Conventional Commits style, scopes, and history-safety rules
type: prompt
whenToUse: When the user asks to commit changes, write a commit message, or prepare a commit for the project
---

Create a commit following this repository's conventions. IMPORTANT: never run `git commit`/`git push` without the user's explicit request — this skill only applies once they asked.

## Message format

Conventional Commits with optional scope, short message, Russian or English (both are used in this repo):

```
type(scope): short description
```

Seen types: `feat`, `fix`, `refactor`, `style`, `test`, `docs`, `chore`, `cleanup`.
Seen scopes: `bootstrap`, `core`, `lib/io`, `ai`, `docs`, `gitignore`, `prereq` — use the module/area actually changed.

Examples from real history:
- `feat(bootstrap): core/prereq теперь в автозагрузке первым делом`
- `test(prereq): тестируем guard, а не надеемся на удачу`
- `chore: tell ShellCheck that bs is bash with extra steps`

## Rules

- Keep commits small and focused (AGENTS.md: "prefer small, focused commits").
- Humor in messages exists in history but AGENTS.md says: add a joke only if the user asks.
- NEVER mutate git history: no `git rebase`, `git reset`, `git push --force` unless the user explicitly asks.
- Before committing, run the validation cycle (`bs-validate` skill): `bash tests/validatesyntax.sh && bash tests/validateshellcheck.sh && bash tests/runalltests.sh`. Do not commit on a red run.
- Review `git status` and `git diff --staged` before committing; stage only files belonging to this change — do not sweep up unrelated modifications.
