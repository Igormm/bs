---
name: bs-docs-shell-claims
description: Find and fix documentation (and code comments) that claim BS or its kernel is bound to bash 4 as a whole, when the truth is per-tier — the `posix` tier runs in any shell, only the `bash4` tier needs bash 4.2+. Every claim about shells, versions or tiers must match the code and a real run. Use after any change of a module's `@shell` tier, of the bash gate, of the trampoline, or before a release; also when a reader says "the docs still say the core needs bash 4".
type: prompt
whenToUse: When a core/ or bootstrap/ module changes its `@shell` tier; when `bs_shell_host_ok`, `bs::shell::ensure_version`, the trampoline or `bs call` change; before releasing; when documentation talks about "bash 4", "bash 4.2+", "requires bash", "bash only" or lists shells
arguments:
  - scope
---

# Утверждения об оболочках в документации / Shell claims in documentation

## Цель / Goal

**Главный факт нельзя прятать: BS требует bash 4.2+.** На bash написаны вся библиотека
`lib/` (87 модулей, ни один не POSIX) и 2 из 19 файлов ядра `core/`. Исключение — 17 небольших
файлов ядра `@shell posix` и пролог точек входа: они работают в любой оболочке. Любой текст,
который говорит о требованиях BS, **сначала называет bash 4.2+**, и только потом — исключения.
Оговорка про ярусы не должна заслонять требование: читатель, увидевший «ядро делится на ярусы»,
не должен прийти к выводу, что bash ему не нужен.

Две ошибки одного класса, обе недопустимы:
1. **Преуменьшение** — «ядро работает в любой оболочке», «bash нужен только ярусу bash4», «для
   Bash» без версии, требование bash 4.2+ отсутствует в первом абзаце или в «Требованиях».
2. **Преувеличение** — «BS работает только в bash», «ядро привязано к bash 4» без слов о том, что
   17 файлов ядра и пролог от bash не зависят и что `bs`/`install.sh` запускаются из любой оболочки.

**The main fact must not be hidden: BS requires bash 4.2+.** All of the `lib/` library (86
modules, none of them POSIX) and 2 of the 19 `core/` files are written in bash. The exception is 17
small `@shell posix` kernel files and the entry-point prologue: they run in any shell. Any text
that speaks about BS requirements **names bash 4.2+ first** and only then the exceptions. The
remark about tiers must not outshine the requirement.

Two mistakes of one class, both unacceptable: **understating** ("the kernel works in any shell",
"bash is needed only by the bash4 tier", "for Bash" with no version, no bash 4.2+ in the first
paragraph or in "Requirements") and **overstating** ("BS works only in bash", "the kernel is bound
to bash 4" with no word that 17 kernel files and the prologue do not depend on it).

## Что считается правдой / What counts as true

Источник правды — код и реальный запуск, не память и не старый текст.
The source of truth is the code and a real run — not memory, not old text.

| Вопрос / Question | Откуда ответ / Where the answer comes from |
|---|---|
| Какого уровня файл / which tier a file is | строка `# @shell posix\|bash4` в начале файла; `bash .agents/skills/bs-shell-portability/scripts/tier_scan.sh --list` |
| Файл парсится в оболочке X / a file parses in shell X | `X -n файл`, для всех установленных оболочек |
| Возможность есть в оболочке X / a feature exists in shell X | `bash .agents/skills/bs-shell-portability/scripts/probe_shells.sh` |
| Что запускалось на деле / what was really run | тесты `tests/unit/test*portable*unit.sh`, `testcallbridgeunit.sh`; таблица приоритетов в `shell-portability.md` |
| Кто проверяет версию bash / who checks the bash version | `bootstrap/shell.sh` (`bs_shell_host_ok`), `bootstrap/bs.sh` (`bs::shell::ensure_version`) |

Три уровня доступа (описание — `documentation/*/08-development/shell-portability.md`):
Three access levels (described in `shell-portability.md`):

1. **posix** — модули `@shell posix` работают в bash, zsh, dash, busybox ash, ksh, mksh.
2. **bash4** — остальное ядро; требует bash 4.2+ как хозяина. Другие оболочки запускают его через трамплин (`exec` в найденный bash).
3. **мост / bridge** — `bs call [--load МОДУЛЬ] ФУНКЦИЯ` вызывает функцию ядра из любой оболочки, включая fish и nushell.

## Шаги / Steps

1. **Найти подозрительные места.** Сфера — `$scope` (по умолчанию `documentation/`, `README.md`, `AGENTS.md`, комментарии в `bootstrap/` и `core/`):

   ```bash
   grep -rnIE "bash ?4|bash 4\.2|bash >= ?4|требует bash|requires bash|только bash|bash only|привяз[а-я]+ к bash|bound to bash" \
     documentation README.md AGENTS.md bootstrap core install.sh boot.sh
   ```

2. **Классифицировать каждое найденное утверждение** — на одно из четырёх:

   | Класс | Пример | Действие |
   |---|---|---|
   | **Верно и названо с уровнем** | «модуль `@shell bash4` требует bash 4.2+» | оставить |
   | **Верно, но без уровня** | «гейт bash 4.2+ срабатывает до загрузки чего-либо» | дописать уровень: «для яруса `bash4`; `posix`-модули и мост этого не требуют» |
   | **Устарело** | «ядро — только bash», хотя `core/const.sh` уже `@shell posix` | исправить по коду |
   | **Неверно** | «в zsh работает всё ядро» без запуска | убрать или заменить фактом из таблицы приоритетов |

3. **Проверить факт перед правкой**, не после: запустить `tier_scan.sh --list` и `X -n` для файла, о котором идёт речь. Утверждение «работает в X» допустимо только если оболочка есть в таблице «Что проверено» или запуск сделан сейчас.

4. **Править в паре языков сразу** (`documentation/en/` и `documentation/ru/`, см. навык `bs-docs-sync`): та же структура, те же примеры, меняется только язык. Если меняется формулировка про гейт или ярусы — править и комментарии в коде (двуязычные пары).

5. **Не переименовывать.** Не менять имена функций, переменных и файлов ради «красоты» формулировки; имена подчиняются `code-style-guide.md` (§2.1). Исправляется только текст утверждения.

6. **Не обещать больше, чем проверено.** Оболочка без настоящего запуска (nushell, oksh, osh, пока не установлены) пишется как «не проверялась», а не «поддерживается».

7. **Проверить документацию:**

   ```bash
   bash tests/validatedocscode.sh
   for l in ru en; do grep -c '^## ' documentation/$l/08-development/shell-portability.md; done   # числа совпадают
   ```

## Формулы / Wordings

Использовать / Use:

- «BS требует bash 4.2+: на нём написаны вся `lib/` и 2 из 19 файлов ядра. 17 файлов ядра (`@shell posix`) и пролог точек входа от bash не зависят; `bs` и `install.sh` можно запускать из любой оболочки.» — формула для первого абзаца и раздела «Требования».
- «BS requires bash 4.2+: all of `lib/` and 2 of the 19 kernel files are written in it. The 17 `@shell posix` kernel files and the entry-point prologue do not depend on it; `bs` and `install.sh` can be started from any shell.» — the formula for the first paragraph and the Requirements section.
- «Гейт bash 4.2+ относится к ярусу `bash4`: так запускается ядро. Модули `@shell posix` и мост `bs call` его не требуют.»
- «The bash 4.2+ gate belongs to the `bash4` tier: that is how the kernel starts. `@shell posix` modules and the `bs call` bridge do not require it.»
- «Запуск из dash, ash, ksh, mksh, fish: трамплин находит bash 4.2+ и перезапускает точку входа.»

Не использовать / Avoid:

- «Ядро делится на ярусы…» **как первая фраза** без «требуется bash 4.2+» — это преуменьшение.
- «для Bash» / «на Bash» без версии 4.2+ в заголовочной фразе.
- «BS работает только в bash» — неверно: точки входа запускаются из любой оболочки, 17 файлов ядра от bash не зависят.
- «Ядро работает в zsh» — без уточнения яруса и без запуска.
- «Поддерживаются все оболочки» — таблица говорит иначе (nushell, oksh, osh не проверялись).

## Отчёт / Report

```
## bs-docs-shell-claims: <дата>
Найдено: N утверждений
  верно с ярусом: n1 | исправлено (без яруса): n2 | устарело: n3 | неверно: n4
Файлы: <список>
Проверено: tier_scan --list, X -n (оболочки: ...), validatedocscode
Не проверялось: <оболочки, которых нет на машине>
```

Исправляй только утверждения классов «без яруса», «устарело», «неверно»; всё остальное — отчёт.
