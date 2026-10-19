# Руководство по стилю кода

Руководство соответствует и расширяет
[Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
применительно к фреймворку BS. Оно детализирует правила для создания
надёжного, поддерживаемого и безопасного Bash-кода, библиотек и
production-скриптов и фокусируется на аспектах, критичных для командной
разработки: модульности, тестировании, документировании и защите от ошибок.

---

## Базовые принципы

- Исполняемые файлы начинаются с `#!/usr/bin/env bs`. Библиотечные модули —
  с `#!/usr/bin/env bash`.
- Отступ — 2 пробела.
- Длина строки — 80 символов.
- Комментарии — полные предложения.
- Используйте `[[ ... ]]` вместо `[ ... ]`, `test` и `/usr/bin/[`.
  Это правило для `lib/` и кода яруса `bash4`; код ядра в пространстве `bs_` (`@shell posix`)
  следует обратному, см. [12](#12-код-в-пространстве-bs_-ядро-ярус-shell-posix).
- Заключайте переменные в кавычки: `"${var}"`, а не `$var`.
- Строгий режим (`set -euo pipefail` и безопасный `IFS`, см.
  [1.1](#11-строгий-режим)) включают точки входа, а не модули.
- В файлах модулей обязательны:
  - защита от повторного импорта Source Guard (см.
    [1.2](#12-структура-файла-модуля-и-source-guard));
  - загрузка зависимостей через `load`, а не прямой `source lib/...`.

## 1. Безопасность и надёжность

### 1.1 Строгий режим

Каждая точка входа работает в строгом режиме: прерывание при ошибке,
при использовании необъявленной переменной и при ошибке в pipeline, а также
безопасный разделитель полей:

```bash
set -euo pipefail
IFS=$'\n\t'
```

- Скрипты `#!/usr/bin/env bs` получают строгий режим от интерпретатора:
  `bs run` включает `set -euo pipefail` **до** source вашего скрипта —
  строка не нужна (см. [getting-started](../01-getting-started/README.md)).
- Обычные точки входа `#!/usr/bin/env bash` (`bs`, `boot.sh`, тестовые
  раннеры) ставят его сами — через pre-kernel `bs::strict()`
  ([bootstrap/bs.sh](../../bootstrap/bs.sh)), через `utils::strict()`
  ([core/utils.sh](../../core/utils.sh)) или сырой строкой выше:

```bash
#!/usr/bin/env bash
source /path/to/bootstrap/init.sh

utils::strict
```

Строгий режим включается только в точках входа, но не в библиотечных
модулях: модуль выполняется в shell вызывающего и не должен незаметно
менять его опции.

### 1.2 Структура файла модуля и Source Guard

Для предотвращения конфликтов и побочных эффектов в многофайловых проектах
каждый модуль начинается с Source Guard — защиты от повторного выполнения
кода при многократном подключении файла:

```bash
#!/usr/bin/env bash
# lib/my_module.sh
#
# @depends core/const, core/logger, core/utils

# Source Guard — bs::guard предоставляется core/prereq.sh, который
# автозагружается первым из bootstrap/init.sh; модули НЕ подключают
# его вручную
bs::guard "MY_MODULE" || return 0

# Зависимости — self-source относительно файла модуля (модуль работает
# и при прямом source, без загрузчика); @depends в заголовке дублирует
# их для load
bs::source_relative "../core/const.sh" "../core/logger.sh" "../core/utils.sh"

# Глобальные константы и структуры модуля
readonly MODULE_NAME="my_module"
declare -gA MODULE_CONFIG
```

`bs::guard "name"` ([core/prereq.sh](../../core/prereq.sh)) атомарно проверяет
и выставляет переменную `__NAME_SOURCED`: возвращает 1, если модуль
**уже загружался** (тогда `|| return 0` завершает подключение), и 0 при
первой загрузке — метка ставится, код модуля выполняется дальше.

При первой загрузке переменная `__MY_MODULE_SOURCED` не определена — код
выполняется; при повторной переменная уже существует, и `return` пропускает
тело файла. Ручную идиому `[[ -n "${__X_SOURCED:-}" ]] && return 0` в новых
модулях не используйте. Не подключайте и `core/prereq.sh` вручную —
`bootstrap/init.sh` загружает его раньше всех остальных модулей, поэтому
`bs::guard` и `bs::source_relative` доступны априори. Устаревший
`utils::guard` из `core/utils.sh` сохранён как алиас для обратной
совместимости.

Не загружайте модули через `source lib/...`. Используйте функцию `load`
([bootstrap/loader.sh](../../bootstrap/loader.sh)): она разрешает пути
относительно `BS_ROOT`, отслеживает уже загруженные модули и обнаруживает
циклические зависимости. Подробнее о метаданных модуля см.
[раздел 8](#8-метаданные-модуля-и-source-guard).

## 2. Именование

| Объект                            | Стиль               | Спецификация                                                    | Пример                        |
|-----------------------------------|---------------------|-----------------------------------------------------------------|-------------------------------|
| Константы и глобальные readonly   | SCREAMING_SNAKE_CASE | Префикс модуля для изоляции                                     | `readonly __MYLIB_MAX_RETRIES=5` |
| Функции                           | `lower_snake_case()` | Публичный API фреймворка — с префиксом модуля: `module::function()` | `validate_input()`, `log::info()` |
| Приватные функции                 | `_leading_underscore` или двойное двоеточие | Видимость только внутри модуля                    | `_helper_calculate()`, `log::__timestamp()` |
| Локальные переменные              | lower_snake_case    | Префикс `l_` для ясности (опционально)                          | `l_temp_file`                 |
| Параметры функции                 | lower_snake_case    |                                                                 | `local -r file_path="$1"`     |
| Глобальные изменяемые             | lower_snake_case    | Не рекомендуется. Использовать функции-геттеры или ассоциативные массивы | (избегать)           |
| Глобальные ассоциативные массивы  | SCREAMING_SNAKE_MAP | `declare -gA` в области модуля                                  | `declare -gA CONFIG_MAP`      |

Важные особенности: фреймворк использует паттерн Source Guard
(`__*_SOURCED`), пространства имён функций с префиксом `module::` и декларирует
конфигурацию в ассоциативных массивах — всё это необходимо для сложных
скриптов.

### 2.1 Почему snake_case, а не CamelCase

BS сознательно использует единый unix-like стиль (`lower_snake_case` +
неймспейсы `module::`) везде; CamelCase не используется никогда:

- **В shell нет компилятора.** Опечатку в регистре (`System::Hw::Cpu` vs
  `system::hw::cpu`) ничто не поймает на этапе написания. В snake_case
  опечатка регистра невозможна по построению — всё одним регистром.
- **Один стиль — ноль двусмысленности.** С двумя стилями каждое имя
  вызывает вопрос «а тут как?». `system::hw::cpu_threads` уже читается как
  путь — CamelCase лишь добавляет второй способ написать то же самое.
- **Единообразие с экосистемой.** Встроенные команды, coreutils и
  переменные окружения — все в snake/SCREAMING: новичок читает маны и чужие
  скрипты в том же стиле.
- **Инструментарий.** Один стиль упрощает грамматику и naming-диагностику
  LSP-сервера.

Матрица стилей:

- `SCREAMING_SNAKE_CASE` — константы, `readonly`, переменные окружения.
- `lower_snake_case` — функции, переменные, имена модулей. Никакого mixedCase.
- `__double_underscore` — приватное.

Если когда-нибудь появится класс-подобная подсистема (конструкторы, типовые
значения), слот PascalCase можно будет обсудить отдельно — но пока типов
нет, нет и слота для CamelCase.

## 3. Документация функций

Google Guide рекомендует комментарии; мы формализуем формат для публичного
API модулей:

```bash
# Calculate the sum of two integers.
# Args:
#   $1: First integer (required).
#   $2: Second integer (required).
# Returns:
#   0 on success, 1 on invalid input.
# Outputs:
#   Writes the result to stdout.
add_integers() {
  local -r first="$1"
  local -r second="$2"
  # ... validation logic ...
  printf '%d\n' "$(( first + second ))"
}
```

Или DocBlock-стиль с `@`-аннотациями:

```bash
# @description Краткое описание функции.
# @param $1 Первый аргумент - описание.
# @param [$2=default] Второй аргумент со значением по умолчанию.
# @returns 0 в случае успеха.
# @returns 1 в случае ошибки.
# @stdout Выводит результат в стандартный вывод.
# @stderr Выводит ошибки в стандартный поток ошибок.
# @example
#   function_name "arg1" "arg2"
# @see related_function
# @deprecated Используйте new_function вместо этой.
```

### Рекомендуемый гибрид для BS

Основной текст — в читаемом формате Google Style, а `@`-аннотации добавляются
для автоматической генерации документации:

```bash
# Проверить входную строку по шаблону.
#
# @function validate_input
# @param $1 {string} Входная строка для валидации
# @param $2 {regex} Регулярное выражение для проверки
# @returns 0 если валидация успешна
# @returns 1 если строка не соответствует шаблону
# @example
#   validate_input "test@example.com" '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
validate_input() {
  local -r input="$1"
  local -r pattern="$2"
  if [[ "$input" =~ $pattern ]]; then
    return 0
  else
    return 1
  fi
}
```

### Правила

1. Все публичные функции должны иметь документацию.
2. Используйте формат Google Style как основной текст.
3. Добавляйте `@`-аннотации для важных метаданных.
4. Обязательные аннотации: `@param`, `@returns`, `@stdout`/`@stderr`.
5. Опциональные: `@example`, `@see`, `@deprecated`.

## 4. Переменные и данные

### 4.1 Объявление и область видимости

- Всегда используйте `local` для переменных внутри функций.
- Используйте `local -r` для параметров и констант внутри функции.
- Для чисел и массивов: `local -i`, `local -a`.
- Глобальные ассоциативные массивы — мощный инструмент конфигурации.
  Используйте осторожно:

```bash
# Объявить один раз в начале модуля
declare -gA SERVICE_ENDPOINTS

_init_config() {
  SERVICE_ENDPOINTS["api"]="https://api.example.com"
  SERVICE_ENDPOINTS["db"]="postgresql://localhost:5432"
}

get_endpoint() {
  local -r service_name="$1"
  # Проверка существования ключа КРИТИЧЕСКИ ВАЖНА
  if [[ -v "SERVICE_ENDPOINTS[${service_name}]" ]]; then
    printf '%s\n' "${SERVICE_ENDPOINTS[${service_name}]}"
  else
    log::error "Endpoint for service '${service_name}' not defined."
    return 1
  fi
}
```

### 4.2 Категории переменных уровня модуля и их документация

Каждая переменная, объявленная вне функции (`declare -g`, `readonly`,
`export`, `: "${VAR:=...}"`), относится к одной из категорий ниже. Категория
определяет маску имени и необходимость документационного снипета.

| № | Категория | Маска | Примеры | Снипет |
|---|---|---|---|---|
| 1 | Guard-флаги | `__<MODULE>_SOURCED` | `__ARGS_SOURCED`, `__PREREQ_SOURCED` | нет — выставляются программно через `bs::guard`, документированы один раз в `core/prereq.sh` |
| 2 | Метаданные модуля | `<MODULE>_LOADED`, `<MODULE>_VERSION` | `ARGS_LOADED`, `CORE_LANG_VERSION` | да |
| 3 | Эфемерные (временные init.sh) | `__name__` | `__bs_src__`, `__BS_INIT_DIR__` | опционально |
| 4 | Nameref-локальные | `__sl_*`, `__arr_*`, `__map_*`, `__b_*` | `__arr_elem`, `__sl_start` | нет — локальны, защита от shadowing by design |
| 5 | Приватные функции | `ns::__name` | `log::__format_message` | функции, не переменные |
| 6 | Приватные локальные | `_name` | `_rc`, `_saved_stdout` | нет — локальны |
| 7 | Константы ошибок | `E_*`, `LIB_ERROR_*` | `E_ERROR`, `LIB_ERROR_INVALID_ARGS` | да |
| 8 | Флаги фреймворка | `FRAMEWORK_*` | `FRAMEWORK_DEBUG`, `FRAMEWORK_DRY_RUN` | да |
| 9 | Env-переменные | `BS_*` | `BS_ROOT`, `BS_SILENT`, `BS_CONFIG_*` | да |
| 10 | Хуки модулей | `<MODULE>_*_{DIR,PATH,MOCK,FILE,TIMEOUT}` | `HW_DMI_PATH`, `LLM_MOCK_RESPONSE`, `VK_API_CACHE_DIR` | да |
| 11 | Константы модуля | `readonly SCREAMING_SNAKE` | `COLOR_RESET`, `SSH_NETWORK_CONNECT_TIMEOUT` | да |
| 12 | Внутреннее состояние модуля | `__<MODULE>_*` | `__ARGS_TREE`, `__ARGS_FLAGS` | да |
| 13 | Состояние модуля (публичное, изменяемое) | `<MODULE>_*` (не хук, не readonly) | `TUI_KEY`, `TUI_MODAL_STACK`, `SSHD_WZ_VALUES` | да |

Объявление через `: "${VAR:=...}"` — всегда **хук** (категория 10)
независимо от суффикса имени.

**Формат снипета.** Переменные уровня модуля категорий 2, 7-11 несут
билингвальный снипет непосредственно над объявлением:

```bash
# @global FRAMEWORK_DEBUG — framework flag (category: framework-flag); default false
# @global FRAMEWORK_DEBUG — флаг фреймворка (категория: framework-flag); по умолчанию false
declare -g FRAMEWORK_DEBUG=false
```

- Снипет начинается с `# @global <ИМЯ> —`, называет метку категории и
  описывает назначение/значение по умолчанию. Читатель видит, что это за
  переменная, не читая места её использования.
- Метки категорий (машиночитаемые): `guard-flag`, `module-flag`,
  `ephemeral`, `nameref`, `private-fn`, `underscore`, `error-const`,
  `framework-flag`, `env`, `hook`, `constant`, `private`, `state`.
- Категории 1, 4, 6 снипета не требуют (программные или локальные).

**Гигиена масок.** Якорение границ обязательно: `\bE_[A-Z][A-Z_]*\b`
находит `E_ERROR`, но НЕ подстроку `E__` внутри `__BS_ROOT_CANDIDATE__`
(неограниченная `E_[A-Z_]+` её находит). Порядок проверок тоже важен:
сначала якорная `__name__` (категория 3), затем открытая `__x_y`
(категория 4) — `__bs_src__` попадает под обе маски.

## 5. Обработка ошибок и логирование

Google Guide предлагает для ошибок обычный `echo`; во фреймворке есть модуль
логирования ([core/logger.sh](../../core/logger.sh)) и модуль обработки ошибок
([core/errorhandler.sh](../../core/errorhandler.sh)):

- Нефатальные ошибки: возвращайте осмысленные коды (1-63), пишите в stderr
  через `log::error`.
- Фатальные ошибки: используйте `error::exit "сообщение" [код]` — функция
  логирует сообщение, запускает зарегистрированные функции очистки и
  завершает скрипт. Учтите: `log::fatal` сам по себе **не** завершает скрипт —
  он возвращает код ошибки, а решение о выходе остаётся за вызывающим.

```bash
#!/usr/bin/env bs
load "core/logger"
load "core/errorhandler"

connect() {
  local -r host="$1"
  if ! utils::quiet ping -c1 "${host}"; then
    log::error "Host ${host} is unreachable"
    return 2  # код ошибки для "хост недоступен"
  fi
  # Если это критично для скрипта:
  # error::exit "Host ${host} is unreachable" 101
}
```

## 6. Подавление вывода

Не пишите «голые» перенаправления `>/dev/null 2>&1` и `2>/dev/null`.
Используйте идиомы из [core/utils.sh](../../core/utils.sh) — они явно выражают
намерение и сохраняют код возврата:

| Вместо                           | Используйте      | Семантика                                    |
|----------------------------------|------------------|----------------------------------------------|
| `command -v cmd >/dev/null 2>&1` | `utils::has cmd` | проверка наличия команды в PATH              |
| `cmd >/dev/null 2>&1`            | `utils::quiet cmd` | выполнить, подавив stdout и stderr         |
| `cmd 2>/dev/null`                | `utils::quiet_err cmd` | выполнить, подавив только stderr       |
| `cmd >/dev/null 2>&1 \|\| true`  | `utils::ignore cmd` | выполнить и проигнорировать результат (всегда возвращает 0) |
| `cmd 2>/dev/null \|\| true`      | `utils::attempt cmd` | best-effort, stdout виден, неудача игнорируется |

Для условий используйте предикаты `is::*` из [core/lang.sh](../../core/lang.sh)
вместо тестовых флагов — `is::empty "${var}"` вместо `[[ -z "${var}" ]]`,
`is::file "${path}"` вместо `[[ -f "${path}" ]]`, `is::command cmd` вместо
`command -v ...` и т.д. (полная таблица: [core-api.md](04-api-reference/core-api.md)).

```bash
if utils::has dnf; then
  utils::quiet dnf check-update
fi

# utils::ignore — только там, где неудача команды действительно не важна
utils::ignore systemctl stop some-service
```

## 7. Абстракции фреймворка

Помимо базовых идиом в `core/utils.sh`, фреймворк предоставляет высокоуровневые
абстракции для потоков, файлов и процессов. Используйте их в новых модулях
вместо низкоуровневых команд.

### 7.1 Потоки ввода-вывода

Модуль `lib/io/streams.sh` централизует работу с потоками, FD и перенаправлениями.

| Вместо | Используйте |
|--------|-------------|
| `echo "$msg"` | `io::streams::print "$msg"` |
| `echo -n "$msg"` | `io::streams::printn "$msg"` |
| `printf "%s" "$data"` | `io::streams::printf "%s" "$data"` (формат — отдельный аргумент) |
| `>&2 echo` | `io::streams::eprint "$msg"` |
| `exec 1>file` | `io::streams::redirect_stdout "file"` |
| `exec 3>&1` / `exec 1>&3-` | `io::streams::save 1 saved` / `io::streams::restore "$saved" 1` |

```bash
load "lib/io/streams"

io::streams::print "safe output"
io::streams::eprint "error message"
```

Правила:
- Никогда не передавайте пользовательские данные в строку формата `printf`.
- Для динамических дескрипторов используйте синтаксис Bash 4: `exec {fd}<file`.
- Библиотечные функции не должны писать в stdout, если это не их прямая задача;
  диагностику направляйте через `log::warn` / `log::error`.

### 7.2 Файловые операции

Модуль `lib/io/files.sh` (FSH API) заменяет прямые вызовы `cp`, `mv`, `rm`.

```bash
load "lib/io/files"

io::files::copy_file "src.txt" "dst.txt"
io::files::ensure_dir "my/dir" "0750"
io::files::move "old" "new"
io::files::remove "tmp"
```

Особенности:
- Поддержка `FRAMEWORK_DRY_RUN=true`: команда только логируется, но не выполняется.
- Атомарные операции через временный файл/каталог рядом с целью.
- Автоматические бэкапы через `BS_FILES_BACKUP_SUFFIX`.
- Cross-device move с fallback на `cp -a` + `rm -rf`.
- Коды ошибок: `E_INVALID`, `LIB_ERROR_FILE_NOT_FOUND`, `LIB_ERROR_FILE_OPERATION`.

### 7.3 Сторож процессов и отладка strace

Модуль `lib/io/process.sh` запускает команду, следит за таймаутом и зависанием,
собирает диагностику и при необходимости запускает `strace`.

```bash
load "lib/io/process"

# Таймаут 60 с, считать зависшим после 30 с молчания
io::process::guard --timeout 60 --hang-after 30 -- ./long-task

# Дополнительно собирать сетевой strace
io::process::guard --timeout 120 --hang-after 60 --strace-net -- ./server
```

При срабатывании сторожа в диагностическом каталоге создаётся:
- `report.log` — снимок `/proc/<pid>/status`, `stack`, `fd/`, `wchan`, `ps`;
- `strace_file.log` — `strace -p <pid> -e trace=read,write,%file`;
- `strace_net.log` — `strace -p <pid> -e trace=%net` (если запрошен).

Правила:
- Всегда отделяйте аргументы самой команды от опций сторожа через `--`.
- strace запускается с `sudo -n`; если прав нет — диагностика собирается без strace.
- Используйте cleanup-stack (`cleanup::add`) для очистки дочерних процессов.

## 8. Метаданные модуля и Source Guard

### 8.1 Source Guard

Каждый модуль должен защищаться от повторного импорта. Используйте единую
обёртку `bs::guard` из [core/prereq.sh](../../core/prereq.sh) — она и проверяет
метку `__NAME_SOURCED`, и выставляет её за один вызов:

```bash
#!/usr/bin/env bash
# lib/my_module.sh

bs::guard "MY_MODULE" || return 0
```

`core/prereq.sh` автозагружается первым из `bootstrap/init.sh`, поэтому
`bs::guard` всегда доступен — модули никогда не подключают `prereq.sh` сами.

Файл [core/guard.sh](../../core/guard.sh) сохранён как обратносовместимая
обёртка над `core/prereq.sh`.

Устаревшие варианты, встречающиеся в старом коде:

```bash
# check-only хелпер из core/utils.sh (deprecated, алиас к bs::guard_loaded)
if utils::guard "MY_MODULE"; then return 0; fi
readonly __MY_MODULE_SOURCED=1

# ручная идиому в ранних модулях core/
[[ -n "${__CONST_SOURCED:-}" ]] && return 0
readonly __CONST_SOURCED=1
```

### 8.2 Метаданные

После Source Guard объявляйте версию и отметку о загрузке:

```bash
readonly MODULE_NAME="my_module"
declare -g MODULE_VERSION="1.0.0"
```

В конце модуля:

```bash
declare -g MODULE_LOADED="1"
```

### 8.3 Зависимости

Если модуль может быть подключён в обход загрузчика (например, через `source` из
другого модуля или напрямую пользователем), используйте `bs::source_relative`
из [core/prereq.sh](../../core/prereq.sh) для подключения зависимостей относительно
своего файла:

```bash
bs::guard "MY_MODULE" || return 0

# @depends core/logger, core/errorhandler, lib/io/streams
bs::source_relative "../core/logger.sh" "../core/errorhandler.sh" "../io/streams.sh"
```

Правила:
- Не подключайте `core/prereq.sh` вручную — он автозагружается первым из
  `bootstrap/init.sh`, поэтому `bs::guard` и `bs::source_relative` доступны
  априори.
- Все зависимости подключайте через `bs::source_relative`.
- Несколько зависимостей можно передать одним вызовом.
- Если модуль гарантированно загружается через `load`, используйте `load` и
  декларируйте зависимости комментарием `# @depends`.

### 8.4 Подключение через `load` (внутри фреймворка)

Когда модуль уже находится в загруженном окружении BS, используйте `load`:

```bash
# @depends core/logger, core/errorhandler, lib/io/streams
load "core/logger"
load "core/errorhandler"
load "lib/io/streams"
```

## 9. Структура проекта

Реальная структура фреймворка BS:

```text
bs/
├── bootstrap/         # Загрузка: init.sh, loader.sh (функция load)
├── core/              # Ядро: args, const, errorhandler, logger, utils, version
├── lib/               # Функциональные модули: audit, data, frameworks,
│                      #   integration, io, network, status, system, ui
├── install/           # Логика установки (actions, checks, path_manager)
├── tests/             # Тесты: testframework.sh, runalltests.sh,
│                      #   unit/, integration/, ...
├── examples/          # Примеры использования
├── documentation/     # Документация (en/, ru/)
├── bs                 # Лаунчер bs (цель shebang)
├── boot.sh            # Точка входа для инициализации окружения
├── install.sh         # Установщик
└── README.md
```

## 10. Тестирование и линтинг

Тестирование: используйте собственную тестовую библиотеку фреймворка
[tests/testframework.sh](../../tests/testframework.sh) — не BATS. Она
предоставляет `testframework::init`, `testframework::assert_true`,
`testframework::assert_false`, `testframework::assert_equal`,
`testframework::assert_file_exists`, `testframework::assert_command`,
`testframework::section` и `testframework::summary`. Каждая публичная функция
должна иметь unit-тест в `tests/unit/`; весь набор запускается через
`tests/runalltests.sh`.

```bash
#!/usr/bin/env bs
# tests/unit/testmymoduleunit.sh
set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"

main() {
  testframework::init
  testframework::section "Module initialization"
  testframework::assert_true '[[ -n "${BS_ROOT}" ]]' "BS_ROOT is set"
  testframework::summary
}

main "$@"
```

Линтинг: обязательно используйте [shellcheck](https://www.shellcheck.net/) —
в репозитории есть конфиг [.shellcheckrc](../../.shellcheckrc) и скрипт
[tests/validateshellcheck.sh](../../tests/validateshellcheck.sh). Настройте оба
в CI.

## 11. Вектор возможностей / Capability vector

Новые функции ядра (`core/`) и библиотеки (`lib/`) должны работать на
любом целевом окружении BS: GNU/Linux, macOS и FreeBSD (BSD userland),
busybox (Alpine), glibc и musl. Правила:

1. **Фича-детекция вместо ОС-детекции.** Проверяйте возможность, а не имя
   ОС. Не пишите `if [[ "$(uname)" == "Darwin" ]]` для выбора реализации —
   пробуйте инструмент/поведение:
   ```bash
   if printf 'a\nb' | sed -z 's/a/X/' >/dev/null 2>&1; then SED_Z=1; fi
   if printf 'x' | grep -Pq 'x' 2>/dev/null; then GREP_P=1; fi
   ```
2. **Probe chain с fallback.** Любой не-POSIX инструмент берётся через
   цепочку проб (эталон — `bs_build::sha256`): `sha256sum → shasum -a 256
   → cksum`. Свойства GNU-инструментов, которые требуют fallback:
   `grep -P`, `sed -z`, `stat -c`, `date +%N`, `readlink -f`, `head -c`.
   BSD-замены: `shasum`, `stat -f`, `perl -0` для многострочного sed.
3. **Никаких GNU-only вызовов в ядре без обёртки.** `core/` не должен
   вызывать `grep -P`/`sed -z` напрямую — только через модуль с fallback
   (например, `regex::matches --pcre` уже умеет ERE-фолбэк).
4. **`/proc` и `/sys` — Linux-only.** Проверяйте `[[ -d /proc ]]` перед
   чтением; на macOS/FreeBSD их нет. Аппаратные данные — через слой
   вроде `lib/system/hw` с хуками для тестов.
5. **Версионируйте по вектору возможностей.** Вектор:
   `kernel / arch / distro / family (ID_LIKE) / repo / userland / libc /
   bash / tools[]`. Репозиторий пакетов — производное от `ID_LIKE`,
   не от названия дистрибутива.
6. **Полное описание** — см. «Портируемость и вектор возможностей —
   рекомендации»: [documentation/ru/02-core-concepts/portability.md](02-core-concepts/portability.md);
   канон правил — этот раздел.

## 12. Код в пространстве `bs_` (ядро, ярус `@shell posix`)

Эта глава самодостаточна: по ней пишут и переводят **любую функцию ядра** (`bootstrap/`, `core/`, `install/`, точки входа). Файл с меткой `# @shell posix` подключают bash, zsh, dash, busybox ash, ksh93 и mksh, и **bash в нём не участвует**; поэтому здесь действуют свои правила. Из разделов 1–11 в силе остаются двуязычные комментарии (§3), `bs_guard` (§8.1), строгий режим только в точках входа (§1.1), `@global` для переменных (§4.2) и вектор возможностей (§11); **не действуют** `module::function` в определениях (§2), `local`, массивы и `[[ ]]` (§4.1). Образцы, на которые ссылается глава: [`core/data.sh`](../../core/data.sh) (слой данных), [`core/logger.sh`](../../core/logger.sh), [`core/quiet.sh`](../../core/quiet.sh), [`core/fmt.sh`](../../core/fmt.sh), [`core/calc.sh`](../../core/calc.sh), [`core/utils.sh`](../../core/utils.sh), [`core/errorhandler.sh`](../../core/errorhandler.sh), [`core/prereq.sh`](../../core/prereq.sh).

Как работать пошагово (процедура с проверками) — навык `bs-kernel-code`; что такое ярус и кто его проверяет — `bs-shell-abstraction` и `bs-shell-portability`. Здесь — **правила и причины**. Каждая причина проверена запуском в dash, busybox ash, ksh93, mksh, zsh и bash; если оболочки нет, правило всё равно действует (причина — в таблице оболочек `shell-portability.md`).

### 12.1 Что проверяет машина, а что — человек

| Правило | Кто следит |
|---|---|
| Файл разбирается в dash, ash, ksh, mksh, zsh (`X -n`) | `check_posix_tier.sh`, раздел «parse» |
| Нет `[[ ]]`, `(( ))`, массивов, `declare`, `${!x}`, `${x^^}`, `=~`, `<( )`, `$'..'`, `source`, ключевого слова `function`, `local -x`; нет `BASH_*`/`ZSH_*`/`FUNCNAME` вне файлов слоя | `check_posix_tier.sh`, раздел «syntax» |
| Каждая функция называется `bs_…` (или `__bs_…`) и не определена с `::` | `check_posix_tier.sh`, раздел «names» |
| Ярус работает в `dash` без bash в `PATH` | `check_posix_tier.sh`, раздел «run» |
| `local`, `[[ ]]`, `printf -v`, `echo -e`, `${x^^}`, `$'..'`, массивы | `shellcheck -s sh` (SC3043, SC3010, SC3045, SC3037, SC3059, SC3003, SC3030) |
| У каждого `posix`-файла `core/` есть переносимый тест | `tests/unit/testposixtierunit.sh` |
| Поведение одинаково во всех шести оболочках | `tests/unit/test<модуль>portableunit.sh` |
| **Не ловит ни одна машина:** `for w in $list` (zsh не делит), `cmd \| while read` (потеря переменных), `$(( ))` на больших числах, `${#s}` на не-ASCII, мутация внутри `$(...)`, `eval` с неподтверждённым именем, перекрытие временных переменных | тест на «трудных» значениях + ревью по этой главе |

Метку `# @shell posix` ищут в **первых 14 строках** файла (`head -n 14` в проверке): не уводите её ниже.

### 12.2 Имена: одно пространство `bs_`

Настоящая функция — идентификатор без `::`. **Весь** код ядра живёт в одном пространстве: `bs_` + прежнее имя, где `::` заменено на `_`, а ведущие `__` приватных имён убраны. Если прежнее имя уже начиналось с `bs::`, второй `bs_` не добавляют.

| Прежнее имя | Настоящее имя | Замечание |
|---|---|---|
| `utils::has` | `bs_utils_has` | базовое правило |
| `log::info` | `bs_log_info` | |
| `calc::eval` | `bs_calc_eval` | |
| `bs::version::get` | `bs_version_get` | `bs::` не удваивается |
| `bs::guard` | `bs_guard` | |
| `cleanup::add` | `bs_cleanup_add` | пространство `cleanup` — не имя файла |
| `bs::exit` | `bs_exit` | |
| `function_exists` | `bs_function_exists` | не было `::` — просто префикс |
| `log::__timestamp` (приватное) | `bs_log_timestamp` | без ведущих `__`, пометка `# @private` |
| `utils::__tmp_cleanup` (приватное) | `bs_utils_tmp_cleanup` | |
| `arr::push` для настоящего массива bash | остаётся `arr::push` | слой данных — `bs_arr_push`, **другие** функции |

Правила:

1. **Модуль в имени — пространство, а не файл.** `core/quiet.sh` и `core/fmt.sh` определяют `bs_utils_*`: так назывались `utils::has` и `utils::human_size` до выноса. Выбирая имя, спросите «как это звали раньше» (или «в каком пространстве это живёт»), а не «в каком я файле».
2. **Вперёд — механически, назад — по таблице псевдонимов.** `bs_utils_quiet_err` ↔ `utils::quiet_err` восстанавливается только по блоку псевдонимов в конце файла: границу «модуль/функция» в `bs_a_b_c` по имени не угадать. Поэтому блок псевдонимов — единственный источник правды о старых именах.
3. **Проверяйте коллизии до выбора имени.** `a::b_c` и `a_b::c` оба дают `bs_a_b_c`. Перед новым именем: `grep -rn 'bs_модуль_имя' bootstrap core install lib bs boot.sh install.sh`.
4. **Зарезервированные префиксы:** `bs_shell_*` (слой `bootstrap/shell.sh`), `bs_guard*`, `bs_source_*` (`core/prereq.sh`), `bs_arr_*`, `bs_map_*`, `bs_data_*`, `bs_quote` (`core/data.sh`), `bs_log_*`, `bs_utils_*`, `bs_cleanup_*`, `bs_error_*`, `bs_signal_*`, `bs_deps_*`, `bs_version_*`, `bs_const_*`, `bs_calc_*`. Новый модуль берёт **новое** пространство и не лезёт в чужое.
5. **Приватное** — без ведущих `__`, но с пометкой `# @private` в doc-комментарии (пример: `bs_log_timestamp`, `bs_data_check`). Двойное подчёркивание внутри имени (`bs_guard__var`, `bs_source__one` в `core/prereq.sh`) проверка «names» пропускает, но оно историческое: новый код пишет `# @private` и обычное имя.
6. **Глаголы и порядок:** `bs_<пространство>_<глагол>[_<объект>]` (`bs_arr_push`, `bs_log_is_level_allowed`, `bs_cleanup_run_all`). Предикаты — `is_`/`has_`, результат — статус, не вывод (`bs_utils_has`).

**Псевдонимы.** Прежнее имя с `::` создаёт `bs_shell_alias настоящее старое::имя` **в самом конце файла**, одной строкой на функцию, в порядке определения (для приватных — `log::__timestamp`):

```sh
bs_shell_alias bs_utils_has utils::has
bs_shell_alias bs_log_timestamp log::__timestamp
```

Что делает `bs_shell_alias` (`bootstrap/shell.sh`): в bash и zsh определяет функцию-обёртку `old() { real "$@"; }`, в остальных оболочках не делает ничего (там `::` в имени — ошибка разбора). Следствия:

* **POSIX-код всегда зовёт настоящее имя.** Старое имя существует не везде; код яруса `bash4` и `lib/` вправе писать `module::function`, новый код полезно писать настоящим именем (меньше кадров стека).
* **Подмена в тестах — по настоящему имени.** Если тест переопределит `log::error`, вызов `bs_log_error` из POSIX-кода его не заметит; переопределив `bs_log_error`, вы перехватите оба пути (псевдоним вызывает настоящую функцию по имени в момент вызова).
* Через псевдоним в стеке вызовов появляется лишний кадр (`bs_error_throw` в `core/errorhandler.sh` учитывает это при поиске имени вызывающего).
* **Не переименовывайте** существующие функции и переменные: старые имена — публичный API `lib/` и пользовательских скриптов. Устаревшее помечают `# @deprecated` (пример: `bs_utils_guard`).
* Если у функции раньше не было `::`-имени и звать её из bash4-кода не нужно, псевдоним не обязателен; если сомневаетесь — добавьте: он стоит одну строку.

### 12.3 Заголовок и устройство файла

```sh
#!/bin/sh
# shellcheck shell=sh
# @shell posix — валидный POSIX sh: <что держит файл> / valid POSIX sh: <what holds the file>
# @tier core — <какие внешние команды нужны>; works everywhere
#
# core/модуль.sh — одна строка о назначении
# core/module.sh — one line about the purpose
#
# ИМЕНА / NAMES
#   Real functions: bs_модуль_а, bs_модуль_б; in bash and zsh also модуль::а, модуль::б (the old names).
#   Настоящие функции: bs_модуль_а, bs_модуль_б; в bash и zsh — ещё и прежние модуль::а, модуль::б.

# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points

bs_guard МОДУЛЬ || return 0

# Dependencies / Зависимости
bs_source_relative "const.sh" "data.sh"
```

Порядок частей файла: заголовок → блок «ИМЕНА / NAMES» → `bs_guard` → зависимости → `@global`-переменные и константы → приватные помощники → публичный API → блок псевдонимов → действия при загрузке (регистрация в стеке очистки, начальный `bs_log_debug`). Всё, что файл **делает** при подключении, стоит в самом конце и минимально: определения функций побочных эффектов не имеют.

* `#!/bin/sh` и `# shellcheck shell=sh` — для редакторов и `shellcheck -s sh`; файл подключают через `.`, исполняемым он не является.
* `@shell posix — <причина> / <reason>` — причина двуязычная и называет, **что держит файл**: «case, подстановки параметров, mktemp; массивы — из core/data.sh». Метку меняют только вместе с кодом и тестом (`bs-shell-abstraction`).
* `@tier core — …` — вторая ось, не путать с `@shell`: какой *userland* нужен файлу (`core` | `gnu-linux`, `bs audit` показывает ярус рядом с найденными GNU-only инструментами). После тире перечисляют внешние команды, без которых функции файла не работают: `builtins only`, `builtins and date`, `date, awk, head`, `builtins, tr and sleep`. Чем короче список, тем раньше модуль можно загружать.
* Блок «ИМЕНА / NAMES» перечисляет настоящие функции и говорит, что старые `::` — псевдонимы bash/zsh (образцы: `core/quiet.sh`, `core/logger.sh`). Если файл заменяет структуру данных — добавьте блок «ДАННЫЕ / DATA» (`core/errorhandler.sh`: стек очистки — массив `bs_cleanup_stack`).
* Порядок загрузки ядра задаёт `bootstrap/init.sh`: `prereq → lang → const → logger → quiet → fmt → data → errorhandler → version → utils → config → deps`. Модуль может звать только то, что загружено **раньше** него (или проверять `command -v bs_log_error`). Новый модуль регистрируют в `init.sh` и в списке `req` команды `bs doctor` (`bs-new-core-module`).

### 12.4 Защита от повторной загрузки

`bs_guard ИМЯ || return 0` — первая исполняемая строка после заголовка (`core/quiet.sh`, `core/logger.sh`). Единственное исключение — `core/prereq.sh`: `bs_guard` определён в нём же, поэтому там самозащита вручную.

* `ИМЯ` — **литерал** из `A-Z 0-9 _` (малые буквы `bs_guard` поднимает через `tr`, но пишите заглавными). Для нового модуля — имя модуля заглавными: `DATA`, `QUIET`, `FMT`, `LOGGER`, `UTILS`. Прежние `CORE_CALC` и `CORE_DEPS` не переименовывают.
* Имя должно быть **уникальным**: две разные части под одним именем — вторая не загрузится молча.
* `bs_guard` возвращает 1 («уже загружен») и 2 («плохое имя»). Идиома `|| return 0` скроет и 2, поэтому имя не собирают из переменных.
* Метка `__ИМЯ_SOURCED` объявляется `readonly`: повторный `source` в **том же процессе** возвращается немедленно. Для тестов это значит: каждая проба — свежий процесс `env -i … sh probe.sh`, а не повторный `source`.
* `return 0` допустим только на верхнем уровне подключаемого файла. `exit` в файле модуля не пишут никогда.

### 12.5 Подключение зависимостей и пути

Зависимости — `bs_source_relative "файл.sh" …` (пути от каталога вызывающего файла), в заголовке — `# @depends core/const, core/logger` (`core/errorhandler.sh`). Каталог файла берётся из `BS_CURRENT_FILE`: его ставит загрузчик и сама `bs_source_relative` на время `.` и возвращает прежним (вложенные подключения не портят друг друга). В bash дополнительно работает стек вызовов, в остальных оболочках **другого источника каталога нет**.

* Не вычисляйте путь файла сами: ни `$0`, ни `${BASH_SOURCE[0]}`, ни `$(dirname …)`. `$0` — только в прологе точки входа (тег `shell-gate`).
* В пробах и тестах перед `.` ставьте `BS_CURRENT_FILE="/абсолютный/путь/файл.sh"` (как `tests/unit/testdataportableunit.sh`), иначе в dash `bs_source_relative` остановится с `BS_CURRENT_FILE is not set`.
* Условные зависимости — `command -v bs_log_error >/dev/null 2>&1` на месте использования (пример: `bs_utils_error` в `core/utils.sh`, `bs_calc_log` в `core/calc.sh`), а не безусловный `bs_source_relative "logger.sh"` в низкоуровневом модуле.
* Файл, подключаемый по пути из аргумента, подключают через `bs_utils_ensure_source ФАЙЛ ФУНКЦИЯ` (проверяет, что нужная функция появилась); `# shellcheck disable=SC1090` с причиной.

### 12.6 Переменные

**Нет `local`.** Причины: его нет в POSIX; в ksh93 его вообще нет (`local: not found`); флаг действует на весь список имён — `local -r a=1 b=2` делает `readonly` **и** `a`, **и** `b` (`b=3` после этого — ошибка), и ошибка в одном имени в длинной строке `local` незаметна. Поэтому временные переменные функций — глобальные и несут префикс:

* **`__bs_<модуль>_`**, где `<модуль>` — короткий устойчивый код файла, уникальный по `bootstrap/`, `core/`, `install/`: `dat` (data), `log` (logger), `fmt`, `calc`, `ut` (utils), `dp` (deps), `eh` (errorhandler), `sb` (shebang), `gd` (guard), `t` (trampoline). Крупные функции вправе иметь свой подкод (`vc`/`vo` в `core/version.sh`; `g`, `gv`, `sr`, `so` в `core/prereq.sh`).
* Проверка уникальности: `grep -rhoE '__bs_[a-z0-9]+_' bootstrap core install bs boot.sh install.sh | sort -u`.
* Публичные настройки — `BS_*` (`BS_LOG_LEVEL`), по умолчанию через `: "${BS_LOG_LEVEL:=INFO}"` (значение пользователя не затирается); внутренние — только `__bs_*`.
* Инициализируйте каждую переменную, которую читаете, **в начале функции**: значение от прошлого вызова — не «пусто» (`__bs_dat_acc=''`, `__bs_log_text=''`).

**Глобальные временные переменные и вложенные вызовы.** Это главная цена отказа от `local`:

* Функция, вызывающая другую функцию **того же файла**, делит с ней префикс; если обе пишут в одно имя, внутренняя затрёт внешнюю. В `core/data.sh` `bs_arr_new` держит имя в `__bs_dat_nn`, а не в `__bs_dat_nm`, потому что `bs_arr_clear` внутри перезаписывает `__bs_dat_nm`; `bs_arr_copy` по той же причине держит `__bs_dat_src`/`__bs_dat_dst`. Перед вызовом помощника сверьте, какие имена он трогает.
* Рекурсия и обратные вызовы затирают переменные: `f() { __x=$1; [ "$1" -gt 0 ] && f $(($1 - 1)); echo "$__x"; }` печатает `0` на всех уровнях (проверено). Выходы: не рекурсировать; держать значения в позиционных параметрах (`bs_source_relative_from` переписывает `"$@"` через `set --`); считать глубину (`__bs_dat_depth` в `bs_arr_each`, имена обратных вызовов `__bs_dat_cmd_<глубина>`); обходить список через `for x in "$@"` — он раскрывается один раз и не зависит от внутренних вызовов.
* «Результат помощника — в переменной» — допустимый контракт, если он **назван в doc-комментарии** («результат в `__bs_log_out`», «имя в `__bs_dat_var`»), см. §12.8.

**Константы** — `bs_shell_readonly ИМЯ=значение` (`core/const.sh`), никогда голый `readonly`. Причина: загрузчик `load` — функция, и `readonly X=1` внутри подключаемого файла в zsh делает `X` **локальной** в этой функции (проверено: после `load` переменной нет); `bs_shell_readonly` в zsh вызывает `readonly -g`. Константа, у которой есть запасное значение (`E_ERROR`), читается как `"${E_ERROR:-1}"`: модуль может быть подключён без `core/const.sh`.

**Флаги модуля** объявляют `# @global` (§4.2) с категорией; для «читают тесты и другие модули» — `# shellcheck disable=SC2034  # причина / reason`.

### 12.7 Конструкции: можно и нельзя

Прежде чем писать помощник руками, загляните в базовые модули: `bs_var_*` (переменные по имени, проверенные имена), `bs_str_*` (регистр, обрезка, дословная замена, склейка), `bs_num_*` (точные целые), `bs_msg_*` (сообщения с запасным путём без логгера), `bs_arr_*`/`bs_map_*` (данные). Дублирование — так в ядре появилось пять копий одной проверки имени.

Разрешено: `case`, `[ ]`/`test`, подстановки `${v#p}`, `${v%p}`, `${v:-d}`, `${v-}`, `${v:?}`, `$(( ))` на небольших целых, `$( )`, `command -v`, `printf`, `while read -r`, `for x in список`, `. файл`, heredoc, `trap` (внутри функции), `eval` (см. §12.10).

| Не пишите | Пишите | Почему (проверено) |
|---|---|---|
| `[[ … ]]` | `[ … ]`, шаблоны — `case` | `[[` — не POSIX; в dash «not found». Составные условия — `[ a ] && [ b ]`, не `-a`/`-o` (неоднозначны) |
| `(( … ))`, `let` | `$(( ))` внутри `[ ]` или присваивания | не POSIX |
| Массивы, `declare -A`, `local -n` | `bs_arr_*`, `bs_map_*` (§12.11) | в dash и ash массивов нет вовсе, в mksh нет ассоциативных, а ksh93 объявляет их через , а массивы zsh считают с единицы |
| `local`, `local -r a b` | глобальные `__bs_<модуль>_…` | §12.6 |
| `${v^^}`, `${v,,}` | `tr '[:lower:]' '[:upper:]'` или `case` с `[Tt][Rr]…` (`bs_log_level_to_number`) | в dash, mksh, ksh93 — «Bad substitution» |
| `${v//a/b}`, `${v:3:2}` | цикл `case … ${v%%"$a"*}` (`bs_log_replace_all`), `cut` | подстановки нет в dash |
| `printf -v имя …` | `имя=$(printf …)` | dash: «Illegal option -v»; mksh печатает «-v» как текст |
| `$'\033'`, `$'\n'` | `__bs_esc=$(printf '\033')` один раз при загрузке | dash не раскрывает `$'..'` (печатает `$a<TAB>b`) |
| `echo -e`, `echo "$данные"` | `printf '%s\n' "$данные"` | dash печатает `-e` и сам разбирает `\t`; `echo -n` как данные — флаг |
| `source`, `function f {`, `==` в `[ ]`, `&>`, `\|&`, `<<<` | `.`, `f() {`, `=`, `>f 2>&1`, `2>&1 \|`, heredoc/`printf \|` | не POSIX |
| `[[ $x =~ … ]]`, `BASH_REMATCH` | `case "$x" in шаблон)` и подстановки (`core/version.sh`) | нет в POSIX |
| `${!имя}`, `declare -f`, `type -t` | `eval` с проверенным именем; `command -v` (`bs_function_exists`) | §12.10 |
| `read -a`, `-p`, `-n`, `-d` | `read -r`; подсказку — только если `[ -t 0 ]` (`core/calc.sh`) | флаги не POSIX; без `-r` `read` съедает обратные слэши |
| `$RANDOM`, `$SECONDS`, `EPOCHREALTIME`, `BASH_*` | `date`, `awk`; необязательное — с запасным путём (`bs_utils_now_ms` в `core/fmt.sh`) | есть не везде |
| `$(( ))` для больших чисел | `awk`, `dc` | **в mksh `$(( ))` 32-битная:** `3*1073741824` даёт `-1073741824` (так 3 GiB переполнялось в `core/fmt.sh`) |
| `$((08))`, `$((x))` из пользовательского ввода | отбросить ведущие нули и проверить `case "$x" in ''\|*[!0-9]*)` (`bs_error_retry`) | `08` — ошибка восьмеричного числа в dash и bash, но `8` в mksh |
| `${#s}` для ширины/обрезки не-ASCII | считайте как «символы или байты — зависит от оболочки» и пишите тест | dash и mksh считают байты, bash/zsh/ksh — символы по локали (рамка `bs_log_header`) |
| `for w in $список`, `set -- $строка` | цикл по `${s%% *}` / `${s#* }`; склейка — в цикле с явным разделителем | **zsh не делит значение переменной на слова** (`set -- $v` даёт `$#` = 1); а в скриптах BS `IFS` — перевод строки и табуляция (`bs_shell_strict`), и `"$*"` склеивает слова **переводом строки**, не пробелом |
| `cmd \| while read x; do … done` с записью в переменные | `while read … done < файл` или heredoc | в bash, dash, ash, mksh конвейер идёт в подоболочке и `n` остаётся 0, в zsh и ksh93 — нет (`n=2`): поведение расходится |
| Неэкранированная переменная | `"$v"`, `"$@"` | глоббинг и деление; единственное исключение — осознанный `eval "$(…)"` |
| `${x%%a\|b}`, голая `\|` в шаблоне подстановки | экранировать: `${x%%\|*}` или `case` | в ksh93 голая `\|` в `${x%%\|*}` — альтернатива, а не символ (нашёл `testdepsportableunit.sh`) |
| `exit` в функции | `return N`; `exit` — только `bs_exit`, точки входа, `trampoline.sh` | `exit` в подоболочке или в чужой функции убивает не то |
| `trap` при загрузке файла | `trap` внутри функции (`bs_errorhandler_setup_trap`), очистка — `bs_cleanup_add` | `trap` **заменяет** предыдущий обработчик, а не добавляется к нему |
| `cd` в функции | `( cd -- "$d" && … )` или `$(cd -- "$d" && pwd -P)` | `cd` меняет каталог вызывающего |
| Последняя строка `[ … ] && команда` | `if …; then …; fi` или `return 0` в конце | при `set -e` (а точки входа включают его) такая функция возвращает 1 и **завершает вызывающего**: `f(){ [ -n "$1" ] && echo x; }; f ""` убивает скрипт |

Код обязан работать **и с `set -eu`, и без**: все необязательные параметры — `${1-}`, `${VAR:-}`; ожидаемый ненулевой статус — `|| :` или `if`. Статусы внешних команд нормализуйте: `command -v` для отсутствующей команды возвращает 127 в dash и ash, 1 в остальных, поэтому `bs_utils_has` и `bs_function_exists` делают `|| return 1`.

### 12.8 Как возвращать значения

| Что нужно | Как | Образец |
|---|---|---|
| Ответ да/нет | только статус, без вывода | `bs_utils_has`, `bs_arr_contains` |
| Одно значение | `stdout`, строка = `printf '%s\n'`; статус 1 — «нет такого» | `bs_arr_get`, `bs_map_get` |
| Значение в горячем пути (загрузчик, `bs_guard`, `bs_map_has`) | **выходная переменная** — подоболочка `$(...)` стоит форка | `bs_guard__var` → `__bs_g_var`; `bs_log_replace_all` → `__bs_log_out` |
| Значение по желанию вызывающего | необязательный параметр «имя переменной»; пусто — в `stdout` | `bs_arr_pop имя [переменная]` через `bs_data_ret` |
| Много значений | массив слоя данных, имя которого передал вызывающий | `bs_utils_split выходной_массив строка разделители` |

* **Функции, меняющие состояние и возвращающие значение (`bs_arr_pop`, `bs_arr_shift`), нельзя звать как `$(...)`:** подоболочка меняет свою копию, исходное состояние остаётся (проверено: `v=$(bs_arr_pop a)` вернул `z`, но длина `a` осталась 3; `bs_arr_pop a v` — длина 2). В doc-комментарии такой функции пишут «НЕ вызывайте как `$(...)`, берите результат в переменную».
* `$(...)` отрезает **завершающие переводы строки**: значение, которое может ими заканчиваться, через `stdout` не вернуть без потерь — только в переменную.
* Имя выходной переменной **проверяют до `eval`** (`bs_data_ret`: `case "$1" in [!A-Za-z_]*|*[!A-Za-z0-9_]*) … return 2`).
* **Функция, чей `stdout` — результат, не печатает ничего лишнего.** `bs_log_info`, `bs_log_debug`, `bs_log_trace`, `bs_log_success` пишут в stdout (предупреждение и ошибка — в stderr), и вызов такого `bs_log_*` внутри `$(...)` испортит результат. Диагностику в «возвращающей» функции пишут через `bs_log_warn`/`bs_log_error` или в stderr.
* Выходные временные имена документируют так же, как параметры (§12.13).

**Коды возврата.** `0` — успех; `1` — «нет/ложь/ошибка» (`${E_ERROR:-1}`); `2` — неверный вызов, плохое имя, недопустимый аргумент (`${E_INVALID:-2}`); остальные — `LIB_ERROR_*` из `core/const.sh`. Статус последней команды функции — её статус: заканчивайте явным `return`, если последняя команда может вернуть не то.

### 12.9 Ошибки, выход и сообщения

* Функции возвращают код, `exit` не вызывают. Выход — `bs_exit [код|ИМЯ]` (выполняет очистку), `bs_error_exit СООБЩЕНИЕ [код]`; код-имя (`E_<ИМЯ>`, `LIB_ERROR_<ИМЯ>`) проверяется `case … *[!A-Z0-9_]*` **до** `eval` (`bs_exit` в `core/errorhandler.sh`).
* `${1:?сообщение}` — штатная идиома **обязательного** аргумента (ошибка программиста). Она завершает скрипт в bash, dash, ash, ksh93 и zsh, но **не в mksh**: тот печатает сообщение и продолжает (проверено). Поэтому это диагностика, а не управление потоком. Для входа, который может быть пустым по вине пользователя, пишут `[ -n "${1-}" ] || return 2`.
* Строгий режим и `IFS` включают только точки входа через `bs_shell_strict`. Модуль строгий режим не включает и **не рассчитывает на него и на его отсутствие** (§12.7).
* Сообщения: после загрузки `core/logger.sh` — `bs_log_error "…"`; в модулях, которые грузятся **раньше** логгера или должны работать без него (`quiet`, `data`, `fmt`, `prereq`), и в проверяемом необязательно — `printf '%s\n' "…" >&2` (образцы: `bs_data_check`, `bs_utils_error`, `bs_calc_log`). Формат: `имя_функции: что не так: значение` (`bs_data: invalid name: …`).
* Ошибку «нечего делать» не оформляют как `ERROR`: это `return 0` (см. навык `bs-cli-noop-output`).
* Очистку регистрируют `bs_cleanup_add функция` (стек, последняя добавленная выполняется первой), а не `trap` на месте. Регистрацию при загрузке защищают: `if command -v bs_cleanup_add >/dev/null 2>&1; then …` (конец `core/utils.sh`).

### 12.10 Безопасность `eval`

`eval` в слое нужен для косвенных имён (нет `${!x}`, нет namerefs) — и это самое опасное место ядра. Разрешено ровно три случая:

1. **Чтение/запись переменной, имя которой составлено из проверенных частей:** `eval "__bs_dat_n=\${__bs_dat_a_${1}__n:-0}"`.
2. **Присваивание по имени, которое передал вызывающий:** `eval "$1=\${__bs_dat_out}"` — после `case`-проверки (`bs_data_ret`).
3. **Создание псевдонима** (`bs_shell_alias`): `eval "$2() { $1 \"\$@\"; }"` — только литералы из самого файла.

Правила:

* **Имя проверяют до любого `eval` и отказывают кодом 2.** Образец — `bs_data_check`: `''|[!A-Za-z]*|*[!A-Za-z0-9_]*|*__*|*_` (начало с буквы, только буквы/цифры/`_`, без `__` и без `_` на конце — чтобы не пересечься с внутренними именами слоя).
* **В строку `eval` подставляется только проверенное имя; значения передаются ссылкой** `\${переменная}` (раскрывается второй раз уже внутри `eval`), а не вставкой текста: `eval "…=\${__bs_dat_v}"`, не `eval "…=$значение"`.
* Если значение всё-таки нужно вставить в код — через `bs_quote` (единые кавычки, внутри `'\''`); `eval "$(bs_arr_to_args имя)"` безопасен именно потому, что каждый элемент пропущен через `bs_quote`.
* **Никогда не `eval` текста пользователя, файла, сети, аргументов командной строки.** Вместо этого — белый список в `case` (`bs_exit` принимает код-имя только `A-Z0-9_`).
* Вызов функции по имени — `"$имя" аргумент`, не `eval`; имя проверяют `command -v` (`bs_signal_on`); для `trap "$обработчик" СИГНАЛ` — `# shellcheck disable=SC2064  # причина`.
* `$` внутри строки `eval` экранируют (`\$`) там, где раскрывать надо **после** сборки имени, и не экранируют там, где имя собирается сейчас: ошибка здесь — тихая подстановка пустоты.
* Тест на `eval` обязателен: подайте «имя» вроде `a;touch /tmp/x` и `$(id)` и проверьте код 2 и отсутствие побочных эффектов (`tests/unit/testdataportableunit.sh`, `bs_arr_push "bad name"`).

### 12.11 Слой данных `core/data.sh`

Массивы и словари POSIX-кода — только `bs_arr_*`, `bs_map_*`, `bs_quote`; `declare -a`, `declare -A`, `local -n` запрещены. Имя структуры — `[A-Za-z][A-Za-z0-9_]*`, без `__` и без `_` на конце; свои структуры называют `bs_<модуль>_<что>` (`bs_cleanup_stack`, `bs_error_handlers`). Внутренние переменные `__bs_dat_*` чужие модули не читают и не пишут.

* Индексы с нуля, отрицательный — с конца; статус 1 — «нет такого», 2 — плохое имя.
* Обход: `eval "$(bs_arr_to_args имя)"`, затем `for x in "$@"`. Это **перезаписывает позиционные параметры функции** — делайте в функции, которой они уже не нужны (как `bs_arr_each`), или сохраните нужное в переменные.
* Разбор по одному элементу с опустошением: `while bs_arr_pop имя __bs_eh_fn; do …` (`bs_cleanup_run_all`).
* Обратный вызов `bs_arr_each имя функция` / `bs_map_each имя функция` принимает **имя функции**, а не строку команды; вложенность считается.
* `bs_arr_pop`, `bs_arr_shift` не звать как `$(...)` (§12.8).
* Цена: каждый доступ — `eval`, `bs_arr_shift` и `bs_arr_remove_at` — O(n). Для горячих циклов храните данные в позиционных параметрах или строке с разделителем.
* Ключ словаря может содержать что угодно (кодируется `_<hex>_`); порядок вставки сохраняется; значение с переводом строки целиком читается `bs_map_get` в stdout, но `bs_map_keys` печатает ключи построчно — для ключей с переводом строки есть `bs_map_keys_to`.
* Слой нельзя звать из файлов, которые грузятся **до** `core/data.sh`.

### 12.12 Логирование

После `core/logger.sh` модуль пишет сообщения только через `bs_log_trace|debug|info|success|warn|error|fatal`; `echo`/`printf` для сообщений пользователю — только там, где логгера ещё нет (§12.9). Цвет, формат (`text|structured|json`), уровень (`BS_LOG_LEVEL`) и метка времени задаются окружением (`BS_LOG_COLOR`, `BS_LOG_FORMAT`, `BS_LOG_TIMESTAMP`) и `NO_COLOR`; модуль их не читает и не меняет. Слова сообщения склеиваются пробелом независимо от `IFS` вызывающего (`bs_log_format_message`); передавайте их отдельными аргументами или одной строкой, не собирая `"$*"`. `bs_log_fatal` возвращает `${E_ERROR:-1}` и **не завершает** скрипт. Для отладочного сообщения при загрузке пишут `bs_log_debug "…" 2>/dev/null || true`: логгер может быть выключен.

### 12.13 Doc-комментарии

Двуязычие обязательно для каждой публичной функции и приватной, у которой нетривиальный контракт. Допустимы две формы, держитесь формы файла:

```sh
# @description Проверить имя массива или словаря / Check an array or map name
# @param $1 name / имя
bs_data_check() {
```

и двухстрочная (`core/quiet.sh`, `core/fmt.sh`):

```sh
# @description Check if command exists in PATH.
# @description Проверить наличие команды в PATH.
# @param $1 {string} Имя команды
# @returns 0  команда доступна
# @returns 1  команда не найдена
```

Теги: `@description`, `@param $N имя`, `@returns`, `@stdout`, `@private`, `@example`, `@function` (если имя в доке отличается от настоящего), `@deprecated`, `@global`. Правила: описание — **что гарантирует функция**, а не пересказ кода; каждый позиционный параметр назван; **выходные переменные названы** («результат в `__bs_log_out`»); разделение кодов `1` и `2` указано; для мутирующих функций — «НЕ вызывайте как `$(...)`»; для обязательных параметров — `${1:?}` и слово «required». Каждый `# shellcheck disable=…` несёт причину на двух языках: `# shellcheck disable=SC2154  # присваивается через eval / assigned through eval`. Строчные комментарии в коде — «по-русски / in English», коротко.

### 12.14 Тесты и проверка

У каждого `posix`-файла `core/` есть `tests/unit/test<модуль>portableunit.sh`: он подключает файл в каждой установленной оболочке (`testframework::posix_shells`) под `env -i`, сравнивает ответы на «трудных» значениях (пробелы, кавычки, `*`, `$`, обратный слэш, перевод строки, кириллица, пустая строка, `-n`), проверяет `::`-псевдонимы в bash и zsh и честно пишет «не проверено» для отсутствующих оболочек. Образцы: `testquietportableunit.sh` (минимальный), `testdataportableunit.sh` (структуры данных), `testloggerportableunit.sh` (вывод). Перед коммитом:

```bash
for sh in dash ksh mksh zsh bash; do "$sh" -n core/модуль.sh; done
busybox ash -n core/модуль.sh
shellcheck -s sh core/модуль.sh
bash .agents/skills/bs-shell-abstraction/scripts/check_posix_tier.sh
bash tests/validatesyntax.sh && bash tests/validateshellcheck.sh && bash tests/validatedocscode.sh
```

### 12.15 Чек-лист ревью

- [ ] Имя `bs_<пространство>_<имя>`, нет коллизий; блок псевдонимов в конце; старое имя не тронуто
- [ ] Заголовок: `#!/bin/sh`, `shellcheck shell=sh`, `@shell posix` с причиной (в первых 14 строках), `@tier core`
- [ ] `bs_guard ИМЯ || return 0`, зависимости — `bs_source_relative`, путь не вычисляется
- [ ] Нет `local`, `[[ ]]`, `(( ))`, массивов, `printf -v`, `$'..'`, `echo -e`, `${x^^}`
- [ ] Временные — `__bs_<модуль>_`, инициализированы, не затираются вложенным вызовом; константы — `bs_shell_readonly`
- [ ] Результат: статус / stdout / выходная переменная; мутирующая функция не рассчитана на `$(...)`
- [ ] Каждый `eval` — с проверенным именем и значениями по ссылке; есть тест на «плохое имя»
- [ ] Работает с `set -eu` и без; нет `[ ] && cmd` в конце функции; нет `exit`
- [ ] Сообщения — `bs_log_*` (или stderr до логгера); двуязычные doc-комментарии
- [ ] Тест `portableunit` во всех оболочках, дифференциальная сверка со старой реализацией, `check_posix_tier.sh` — OK
