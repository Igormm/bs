# Upstream / Источник

- Source / Источник: https://github.com/wshobson/agents — `plugins/shell-scripting/skills/bash-defensive-patterns/`
- License / Лицензия: MIT, Copyright (c) 2024 Seth Hobson
- Imported verbatim (SKILL.md, references/details.md) on 2026-10-13; not modified.
  Импортировано без изменений (SKILL.md, references/details.md) 2026-10-13.

## Notes for BS / Заметки для BS

- BS rules win over the generic advice here / правила BS главнее общих советов:
  strict mode only in entry points, never in `lib/` modules; use `utils::has`
  instead of `command -v`; `bs::guard`, `bs::source_relative`, module namespaces
  (`AGENTS.md`, `documentation/*/code-style-guide.md`).
- Upstream `atomic_write` in `references/details.md` declares `local -r tmpfile`
  and then assigns it — that fails in bash; declare first, assign after.
  В upstream `atomic_write` (`references/details.md`) `local -r tmpfile` объявлен
  и затем присваивается — в bash это ошибка; объявляйте, затем присваивайте.
