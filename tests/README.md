# BS Framework Test Suite

## Overview / Обзор

This directory contains the test suite for the BS framework, organized by test type.
В этом каталоге находятся тесты фреймворка BS, сгруппированные по типам.

## Test Structure / Структура

```
tests/
├── runalltests.sh                 # Main test runner / Основной запуск тестов
├── validatesyntax.sh              # Syntax validation / Проверка синтаксиса
├── testframework.sh               # Test framework utilities / Утилиты тестового фреймворка
├── unit/                          # Unit tests / Модульные тесты
│   ├── testconstunit.sh           # core/const: коды ошибок, const::error_description
│   ├── testerrorhandlerunit.sh    # core/errorhandler: errorhandler::throw, cleanup-стек
│   ├── testversionunit.sh         # core/version: bs::version::compare
│   ├── testloaderunit.sh          # bootstrap/loader: load, повторы, ошибки
│   ├── testloggerunit.sh          # core/logger: уровни, форматирование
│   ├── testplatformcheckunit.sh   # lib/system/platformcheck
│   └── testps1configunit.sh       # lib/ui/ps1config
├── integration/                   # Integration tests (mocked) / Интеграционные тесты (на моках)
│   ├── testvkapi.sh               # lib/integration/vkapi (мок curl)
│   ├── testvkmusic.sh             # lib/integration/vkmusic (моки curl/vkapi, изолированный HOME)
│   └── testwireguard.sh           # lib/integration/wireguard — ROOT, см. ниже
├── data/
│   └── testdataprocessor.sh       # lib/data/dataprocessor (jq/xmllint/pyyaml)
├── frameworks/
│   └── testframeworksintegration.sh # lib/frameworks/frameworksintegration
├── network/
│   └── testsshnetwork.sh          # lib/network/sshnetwork (моки ssh/scp/rsync/nmap)
├── status/
│   └── testps1status.sh           # lib/status/ps1status
├── audit/
│   └── testsystemaudit.sh         # lib/audit/systemaudit — ROOT, см. ниже
└── demos/
    └── testps1configdemo.sh       # Демо модуля ps1config
```

## Running Tests / Запуск тестов

Запускать можно из любого каталога — пути вычисляются от расположения скриптов.
Tests can be run from any directory — paths are resolved from the script locations.

### Run All Tests / Запуск всех тестов
```bash
bash tests/runalltests.sh        # из корня проекта / from the project root
cd tests && bash runalltests.sh  # или из каталога tests / or from tests/
```

Общий прогон не требует root и не пишет ничего в `/etc` или реальный `~/.config`
(модули, работающие с домашним каталогом, тестируются в изолированном временном HOME).

The default run needs no root and writes nothing to `/etc` or the real `~/.config`
(modules that use the home directory are tested in an isolated temporary HOME).

### Destructive / root-requiring tests / Деструктивные тесты

По умолчанию пропускаются с явным сообщением (skip):
Skipped by default with an explicit message:

- `integration/testwireguard.sh` — пишет в `/etc/wireguard`, `/var/backups/wireguard`,
  поднимает сетевые интерфейсы; требует root.
- `audit/testsystemaudit.sh` — подменяет `/etc/ssh/sshd_config` и
  `/etc/security/pwquality.conf`; требует root.

Запуск — только явно и только под root:
Run them only explicitly and only as root:

```bash
sudo bash tests/runalltests.sh --with-root
```

`network/testsshnetwork.sh` в общий прогон включён: он полностью на моках
(ssh/scp/rsync/nmap/ssh-keygen) и работает в изолированном HOME.
`network/testsshnetwork.sh` is part of the default run: it is fully mocked
(ssh/scp/rsync/nmap/ssh-keygen) and runs in an isolated HOME.

### Validate Syntax / Проверка синтаксиса
```bash
bash tests/validatesyntax.sh
```
Проверяет `bash -n` для `bs`, `boot.sh`, `install.sh`, `bootstrap/`, `core/`, `lib/`,
`install/`, `tests/`. Exit 1, если есть ошибки синтаксиса или
отсутствующие обязательные файлы.
Runs `bash -n` over `bs`, `boot.sh`, `install.sh`, `bootstrap/`, `core/`, `lib/`,
`install/`, `tests/`. Exit 1 on syntax errors or missing required files.

### Run a Single Test / Запуск одного теста
```bash
bash tests/unit/testloggerunit.sh     # из корня / from the root
cd tests/unit && bash testloggerunit.sh  # или из каталога теста / or from its directory
```

## Test Coverage / Покрытие

### Core (unit)
- `core/const` — базовые коды возврата (E_SUCCESS/E_ERROR/E_INVALID),
  `const::error_description`, `const::is_valid_error_code`, `const::version`
- `core/errorhandler` — `errorhandler::throw` (код возврата, лог, без exit),
  идемпотентность cleanup-стека, `log::fatal` возвращает код
- `core/version` — `bs::version::compare` (меньше/равно/больше, включая 0.3.0 < 0.10.0)
- `core/logger` — уровни, форматирование, fallback невалидного уровня
- `bootstrap/loader` — загрузка модулей, защита от повторной загрузки,
  ошибка на несуществующем модуле без ложного circular dependency

### Lib (integration-style, на моках / mocked)
- `lib/system/platformcheck`, `lib/ui/ps1config`, `lib/status/ps1status`
- `lib/integration/vkapi`, `lib/integration/vkmusic` (мок curl, без реальных API-вызовов)
- `lib/network/sshnetwork` (моки ssh/scp/rsync/nmap/ssh-keygen)
- `lib/data/dataprocessor` (jq, xmllint, python3+pyyaml)
- `lib/frameworks/frameworksintegration` (bash-it/bashinator/bashly/shellspec/mbfl)

### Только с `--with-root` и под root
- `lib/integration/wireguard`, `lib/audit/systemaudit`

## Writing Tests / Написание тестов

### Using the Test Framework / Использование тестового фреймворка

```bash
#!/usr/bin/env bs
set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"   # нужен lib-модулям / needed by lib modules

main() {
    print_header "My Tests / Мои тесты"
    testframework::init

    testframework::section "Section / Раздел"
    testframework::assert_true "true" "True condition"
    testframework::assert_false "some::failing_command" "Command fails"
    testframework::assert_equal "expected" "${result}" "Equality"
    testframework::assert_file_exists "${BS_PROJECT_ROOT}/bs" "File exists"
    testframework::assert_command "ls /tmp" "Command succeeds"

    testframework::summary
}

main "$@"
```

Замечания / Notes:
- Счётчики инкрементируйте как `((++var))`: `((var++))` возвращает код 1 при
  нулевом значении и убивает скрипт с `set -e`.
  Increment counters as `((++var))`: `((var++))` returns status 1 at zero
  and kills the script under `set -e`.
- Если модуль пишет в `~/.config` или `~/Music`, экспортируйте изолированный
  `HOME=$(mktemp -d)` ДО source модуля (readonly-пути вычисляются из HOME).
  If a module writes to `~/.config` or `~/Music`, export an isolated
  `HOME=$(mktemp -d)` BEFORE sourcing the module (readonly paths derive from HOME).
- Двуязычные сообщения (RU/EN) приветствуются / Bilingual messages (RU/EN) are welcome.

## Debugging Tests / Отладка

```bash
export BS_LOG_LEVEL=DEBUG
bash tests/runalltests.sh

bash -x tests/unit/testloggerunit.sh
```

## Test Results / Формат результатов

- ✓ PASSED — зелёная галочка / green checkmark
- ✗ FAILED — красный крест / red cross
- ⊘ SKIP — жёлтый знак пропуска с причиной / yellow skip with a reason
- ▶ RUNNING — синяя стрелка / blue arrow

## License

Tests are part of the BS framework and follow the same licensing terms.
