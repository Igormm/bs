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
- Заключайте переменные в кавычки: `"${var}"`, а не `$var`.
- В файлах модулей обязательны:
  - строгий режим (`set -euo pipefail` и безопасный `IFS`, см.
    [1.1](#11-строгий-режим));
  - защита от повторного импорта Source Guard (см.
    [1.2](#12-структура-файла-модуля-и-source-guard));
  - загрузка зависимостей через `load`, а не прямой `source lib/...`.

## 1. Безопасность и надёжность

### 1.1 Строгий режим

Каждый основной скрипт должен включать строгий режим: прерывание при ошибке,
при использовании необъявленной переменной и при ошибке в pipeline, а также
безопасный разделитель полей:

```bash
set -euo pipefail
IFS=$'\n\t'
```

Во фреймворке для этого есть функция `utils::strict()`
([core/utils.sh](../../core/utils.sh)). Строгий режим включается только в
точках входа, но не в библиотечных модулях: модуль выполняется в shell
вызывающего и не должен незаметно менять его опции.

```bash
#!/usr/bin/env bs
load "core/utils"

utils::strict
```

### 1.2 Структура файла модуля и Source Guard

Для предотвращения конфликтов и побочных эффектов в многофайловых проектах
каждый модуль начинается с Source Guard — защиты от повторного выполнения
кода при многократном подключении файла:

```bash
#!/usr/bin/env bash
# lib/my_module.sh

# Source Guard
if utils::guard "MY_MODULE"; then return 0; fi
readonly __MY_MODULE_SOURCED=1

# Зависимости загружаются через load (путь от корня фреймворка,
# без расширения .sh)
load "core/logger"

# Глобальные константы и структуры модуля
readonly MODULE_NAME="my_module"
declare -gA MODULE_CONFIG
```

`utils::guard "name"` ([core/utils.sh](../../core/utils.sh)) проверяет
переменную `__NAME_SOURCED`: возвращает 0, если модуль ещё не загружался, и 1,
если уже загружался (тогда файл сразу завершает подключение).

При первой загрузке переменная `__MY_MODULE_SOURCED` не определена — код
выполняется; при повторной переменная уже существует, и `return` пропускает
тело файла.

Не загружайте модули через `source lib/...`. Используйте функцию `load`
([bootstrap/loader.sh](../../bootstrap/loader.sh)): она разрешает пути
относительно `BS_ROOT`, отслеживает уже загруженные модули и обнаруживает
циклические зависимости.

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

```bash
if utils::has dnf; then
  utils::quiet dnf check-update
fi

# utils::ignore — только там, где неудача команды действительно не важна
utils::ignore systemctl stop some-service
```

## 7. Структура проекта

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
├── documentation/     # Документация (en/, ru/, archive/)
├── bs                 # Лаунчер bs (цель shebang)
├── boot.sh            # Точка входа для инициализации окружения
├── install.sh         # Установщик
└── README.md
```

## 8. Тестирование и линтинг

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
