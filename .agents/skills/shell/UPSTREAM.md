# Upstream / Источник

- Source / Источник: https://github.com/posidoni/shell-skill — `skills/shell/`,
  `reference/`, `examples/`, `tests/`
- License / Лицензия: MIT, Copyright (c) 2026 Mikhail Kuznetsov (@posidoni)
- Imported on 2026-10-22 / Импортировано 2026-10-22.
- Content is verbatim except for one mechanical fix: links in `SKILL.md` that
  pointed to `../../reference/` now point to `reference/`, because the skill
  lives at `.agents/skills/shell/` instead of upstream's `skills/shell/`.
  Содержимое без изменений, кроме механической правки ссылок в `SKILL.md`
  (`../../reference/` → `reference/`): навык лежит в `.agents/skills/shell/`,
  а не в upstream-каталоге `skills/shell/`.

## Notes for BS / Заметки для BS

- BS rules win over the generic advice here / правила BS главнее общих советов:
  strict mode only in entry points, never in library modules; `core/` stays
  `@shell posix`, so the Bash-only rules (`set -euo pipefail`, `[[ ]]`, arrays,
  `local`, `${var^^}`) do not apply there; use `bs::guard`,
  `bs::source_relative`, `utils::has`, `utils::quiet`, module namespaces
  (`AGENTS.md`, `documentation/*/code-style-guide.md`).
- The POSIX section is the useful part for `core/`; the “pick another tool”
  table is useful for CLI scripts, not for a runtime that must have no external
  dependencies.
  Полезная часть для `core/` — POSIX-раздел; таблица «взять другой инструмент»
  полезна для CLI-скриптов, но не для рантайма без внешних зависимостей.
- Upstream `reference/posix-sh.md` and `examples/posix-sh/` are good review
  checklists; `bs-kernel-code` and `bs-shell-abstraction` remain the authority
  for tier rules and the `bs_` namespace.
- The upstream examples use `set -eu` and `#!/bin/sh`; run them in a sandbox,
  not as BS modules. Не запускайте upstream-примеры как модули BS: это
  самостоятельные скрипты.
