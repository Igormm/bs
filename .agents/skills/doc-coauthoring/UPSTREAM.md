# Upstream / Источник

- Source / Источник: https://github.com/anthropics/skills — `skills/doc-coauthoring/SKILL.md`
- License / Лицензия: the repository README says "many skills in this repo are open source (Apache 2.0)";
  the skill directory carries no LICENSE file of its own — check upstream before redistributing.
  README репозитория: «многие навыки — open source (Apache 2.0)»; в каталоге навыка своего
  LICENSE нет — перед распространением сверьтесь с upstream.
- Imported verbatim on 2026-10-13; not modified / Импортировано без изменений 2026-10-13.

## Notes for BS / Заметки для BS

- Use it for `documentation/en` + `documentation/ru`: write the English page, then the Russian one, and finish with `bs-docs-sync` and `bs-check-docs-code`.
  Для `documentation/en` + `ru`: сначала английская страница, затем русская; в конце `bs-docs-sync` и `bs-check-docs-code`.
- Its "Reader Testing" stage uses a sub-agent; in BS only on the user's request.
  Стадия «Reader Testing» использует субагента; в BS — только по просьбе пользователя.
