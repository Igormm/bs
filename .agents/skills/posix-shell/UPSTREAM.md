# Upstream / Источник

- Source / Источник: https://github.com/f-steff/POSIX_Shell_Skill —
  `skills/posix-shell/`
- License / Лицензия: MIT, Copyright (c) 2026 f-steff <fsteff@gmail.com>
- Imported verbatim on 2026-10-22; not modified.
  Импортировано без изменений 2026-10-22.

## Notes for BS / Заметки для BS

- This is the closest external skill to the BS `@shell posix` tier: real
  `/bin/sh`, no arrays, no `[[ ]]`, no `local`, cross-shell Docker testing.
  Это ближайший внешний навык к tier `@shell posix`: настоящий `/bin/sh`, без
  массивов, `[[ ]]` и `local`, с кросс-оболочечным Docker-тестированием.
- BS rules win / правила BS главнее: `core/` uses the `bs_` namespace and the
  data layer (`core/data.sh`) instead of shell arrays; strict mode only in entry
  points; use `bs_guard`/`bs::guard` and `bs_source_relative` instead of
  hand-rolled guards/sourcing.
- Upstream requires ASCII-only comments; BS keeps bilingual Russian/English
  comments in `core/`, so do not apply that rule to BS files.
  В upstream комментарии только ASCII; в BS у `core/` двуязычные комментарии,
  поэтому это правило к файлам BS не применяется.
- Useful scripts: `scripts/docker_test.sh`, `scripts/docker_test_cross.sh`,
  `scripts/test_runner.sh`. They are standalone helpers; BS already has
  `scripts/probe_shells.sh` and `scripts/check_posix_tier.sh`, so prefer the BS
  scripts inside the repo.
  Полезные скрипты — `docker_test*.sh` и `test_runner.sh`; внутри репозитория
  предпочитайте уже существующие `scripts/probe_shells.sh` и
  `scripts/check_posix_tier.sh`.
