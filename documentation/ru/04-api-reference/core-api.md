[↑ Оглавление](../README.md)

# Справочник Core API

Справочник по core-модулям: `core/logger.sh`, `core/errorhandler.sh`, `core/const.sh`, `core/version.sh`.
Про `core/args.sh` и `core/utils.sh` см. [Модуль Core utils](../03-modules/core-utils.md).

## Загрузка

В скрипте с shebang `#!/usr/bin/env bs` или после `source bootstrap/init.sh`:

```bash
#!/usr/bin/env bs
load "core/logger"       # логирование
load "core/errorhandler" # обработка ошибок и стек очистки
load "core/const"        # коды возврата и константы
load "core/version"      # информация о версии
```

`load` разрешает пути относительно `BS_ROOT` без расширения `.sh` и предотвращает повторную загрузку.

---

## Логирование — `core/logger.sh`

Все функции `log::*` принимают сообщение как `"$@"` (аргументы объединяются пробелами). Сообщение выводится, только если его уровень не ниже `BS_LOG_LEVEL`. `log::error` и `log::fatal` пишут в stderr, остальные — в stdout.

Веса уровней: `TRACE`=0, `DEBUG`=10, `INFO`=20, `SUCCESS`=25, `WARN`=30, `ERROR`=40, `FATAL`=50, `NONE`=1000 (отключает всё).

### Функции уровней

#### `log::trace <message...>`
- Параметры: `$@` — текст сообщения
- Возвращает: 0
- Пример: `log::trace "Entering function with args: $*"`

#### `log::debug <message...>`
- Параметры: `$@` — текст сообщения
- Возвращает: 0
- Пример: `log::debug "Processing item: $item"`

#### `log::info <message...>`
- Параметры: `$@` — текст сообщения
- Возвращает: 0
- Пример: `log::info "Starting process with PID: $$"`

#### `log::success <message...>`
- Параметры: `$@` — текст сообщения
- Возвращает: 0
- Пример: `log::success "Operation completed successfully"`

#### `log::warn <message...>`
- Параметры: `$@` — текст сообщения
- Возвращает: 0
- Пример: `log::warn "Configuration file not found, using defaults"`

#### `log::error <message...>`
- Параметры: `$@` — текст сообщения
- Возвращает: 0; вывод идёт в stderr
- Пример: `log::error "Failed to connect to database: $error"`

#### `log::fatal <message...>`
- Параметры: `$@` — текст сообщения
- Возвращает: `E_ERROR` (или 1, если `core/const.sh` не загружен); **не** завершает скрипт — решение за вызывающим
- Пример: `log::fatal "Critical error, cannot continue" || exit 1`

#### `log::print <message...>`
- Алиас для `log::info` (обратная совместимость)
- Параметры: `$@` — текст сообщения
- Возвращает: 0
- Пример: `log::print "Simple message"`

### Форматирование

#### `log::header <text> [char]`
- Параметры: `$1` — текст заголовка (обязательный); `$2` — символ подчёркивания (опционально, по умолчанию `=`)
- Возвращает: 0
- Пример: `log::header "Starting deployment"`

#### `log::list <item...>`
- Параметры: `$@` — элементы списка, каждый выводится с маркером (`•` с цветом, `*` без)
- Возвращает: 0
- Пример: `log::list "Item 1" "Item 2" "Item 3"`

#### `log::table <row...>`
- Параметры: `$@` — строки вида `"col1|col2|col3"`, выводятся с отступом
- Возвращает: 0
- Пример: `log::table "Name|Value" "Host|localhost" "Port|8080"`

#### `log::progress <current> <max> [width]`
- Параметры: `$1` — текущее значение (обязательный); `$2` — максимум (обязательный); `$3` — ширина полосы (опционально, по умолчанию 50)
- Возвращает: 0; перерисовывает полосу на месте (`\r`), переводит строку при `current == max`
- Пример: `log::progress 25 100`

#### `log::clear_line`
- Очищает текущую строку терминала (`\r\033[K`)
- Возвращает: 0
- Пример: `log::clear_line`

### Переменные настройки

Задаются до загрузки модуля (или экспортируются в окружение); значения по умолчанию применяются через `:=`:

| Переменная | Значения | По умолчанию | Описание |
|---|---|---|---|
| `BS_LOG_LEVEL` | `TRACE`, `DEBUG`, `INFO`, `SUCCESS`, `WARN`, `ERROR`, `FATAL`, `NONE` | `INFO` | Минимальный выводимый уровень |
| `BS_LOG_COLOR` | `auto`, `always`, `never` | `auto` | Цвета; `auto` = только когда stdout — TTY |
| `BS_LOG_FORMAT` | `text`, `json`, `structured` | `text` | Формат вывода |
| `BS_LOG_TIMESTAMP` | `true`, `false` | `true` | Метка времени `YYYY-MM-DD HH:MM:SS` в начале строки |

### Форматы вывода

- `text` — `[2026-07-29 19:24:13] INFO  message`, с ANSI-цветами, если разрешены (ERROR/FATAL — жирным).
- `json` — `{"timestamp":"...","level":"INFO","message":"..."}` (сообщение экранируется для JSON; ключ `timestamp` отсутствует при `BS_LOG_TIMESTAMP=false`).
- `structured` — `[2026-07-29 19:24:13] INFO  | message`, без цветов.

---

## Обработка ошибок — `core/errorhandler.sh`

### Стек очистки

Любой модуль может зарегистрировать функцию очистки; стек выполняется в порядке LIFO при завершении скрипта.

#### `cleanup::add <function>`
- Параметры: `$1` — имя функции очистки
- Возвращает: 0; 2, если имя не указано
- Пример: `cleanup::add my_cleanup_function`

#### `errorhandler::setup_trap`
- Устанавливает `EXIT`-trap, выполняющий стек очистки (`BS::__on_exit`). Только для точек входа.
- Возвращает: 0
- Пример: `errorhandler::setup_trap`

#### `bs::exit [code]`
- Параметры: `$1` — код выхода (опционально, по умолчанию 0)
- Не возвращается: выполняет весь стек очистки, затем `exit`
- Пример: `bs::exit 1`

### Отчёты об ошибках

#### `errorhandler::throw <func> <message> [code]`
- Параметры: `$1` — имя функции, где произошла ошибка; `$2` — сообщение; `$3` — код ошибки (опционально, по умолчанию `E_ERROR`)
- Возвращает: код ошибки; логирует через `log::error`, если логгер загружен, иначе печатает в stderr
- Пример: `errorhandler::throw "my::func" "Something failed" "${LIB_ERROR_FILE_NOT_FOUND}"`

#### `error::log <message>`
- Параметры: `$1` — сообщение
- Возвращает: 0; логирует ошибку без выхода
- Пример: `error::log "Non-fatal error occurred"`

#### `error::exit <message> [code]`
- Параметры: `$1` — сообщение; `$2` — код выхода (опционально, по умолчанию 1)
- Не возвращается: логирует сообщение и вызывает `bs::exit`
- Пример: `error::exit "Something went wrong" 2`

#### `error::exit_with_backtrace <message> [code]`
- Параметры: `$1` — сообщение; `$2` — код выхода (опционально, по умолчанию 1)
- Не возвращается: логирует сообщение и backtrace по `BASH_SOURCE`/`FUNCNAME`, затем выходит через `bs::exit`
- Пример: `error::exit_with_backtrace "Critical error occurred" 3`

#### `error::panic <message>`
- Параметры: `$1` — сообщение о критической ошибке
- Не возвращается: логирует `PANIC`, выполняет стек очистки, `exit 1`
- Пример: `error::panic "Critical system failure"`

### Пользовательские обработчики

#### `error::handle <code> <message>`
- Параметры: `$1` — код ошибки; `$2` — сообщение
- Возвращает: код возврата обработчика; если существует функция `error::handler::<code>`, она вызывается с сообщением, иначе выполняется `error::exit`
- Пример: `error::handle 127 "Command not found"`

#### `error::set_handler <code> <function>`
- Параметры: `$1` — код ошибки; `$2` — имя функции-обработчика (должна уже существовать)
- Возвращает: 0; 1, если функция-обработчик не существует
- Пример: `error::set_handler 127 my_not_found_handler`

#### `error::reset_handler <code>`
- Параметры: `$1` — код ошибки
- Возвращает: 0; удаляет `error::handler::<code>`
- Пример: `error::reset_handler 127`

#### `function_exists <name>`
- Параметры: `$1` — имя функции
- Возвращает: 0, если функция существует, иначе 1
- Пример: `function_exists "my::func" && my::func`

#### `error::handler::command_not_found <cmd>`
- Встроенный обработчик: логирует отсутствующую команду, предлагает пакет через `apt-cache`/`dnf` при наличии, затем `error::exit ... 127`
- Пример: `error::handler::command_not_found "mycommand"`

### Хелперы выполнения

#### `error::try <cmd> [args...]`
- Параметры: `$@` — команда для выполнения
- Возвращает: 0 при успехе; при неудаче логирует `Command failed: ...` и возвращает код команды
- Пример: `error::try command_that_might_fail`

#### `error::try_with_fallback <primary> <fallback>`
- Параметры: `$1` — основная команда строкой (выполняется через `eval`); `$2` — запасная команда строкой
- Возвращает: код запасной команды, если основная не удалась, иначе 0
- Пример: `error::try_with_fallback "critical_command" "fallback_command"`

#### `error::retry <max> <cmd> [args...]`
- Параметры: `$1` — максимум попыток; `$@` (с `$2`) — команда для выполнения; между попытками `sleep 1`
- Возвращает: 0 при первом успехе; иначе код последней неудачи после логирования ошибки
- Пример: `error::retry 3 command_that_might_fail`

#### `error::ignore <cmd> [args...]`
- Параметры: `$@` — команда, stderr отбрасывается, неудача игнорируется
- Возвращает: всегда 0 (`"$@" 2>/dev/null || true`); ср. `utils::ignore`, который глушит и stdout
- Пример: `error::ignore command_that_might_fail`

#### `error::with_timeout <seconds> <cmd> [args...]`
- Параметры: `$1` — таймаут в секундах; `$@` (с `$2`) — команда для выполнения
- Возвращает: код команды (124 при таймауте, по `timeout(1)`); если `timeout` недоступен — выполняет без таймаута с предупреждением
- Пример: `error::with_timeout 10 long_running_command`

Примечание: внутри используется проверка `command -v timeout >/dev/null 2>&1`; в своём коде предпочитайте `utils::has timeout` из `core/utils.sh`.

#### `error::conditional <condition> <message> [code]`
- Параметры: `$1` — условие строкой (выполняется через `eval`); `$2` — сообщение; `$3` — код выхода (опционально, по умолчанию 1)
- Возвращает: 0, если условие ложно; иначе выходит через `error::exit`
- Пример: `error::conditional "[[ -z ${config} ]]" "Config is empty" 2`

#### `error::conditional_warning <condition> <message>`
- Параметры: `$1` — условие строкой (выполняется через `eval`); `$2` — текст предупреждения
- Возвращает: 0; логирует предупреждение, если условие истинно
- Пример: `error::conditional_warning "check_deprecated_feature" "Feature is deprecated"`

---

## Константы — `core/const.sh`

### Коды возврата

| Константа | Значение | Смысл |
|---|---|---|
| `E_SUCCESS` | 0 | Успешное выполнение |
| `E_ERROR` | 1 | Общая ошибка |
| `E_INVALID` | 2 | Неверные аргументы или параметры |
| `LIB_ERROR_INVALID_ARGS` | 3 | Неверные аргументы функции |
| `LIB_ERROR_INVALID_INPUT` | 4 | Неверный формат входных данных |
| `LIB_ERROR_FILE_NOT_FOUND` | 5 | Файл не найден |
| `LIB_ERROR_PERMISSION_DENIED` | 6 | Отказано в доступе |
| `LIB_ERROR_DEPENDENCY` | 7 | Ошибка зависимости |
| `LIB_ERROR_UNSUPPORTED_OS` | 8 | Неподдерживаемая ОС |
| `LIB_ERROR_TIMEOUT` | 9 | Таймаут операции |
| `LIB_ERROR_CONFLICT` | 10 | Конфликт ресурсов |
| `LIB_ERROR_FILE_OPERATION` | 100 | Ошибка файловой операции |
| `LIB_ERROR_DEPENDENCY_MISSING` | 101 | Отсутствует зависимость |
| `LIB_ERROR_PLATFORM_UNSUPPORTED` | 102 | Платформа не поддерживается |

### Глобальные переменные

- `FRAMEWORK_DEBUG=false` — флаг режима отладки.
- `FRAMEWORK_DRY_RUN=false` — флаг «сухого запуска» (без выполнения действий).
- `BS_VERSION` — версия фреймворка; владелец — скрипт `bs` (readonly), здесь задаётся только если пусто.

### Группы констант

- Цвета: `COLOR_RESET`, `COLOR_RED`, `COLOR_GREEN`, `COLOR_YELLOW`, `COLOR_BLUE`, `COLOR_PURPLE`, `COLOR_CYAN`, `COLOR_WHITE`, `COLOR_BLACK`, а также варианты `COLOR_BRIGHT_*` (ANSI escape-последовательности).
- Форматирование: `SPINNER_CHARS='/-\|'`, `PROGRESS_BLOCK='█'`, `PROGRESS_EMPTY=' '`.
- Пути: `SYS_ETC`, `SYS_VAR`, `SYS_TMP`, `SYS_USR_LOCAL`, `SYS_HOME`.
- Валидация: `SUPPORTED_DISTROS=("alma" "centos" "rhel" "fedora" "debian" "ubuntu")`, `FILENAME_ALLOWED_CHARS='[a-zA-Z0-9._-]'`.

### Функции

#### `const::is_valid_error_code <code>`
- Параметры: `$1` — код ошибки
- Возвращает: `E_SUCCESS`, если код в диапазоне 0–10, иначе `E_ERROR`
- Пример: `const::is_valid_error_code 5`

#### `const::error_description <code>`
- Параметры: `$1` — код ошибки
- Возвращает: 0; печатает двуязычное описание (коды 0–10, иначе "Unknown error")
- Пример: `const::error_description "${LIB_ERROR_FILE_NOT_FOUND}"`

#### `const::version`
- Возвращает: 0; печатает `BS_VERSION`
- Пример: `const::version`

---

## Версия — `core/version.sh`

- `BS_VERSION` — текущая версия (например, `0.3.0`); экспортируется только если пусто, владелец readonly-переменной — скрипт `bs`.
- `BS_NAME="BS (Bash Open Source Architecture) BOSA Framework"`.

#### `bs::version::print`
- Печатает `"${BS_NAME} ${BS_VERSION}"`
- Возвращает: 0
- Пример: `bs::version::print`

#### `bs::version::get`
- Печатает строку версии
- Возвращает: 0
- Пример: `version=$(bs::version::get)`

#### `bs::version::compare <ver1> <ver2>`
- Параметры: `$1`, `$2` — версии через точку, сравниваются численно по частям
- Возвращает: 0, если равны; 1, если `ver1 > ver2`; 2, если `ver1 < ver2`
- Пример: `bs::version::compare "0.1.0" "0.2.0"; [[ $? -eq 2 ]] && echo "older"`

---

## Утилиты — `core/utils.sh`

`core/utils.sh` предоставляет хелперы общего назначения, включая канонические идиомы тишины, принятые во фреймворке:

- `utils::has cmd` — вместо `command -v cmd >/dev/null 2>&1`
- `utils::quiet cmd` — вместо `cmd >/dev/null 2>&1`
- `utils::quiet_err cmd` — вместо `cmd 2>/dev/null`
- `utils::ignore cmd` — вместо `cmd >/dev/null 2>&1 || true`

Полный справочник: [Модуль Core utils](../03-modules/core-utils.md).
