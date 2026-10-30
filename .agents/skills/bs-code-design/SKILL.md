---
name: bs-code-design
description: Проектировать и реализовывать код в BS — единая адаптированная цепочка дизайна (brainstorm → map → plan → TDD → verify → review → commit) поверх импортированных методических скиллов, но с жёсткими правилами фреймворка: ярусы @shell posix|bash4, неймспейсы module::func / bs_, валидационный цикл, двуязычность и честность про проверенное.
type: prompt
whenToUse: Перед любой нетривиальной фичей или рефакторингом в BS — когда нужно спроектировать, а не просто вставить пару строк; когда пользователь просит «сделай красиво», «добавь модуль», «отрефактори»; перед работой в core/ bootstrap/ install/ (ярусы) или над публичным API.
arguments:
  - task
---

# Дизайн кода в BS / Code design in BS

Собранная цепочка: **общие методики дизайна, адаптированные под BS** — не заменяет
импортированные скиллы, а накладывает на них правила фреймворка и твой контекст.

## Твой контекст (что всегда в голове при дизайне)

- BS = Bash 4.2+; ядро делится на яруса: `@shell posix` (`core/`, `bootstrap/`, `install/`) и `@shell bash4` (`lib/`, `bootstrap/bs.sh`). Ярус — единственный источник правды о зависимости от оболочки.
- Неймспейсы: `module::function` в `lib/`; `bs_module_function` + `::`-алиасы в ядре; приватные — `module::__helper`.
- Идиомы: `bs::guard`, `bs::source_relative`, `utils::*`/`bs_utils_*`, `is::*`, `bs_arr_*`/`bs_map_*` (не массивы bash), `bs_log_*`.
- Валидационный цикл обязателен: `tests/validatesyntax.sh`, `tests/validateshellcheck.sh`, `tests/runalltests.sh`, плюс для `posix` — `check_posix_tier.sh`, для версии — `version.sh check`.
- Всё двуязычно (RU первым); стиль — code-style-guide (ядро — глава 12); вывод — `bs-cli-style` (рамки, подсветка главного, без `===`).

## Цепочка дизайна / The design chain

### 1. Brainstorm — что и зачем, до кода
Задействуй `brainstorming` (уточнить намерение) и `grill-me` (прожать решение). В BS добавь вопросы:
- Какой ярус у файла? (`@shell posix|bash4` + причина). Новый файл без метки = bash4.
- Это ядро или lib? Ядро → `bs_` неймспейс, глава 12, `bs-kernel-code`.
- Публичный API или приватный? Новый публичный вызов = тест + двуязычный `@description`.
- Влияет на выводимые наружу строки? → `bs-cli-style` / `bs-cli-markdown-style`.

### 2. Map — сначала проверь, что УЖЕ есть
Задействуй `zero-hallucination-coder` (Map-фаза). Инструменты: `bs list`, `bs doctor`,
`bs lang-doc <функция>`, `scripts/inventory.sh`, `grep`/`glob`, субагент `explore`.

**Железное правило этой репозитории** (вывод из практики): *до* «сделаю новый хелпер»
проверь `core/` и `lib/` — `utils::human_size`, `utils::tempfile` (с авто-очисткой),
`utils::head_bytes`, `utils::pid_alive`, `is::command` уже существуют. Маркеры
`WRAPPER-CANDIDATE` в коде часто устарели — проверяй факт, а не комментарий.

### 3. Plan — по-шагово, с проверками
Задействуй `writing-plans`. Каждый шаг плана = файл(ы) + команда проверки. Обязательно включай:
- валидацию (syntax/shellcheck/тесты/`check_posix_tier.sh`) как отдельный шаг;
- `tests/unit/test*.sh` для нового публичного API;
- двуязычные доки (`@description`/`@global`) и, если ядро/версия — `bs-version-bump`, `bs-docs-sync`.

### 4. TDD — красный → зелёный → рефактор
Задействуй `test-driven-development` + `bs-write-test`. Конкретика:
- `testframework::assert_equal/true/false/command`; тест — `./bs run tests/unit/testX.sh`.
- Для `posix`-кода тест обязан проходить под `dash`/`zsh` (см. `testquietportableunit.sh` — эталон).
- Изолируй `HOME`/`PATH`/`BS_SYSTEM_PREFIX`, не трогай реальную установку.

### 5. Verify — докажи, потом утверждай
Задействуй `verification-before-completion` + `bs-validate`. Перед словами «готово»:
1. `bash tests/validatesyntax.sh`
2. `bash tests/validateshellcheck.sh`
3. `bash tests/runalltests.sh`
4. для `@shell posix`: `bash .agents/skills/bs-shell-abstraction/scripts/check_posix_tier.sh`
5. при смене версии/имени: `bash .agents/skills/bs-version-bump/scripts/version.sh check`

### 6. Review — скептик и безопасность
Задействуй `bs-review-module` (список сомнений), `bs-code-review-security` (P0–P3),
`requesting-code-review`/`receiving-code-review` (по серьёзности, не «performative agreement»).

### 7. Commit — атомарно и по стилю
Задействуй `bs-commit-style`/`bs-commit-pro`: Conventional Commits, плотный subject
с уточнениями через `;`, staged только нужное, без истории-переписываний. Не пушить,
пока не попросили.

## Принципы честности / Honesty principles

1. **Не строй абстракцию «наименьшего общего знаменателя».** Одинаковое на вид ≠
   одно и то же: wall-clock таймаут (GNU `timeout`), I/O-таймаут (`curl --max-time`,
   `read -t`, `/dev/tcp`) и readiness-poll (`wait_ready`, `error::retry`, `http::retry`) —
   разные сущности. `process::timeout` как «объединяющий» был отклонён именно поэтому.
2. **Проверь факт, не комментарий.** `WRAPPER-CANDIDATE`/`TODO` могут быть устаревшими.
   Сначала `grep` определения, потом говори «добавим».
3. **Минимальные, честные изменения.** Правка одного файла лучше трёх; не трогай то,
   что не относится к задаче. Если выяснил, что задача — ложный след, скажи об этом
   и закрой маркер, а не строй что-то ненужное.
4. **Не ври про проверенное.** Оболочку, которую не запускали, называй «не проверено»
   (таблица `shell-portability.md`).

## Соседние навыки / Related

- Методики: `brainstorming`, `writing-plans`, `executing-plans`, `test-driven-development`, `zero-hallucination-coder`, `systematic-debugging`, `verification-before-completion`, `using-superpowers`, `writing-skills`.
- Обзор: `requesting-code-review`, `receiving-code-review`, `named-persona-adversarial-review`, `pr-review-expert`.
- BS-специфичные: `bs-kernel-code`, `bs-new-lib-module`, `bs-new-core-module`, `bs-write-test`, `bs-validate`, `bs-scenario-audit`, `bs-review-module`, `bs-code-review-security`, `bs-cli-style`, `bs-cli-markdown-style`, `bs-variable-metadata`, `bs-shell-abstraction`, `bs-shell-portability`, `bs-version-bump`, `bs-docs-sync`, `bs-commit-style`, `bs-commit-pro`.
