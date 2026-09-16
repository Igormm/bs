# Анализ проекта BS Framework

> Обзорный технический анализ репозитория `/home/igor/bs`.
> Дата анализа: 2026-09-16. Версия фреймворка: 0.4.0.

## 1. Назначение

**BS** — модульный фреймворк и стандартная библиотека для Bash 4+:

- загрузчик модулей с разрешением зависимостей (`load "lib/io/streams"`, `# @depends`);
- ядро (`core/`): `args`, `logger`, `errorhandler`, `const`, `utils`, `version`, `config`, `deps`, `prereq`, `lang`, `guard`;
- стандартная библиотека (`lib/`): `io/*`, `system/*`, `ui/*`, `network/*`, `data/*`, `integration/*` (HTTP, LLM, Kubernetes, VK), `audit/*`, `status/*`, `frameworks/*`;
- интерпретатор `bs` — CLI-диспетчер и shebang-режим (`#!/usr/bin/env bs`);
- собственный тест-фреймворк + ShellCheck + CI-матрица дистрибутивов.

Характеристики: ноль внешних зависимостей в рантайме, единый code style
(`lower_snake_case` + пространства имён `module::`), двуязычные комментарии
(EN/RU), документация EN и RU в `documentation/`.

## 2. Масштаб

| Метрика | Значение |
|---|---|
| Файлов в репозитории (без `.git`) | ~195 |
| `.sh`-скриптов | 119 |
| Строк bash-кода | ~35 000 |
| Модулей `core/` | 11 |
| Подкаталогов `lib/` | 10 (без корневых модулей) |
| Юнит-тестов (`tests/unit/`) | 21 |
| Наборов интеграционных тестов | 3+ (vkapi, vkmusic, wireguard) |
| Others: `data`, `frameworks`, `network`, `status`, `audit`, `demos` | по 1–2 |

## 3. Архитектура

### 3.1 Двухстадийный запуск

1. **`boot.sh` (stage-1)** — без зависимостей: проверка bash ≥ 4, поиск `BS_ROOT`
   (репо → `~/.local/lib/bs` → `/usr/local/lib/bs`), `exec bs "$@"`.
2. **`bs` (stage-2)** — унифицированная точка входа: определяет `BS_ROOT`,
   `BS_HOME`, `BS_SILENT`, source `bootstrap/init.sh`, ставит EXIT-trap
   (`errorhandler::setup_trap`), диспетчеризует команды
   (`help|version|env|list|doctor|run|init-shell`) или shebang-режим.

### 3.2 Ядро

- `bootstrap/init.sh` — точка инициализации: загружает ядро по порядку,
  переменная `BS_INITIALIZED` защищает от повторной загрузки.
- `bootstrap/loader.sh` — модульный загрузчик: `load`, поиск по `BS_ROOT`,
  `# @depends`, защита от циклов и повторной загрузки.
- `core/guard.sh` — `bs::guard` (идемпотентность source), `bs::source_relative`.
- `core/lang.sh` — языковое ядро: предикаты `is::*`, строки `str::*`,
  коллекции `arr::*`/`map::*`, интроспекция `bs::*`.
- `core/utils.sh` — идиомы тишины `utils::attempt/quiet/ignore/has`, время,
  `utils::strict`.
- `core/errorhandler.sh` — `error::throw/exit`, cleanup-стек, именованные коды
  `E_*` из `core/const.sh`.
- `core/args.sh` — декларативные параметры: валидация, авто-help, `--key value`,
  bash-completion.
- `core/version.sh` — сравнение версий `bs::version::compare`.
- `core/deps.sh` — проверка зависимостей модулей (`deps::check_module`).
- `core/prereq.sh`, `core/config.sh` — внешние утилиты и конфигурация.

### 3.3 Библиотека

`lib/` включает: `io` (streams/files/process), `ui`, `network`, `data`,
`system/*` (~20+ модулей: дистрибутивы, пакеты, пользователи, сервисы, сеть,
устройства, hw), `integration` (result/JSON-контракт, http, llm, k8s, vkapi,
vkmusic, wireguard), `audit`, `status`, `frameworks`, `automation.sh`.

### 3.4 Интеграции

`lib/integration/result` — JSON-контракт для Go-backend/CI. HTTP-клиент,
LLM (OpenAI/Ollama), Kubernetes — проверка зависимостей через `core/deps`
(например, k8s требует `kubectl` — в `bs doctor` помечается `[OPTIONAL]`).

## 4. Установщик (`install.sh` + `install/`)

Модульный установщик из 4 файлов:

| Файл | Роль |
|---|---|
| `install/main.sh` | разбор аргументов, режимы (`system`/`local`), пути, диспетчер |
| `install/actions.sh` | `do_install` / `do_uninstall` |
| `install/checks.sh` | `is_already_installed`, `check_shell_environment` |
| `install/path_manager.sh` | PATH-хелперы, `auto_update_path` |

Принципы:

- **копирование**, а не симлинки: после установки репозиторий можно удалить;
- обёртка `bin/bs` экспортирует `BS_ROOT` и `exec`s целевой `bs`;
- переопределение путей через `PREFIX`, `BIN_DIR`, `LIB_DIR`;
- system-режим требует root; `--local` пишет в `~/.local` (без sudo);
- после локальной установки автоматически обновляется PATH (`.bashrc`/`.zshrc`).

Замечания по установщику (см. также §7):

- в `install.sh` дублируются проверки `bootstrap/init.sh` (строки 55–58 и
  101–104) и ядра (`core/*` проверяется дважды);
- **найден и исправлен в ходе этого анализа**: `install.sh` вызывал
  `utils::ensure_shell_version`, который проверяет переменную окружения
  `$SHELL` (логин-шелл), а не реально запущенный интерпретатор. При
  `SHELL=zsh` установка падала с «Zsh version 4 or higher is required…»,
  хотя выполнялась под bash. Исправлено: проверка переведена на уже
  существующую `check_shell_environment` из `install/checks.sh`, которая
  определяет интерпретатор по `/proc/$$/exe` (документация EN/RU
  синхронизирована). Покрыто тестом (system-режим без root);
- `auto_update_path` пишет в rc-файлы **без подтверждения**, при том что
  `update_path_bashrc` спрашивает (рассинхрон поведения);
- `uninstall` не убирает добавленную строку PATH из `.bashrc`/`.zshrc`;
- копируются только `bootstrap/ core/ lib/ bs` — `examples/` и `install/`
  в целевой каталог не попадают (осознанно, но стоит зафиксировать в доке).

## 5. Тестирование

Собственный тест-фреймворк (`tests/testframework.sh`):

- `testframework::assert_true/false/equal/file_exists/command`, секции,
  сводка со счётчиками;
- `tests/runalltests.sh` — автообнаружение по каталогам
  (`unit`, `integration`, `data`, `frameworks`, `network`, `status`, `audit`,
  `demos`), пропуск root/деструктивных тестов без `--with-root`;
- `tests/validatesyntax.sh` — `bash -n` по всем скриптам;
- `tests/validateshellcheck.sh` — ShellCheck, уровень `error` обязателен
  (локально пропускается, если shellcheck не установлен).

Покрытие на момент анализа: core (const, errorhandler, version, logger, loader,
utils, lang, args, deps, prereq, process, files, streams, http, result, ps1,
schedule, hw, k8s, llm, platformcheck) — юнит; vkapi/vkmusic/sshnetwork/… —
интеграционные на моках. **Установщик тестами не покрывался** — покрытие
добавлено файлом `tests/integration/testinstall.sh` (см. §9.1).

Тест-скрипты выполняются как `bash <script>`, шебанг `#!/usr/bin/env bs`
используется для консистентности и ShellCheck `-s bash`.

## 6. CI (GitHub Actions)

Два job (`.github/workflows/ci.yml`):

1. **lint** — `validatesyntax.sh` + `validateshellcheck.sh` (ubuntu);
2. **tests** — матрица контейнеров: `ubuntu:latest`, `debian:stable`
   (bash 5.x), `almalinux:9` (bash 5.1), `almalinux:8` (bash 4.4 — минимальная
   поддерживаемая версия). Запускается `runalltests.sh` без `--with-root`.

## 7. Проблемы и риски

1. **Установщик без тестов** (до этого изменения) — критичный путь, ошибки
   тихой установки/удаления сложно ловить вручную.
2. **`install.sh` проверял `$SHELL`, а не реальный интерпретатор** —
   `utils::ensure_shell_version` смотрит в переменную окружения `$SHELL`
   (логин-шелл): при `SHELL=zsh` установка из-под bash падала
   («Zsh version 4 or higher is required…»). Исправлено переходом на
   `check_shell_environment` (по `/proc/$$/exe`).
3. **Дублирование проверок** в `install.sh` (см. §4).
4. **`auto_update_path` без подтверждения** — неожиданная модификация
   пользовательских rc-файлов; потенциальная жалоба пользователей.
5. **Рассинхрон `bs doctor`** с фактическим составом `core/`: список
   обязательных файлов захардкожен в `doctor_cmd` (новые модули, например
   `core/guard.sh`, не проверяются).
6. **Рост CLI в одном файле** `bs` (218 строк): команды `doctor`, `list`, `run`
   уже тянут к выносу в подсистему команд (`core/cli`), иначе диспетчер будет
   расти вместе с фреймворком.
7. **`deps::check_module`** для `lib/integration/k8s` возвращает
   OPTIONAL-статус при отсутствии `kubectl` — семантика «зависимость не
   обязательна для доктора», но пользователь может ожидать FAILED.
8. **Примеры** не проверяются `validatesyntax.sh` (закомментировано в
   скрипте: «проверяются отдельно, фаза 6 плана чистки») — пробел, если фаза
   ещё не выполнена.
9. **Несогласованность каталогов тестов**: `get_current_shell_name` и
   `check_shell_environment` в `install/checks.sh` не покрыты тестами (нет
   юнит-тестов для `install/`).

## 8. Сильные стороны

- Ноль внешних рантайм-зависимостей; строгий единый стиль (guard'ы,
  `is::*`-предикаты, идиомы тишины).
- Двухстадийный boot + shebang-режим + `bs run`: скрипты без boilerplate.
- Модульный установщик с тремя режимами и переопределением путей — удобен
  для CI и изолированных окружений.
- Тест-фреймворк с автообнаружением и явным пропуском деструктивных тестов.
- CI-матрица на минимальной версии bash (4.4, almalinux:8).
- Документация EN/RU, стиль-гайд, AGENTS.md для агентной разработки,
  skills в `.agents/skills/` (kimi/agents-совместимые промпты и воркфлоу).

## 9. Рекомендации (по приоритету)

1. **Добавить тесты установщика** — сделано: `tests/integration/testinstall.sh`
   (установка/повторная установка/удаление в изолированном `HOME` и temp-пути,
   проверка обёртки, правильности `BS_ROOT`, PATH-хелперов, отказа system-режима
   без root).
2. **Покрыть `install/checks.sh`** юнит-тестами (`get_current_shell_name`,
   `check_shell_environment`, `is_already_installed`).
3. **Убрать дублирование** проверок в `install.sh`; вынести список
   обязательных файлов в одну функцию.
4. **Решить вопрос `auto_update_path`**: либо подтверждение, либо явный флаг
   `--yes`, либо документировать поведение.
5. **Синхронизировать `bs doctor`** с фактическим составом ядра (например,
   сканировать `core/*.sh` и сообщать об отсутствующих).
6. **Вынести CLI-команды** из `bs` в модуль (например, `core/cli.sh`),
   оставив диспетчер тонким.
7. Включить проверку `examples/` в `validatesyntax.sh` (или удалить
   закомментированную фазу).

## 10. Заключение

Зрелый, хорошо спроектированный bash-фреймворк с продуманной архитектурой
(ядро/библиотека/интеграции), CI и документацией. Основные точки роста —
покрытие установщика (уже добавлено), консолидация `bs doctor` и CLI,
устранение дублирования в `install.sh`.