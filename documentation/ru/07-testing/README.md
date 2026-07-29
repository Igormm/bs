[↑ Оглавление](../README.md)

# Тестирование

Как устроен набор тестов BS, как его запускать и как писать новые тесты.

## Структура

Все тесты находятся в `tests/` и сгруппированы по типам:

```
tests/
├── runalltests.sh                 # Основной запуск тестов
├── testframework.sh               # Функции-проверки для написания тестов
├── validatesyntax.sh              # Проверка синтаксиса через bash -n
├── validateshellcheck.sh          # Проверка ShellCheck
├── unit/                          # Модульные тесты core и lib
│   ├── testargsunit.sh            # core/args
│   ├── testconstunit.sh           # core/const: коды ошибок, const::error_description
│   ├── testerrorhandlerunit.sh    # core/errorhandler: errorhandler::throw, cleanup-стек
│   ├── testloaderunit.sh          # bootstrap/loader: load, повторы, ошибки
│   ├── testloggerunit.sh          # core/logger: уровни, форматирование
│   ├── testplatformcheckunit.sh   # lib/system/platformcheck
│   ├── testps1configunit.sh       # lib/ui/ps1config
│   ├── teststreamsunit.sh         # lib/io/streams (io::streams)
│   └── testversionunit.sh         # core/version: bs::version::compare
├── integration/                   # Интеграционные тесты (на моках)
│   ├── testvkapi.sh               # lib/integration/vkapi (мок curl)
│   ├── testvkmusic.sh             # lib/integration/vkmusic (моки curl/vkapi, изолированный HOME)
│   └── testwireguard.sh           # lib/integration/wireguard — требует root, см. ниже
├── data/
│   └── testdataprocessor.sh       # lib/data/dataprocessor (jq/xmllint/pyyaml)
├── frameworks/
│   └── testframeworksintegration.sh # lib/frameworks/frameworksintegration
├── network/
│   └── testsshnetwork.sh          # lib/network/sshnetwork (моки ssh/scp/rsync/nmap)
├── status/
│   └── testps1status.sh           # lib/status/ps1status
├── audit/
│   └── testsystemaudit.sh         # lib/audit/systemaudit — требует root, см. ниже
└── demos/
    └── testps1configdemo.sh       # Демо модуля ps1config
```

## Запуск всего набора

```bash
bash tests/runalltests.sh        # из корня проекта
cd tests && bash runalltests.sh  # или из каталога tests/
```

Пути вычисляются от расположения скрипта, поэтому прогон работает из любого каталога. Раннер обходит каталоги в порядке: `unit`, `integration`, `data`, `frameworks`, `network`, `status`, `audit`, `demos`, затем выводит сводку (всего / пройдено / провалено / пропущено) и завершается с кодом `0`, если провалов нет, иначе `1`. Неизвестная опция — код выхода `2`.

Обычный прогон не требует root и ничего не пишет в `/etc` или реальный `~/.config`: модули, работающие с домашним каталогом, тестируются в изолированном временном `HOME`.

### Деструктивные тесты, требующие root

Два теста по умолчанию пропускаются с явным сообщением:

- `integration/testwireguard.sh` — пишет в `/etc/wireguard` и `/var/backups/wireguard`, поднимает сетевые интерфейсы; требует root.
- `audit/testsystemaudit.sh` — подменяет `/etc/ssh/sshd_config` и `/etc/security/pwquality.conf`; требует root.

Запуск — только явно и только под root:

```bash
sudo bash tests/runalltests.sh --with-root
```

С `--with-root`, но без прав root, они всё равно пропускаются (с причиной `EUID != 0`).

## Запуск одного теста

Каждый тестовый файл — самостоятельный скрипт:

```bash
bash tests/unit/testloggerunit.sh        # из корня
cd tests/unit && bash testloggerunit.sh  # или из каталога теста
```

## Написание теста

Тестовые файлы подключают `tests/testframework.sh`, который предоставляет проверки и счётчики:

| Функция | Назначение |
|---|---|
| `testframework::init` | Сбросить счётчики и объявить старт фреймворка |
| `testframework::section "имя"` | Вывести заголовок раздела |
| `testframework::assert_true "усл" "имя"` | Проходит, если условие истинно (`"true"`/`"false"` или выражение `[[ ... ]]`) |
| `testframework::assert_false "команда" "имя"` | Проходит, если команда завершается с ошибкой |
| `testframework::assert_equal "ожид" "$факт" "имя"` | Равенство строк |
| `testframework::assert_file_exists "путь" "имя"` | Файл существует |
| `testframework::assert_command "команда" "имя"` | Команда завершается с кодом 0 |
| `testframework::summary` | Вывести итоги; возвращает 0, если провалов нет |

Типичный тест (шаблон реальных модульных тестов):

```bash
#!/usr/bin/env bs
set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"   # нужен lib-модулям

main() {
    print_header "My Tests"
    testframework::init

    testframework::section "Раздел"
    testframework::assert_true "true" "True condition"
    testframework::assert_false "some::failing_command" "Command fails"
    testframework::assert_equal "expected" "${result}" "Equality"
    testframework::assert_file_exists "${BS_PROJECT_ROOT}/bs" "File exists"
    testframework::assert_command "ls /tmp" "Command succeeds"

    testframework::summary
}

main "$@"
```

Замечания:

- Счётчики инкрементируйте как `((++var))`: `((var++))` возвращает код 1 при нулевом значении и убивает скрипт с `set -e`.
- Если модуль пишет в `~/.config` или `~/Music`, экспортируйте изолированный `HOME=$(mktemp -d)` **до** подключения модуля — readonly-пути вычисляются из `HOME`.
- В собственных проверках используйте идиомы из `core/utils.sh` вместо «сырых» перенаправлений: `utils::has cmd` вместо `command -v cmd >/dev/null 2>&1`, `utils::quiet cmd` вместо `>/dev/null 2>&1`, `utils::quiet_err cmd` вместо `2>/dev/null`, `utils::ignore cmd` вместо `>/dev/null 2>&1 || true`.

## Проверка синтаксиса

```bash
bash tests/validatesyntax.sh
```

Выполняет `bash -n` для обязательных точек входа (`bs`, `boot.sh`, `install.sh`, `bootstrap/init.sh`, `bootstrap/loader.sh`) и всех `*.sh` файлов в `core/`, `lib/`, `install/` и `tests/`. Код выхода `1` при любой ошибке синтаксиса или отсутствующем обязательном файле, иначе `0`.

## Проверка ShellCheck

```bash
bash tests/validateshellcheck.sh             # только ошибки
bash tests/validateshellcheck.sh --warnings  # + информационные предупреждения
```

Прогоняет `shellcheck -s bash` по всем `*.sh` файлам и скрипту `bs` (`-s bash`, потому что shebang `#!/usr/bin/env bs` неизвестен ShellCheck). Уровень error обязателен: любая ошибка — код выхода `1`. Предупреждения информационны и не роняют прогон. Если ShellCheck локально не установлен, скрипт честно пропускается с кодом `0` (в CI он устанавливается).

## CI

`.github/workflows/ci.yml` запускается на каждый push и pull request, два job:

- **lint** (`ubuntu-latest`) — устанавливает ShellCheck, затем выполняет `bash tests/validatesyntax.sh` и `bash tests/validateshellcheck.sh`.
- **tests** — выполняет `bash tests/runalltests.sh` в контейнерах дистрибутивов (`fail-fast: false`):

| Запись матрицы | Образ | Bash |
|---|---|---|
| ubuntu, bash 5.x | `ubuntu:latest` | 5.x |
| debian stable, bash 5.x | `debian:stable` | 5.x |
| almalinux 9, bash 5.1 | `almalinux:9` | 5.1 |
| almalinux 8, bash 4.4 (minimum) | `almalinux:8` | 4.4 — минимальная версия фреймворка |

В каждом контейнере сначала устанавливаются зависимости тестов (`git`, `procps`/`procps-ng`, `jq`, `curl`, `openssl`, `python3-yaml`/`python3-pyyaml`, `iproute2`/`iproute`, `nmap`, `rsync`, `openssh-client(s)`, `bc` и сопутствующие утилиты).

## Отладка

```bash
export BS_LOG_LEVEL=DEBUG
bash tests/runalltests.sh

bash -x tests/unit/testloggerunit.sh
```

Маркеры результатов: `✓ PASSED` (зелёный), `✗ FAILED` (красный), `⊘ SKIP` (жёлтый, с причиной), `▶ RUNNING` (синий).
