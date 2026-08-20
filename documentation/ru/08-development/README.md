[↑ Оглавление](../README.md)

# Руководство разработчика

Как написать модуль BS, добавить тест и выполнить проверки перед коммитом.

## Написание модуля

### Расположение и именование

Библиотечные модули лежат в `lib/<group>/<name>.sh`. Существующие группы:
`audit`, `data`, `frameworks`, `integration`, `io`, `network`, `status`,
`system`, `ui`. Базовые механизмы (логгер, args, utils, обработчик ошибок)
лежат в `core/`.

Публичные функции именуются `<group>::<module>::<func>` — например
`system::distro::detect()` в
[lib/system/distro.sh](../../../lib/system/distro.sh) или `io::streams::print()`
в [lib/io/streams.sh](../../../lib/io/streams.sh). Приватные вспомогательные
функции получают двойное подчёркивание перед именем: `io::streams::__is_fd()`.

### Скелет файла

```bash
#!/usr/bin/env bs
# lib/system/foo.sh — Short description of the module
#
# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points

# Source Guard / Защита от повторного подключения
# (bs::guard автозагружается из core/prereq.sh первым, bootstrap/init.sh)
bs::guard "SYSTEM_FOO" || return 0
```

Ключевые моменты:

- Shebang — `#!/usr/bin/env bs` (из-за него ShellCheck запускается с
  `-s bash`, см. [tests/validateshellcheck.sh](../../../tests/validateshellcheck.sh)).
- Модуль не вызывает `set -euo pipefail` и не меняет `IFS` — это задача точки
  входа (см. [Строгий режим](#строгий-режим)).
- Source guard предотвращает повторное выполнение при двойном подключении
  файла. Используйте обёртку `bs::guard` из
  [core/prereq.sh](../../../core/prereq.sh): она атомарно проверяет метку
  `__SYSTEM_FOO_SOURCED` и выставляет её; возвращает 1, если модуль уже
  загружался (тогда срабатывает `|| return 0`). `core/prereq.sh`
  автозагружается первым из `bootstrap/init.sh`, поэтому подключать его
  вручную не нужно. Ручная идиома
  `[[ -n "${__X_SOURCED:-}" ]] && return 0` и check-only хелпер `utils::guard`
  считаются устаревшими и оставлены для обратной совместимости.

### Зависимости

Загрузчик ([bootstrap/loader.sh](../../../bootstrap/loader.sh)) разбирает
комментарий `# @depends` в файле модуля и загружает перечисленные модули
первыми, с обнаружением циклов:

```bash
# @depends core/logger, lib/system/utils
```

Зависимости — пути модулей относительно `BS_ROOT`, без расширения `.sh`,
через запятую. Дополнительно каждый модуль подключает свои зависимости
self-source'ом сразу после Source Guard — путями относительно собственного
файла, поэтому модуль работает и при прямом `source` в обход загрузчика:

```bash
bs::guard "SYSTEM_FOO" || return 0

# Зависимости / Dependencies
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/const.sh"
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/logger.sh"
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/utils.sh"
```

В скрипте-точке входа модуль подключается так:

```bash
#!/usr/bin/env bs
load "lib/system/foo"
```

Не подключайте `lib/...` вручную через `source` в пользовательских скриптах —
`load` отслеживает загруженные модули в `BS_LOADED_MODULES` и пропускает
повторные подключения.

### Формат docstring

Публичные функции документируются `@`-аннотациями непосредственно над
функцией (гибридный стиль из
[руководства по стилю](../../code-style-guide.md)):

```bash
# @description Check if a package is installed / Проверить, установлен ли пакет
# @param $1 Package name / Имя пакета
# @return 0 if installed, 1 if not / 0 если установлен, 1 если нет
# @example
#   if system::distro::is_package_installed "curl"; then
#       echo "curl is installed"
#   fi
system::distro::is_package_installed() {
```

Обязательные аннотации: `@description`, `@param` на каждый аргумент,
`@return` / `@returns`. Опциональные: `@example`, `@private` (помечает
внутренние хелперы), `@see`, `@deprecated`. Прозу можно писать двуязычно
`English / Русский`, как в существующих lib-модулях.

## Идиомы тишины

Не используйте голые перенаправления в `/dev/null` в коде модулей — берите
обёртки из [core/utils.sh](../../../core/utils.sh). Они делают намерение
явным и сохраняют видимой семантику кодов возврата:

| Вместо | Используйте | Примечания |
|---|---|---|
| `command -v cmd >/dev/null 2>&1` | `utils::has cmd` | в условиях `if` |
| `cmd >/dev/null 2>&1` | `utils::quiet cmd` | код возврата сохраняется |
| `cmd 2>/dev/null` | `utils::quiet_err cmd` | код возврата сохраняется |
| `cmd >/dev/null 2>&1 \|\| true` | `utils::ignore cmd` | неудача действительно не важна |
| `cmd 2>/dev/null \|\| true` | `utils::attempt cmd` | best-effort, stdout виден |
| `[[ -z/-n ... ]]`, `[[ -f/-d ... ]]` | `is::empty`, `is::file`, ... | предикаты из `core/lang.sh` |

Реальное использование — [lib/system/distro.sh](../../../lib/system/distro.sh):

```bash
if utils::has lsb_release; then
    DISTRO_ID=$(utils::quiet_err lsb_release -si | tr '[:upper:]' '[:lower:]')
fi

# dnf|yum)
#     utils::quiet rpm -q "${package}"
```

`utils::ignore` — только для случаев, когда неудача команды действительно не
важна; не используйте его, чтобы скрывать ошибки, значимые для вызывающего.

## Строгий режим

`set -euo pipefail` и `IFS=$'\n\t'` задаются **только в точках входа** —
исполняемых скриптах вроде `bs`, `boot.sh` и тестовых раннеров в `tests/` —
и никогда внутри подключаемых модулей. В заголовке каждого модуля это
зафиксировано явно:

```bash
# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points
```

Причина: подключаемый модуль не должен менять опции чужого шелла как побочный
эффект. Код модулей пишется так, чтобы работать и со строгим режимом, и без
него (кавычки вокруг переменных, `"${var:-default}"`, явная проверка кодов
возврата). Для точек входа, предпочитающих вызов функции голой строке `set`,
есть хелпер `utils::strict()` в [core/utils.sh:17](../../../core/utils.sh).

## Добавление теста

1. Создайте файл в подходящем каталоге `tests/` — unit-тесты кладутся в
   `tests/unit/test<name>unit.sh` (шаблон см. в
   [tests/unit/testloaderunit.sh](../../../tests/unit/testloaderunit.sh)).
   Другие каталоги: `integration`, `data`, `frameworks`, `network`, `status`,
   `audit`, `demos`.
2. Скелет:

   ```bash
   #!/usr/bin/env bs
   # tests/unit/testfoounit.sh — Unit tests for lib/system/foo

   set -euo pipefail

   readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
   readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

   source "${TEST_SCRIPT_DIR}/../testframework.sh"

   export BS_SILENT=1
   source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
   export BS_HOME="${BS_PROJECT_ROOT}"

   main() {
       print_header "Foo Unit Tests"
       testframework::init

       testframework::section "Load"
       testframework::assert_command 'load "lib/system/foo"' "Load lib/system/foo"
       testframework::assert_true "true" "example assertion"

       testframework::summary
   }

   main "$@"
   ```

   Доступные проверки из
   [tests/testframework.sh](../../../tests/testframework.sh):
   `testframework::assert_true`, `testframework::assert_false`,
   `testframework::assert_equal`, `testframework::assert_file_exists`,
   `testframework::assert_command`.
3. Регистрация не нужна:
   [tests/runalltests.sh](../../../tests/runalltests.sh) запускает каждый
   `*.sh`, найденный в тестовых каталогах.

## Проверки перед коммитом

Запустите те же три скрипта, что запускает CI
([.github/workflows/ci.yml](../../../.github/workflows/ci.yml)):

```bash
bash tests/validatesyntax.sh       # bash -n по всем файлам
bash tests/validateshellcheck.sh   # ShellCheck, уровень error обязателен
bash tests/runalltests.sh          # полный прогон тестов
```

Примечания:

- `validateshellcheck.sh` завершается с кодом 0, если ShellCheck локально не
  установлен — в CI он устанавливается, поэтому при изменении нетривиального
  кода проверяйте предупреждения вручную.
- `runalltests.sh --with-root` дополнительно запускает деструктивные тесты,
  требующие root; делайте это только под root на одноразовой системе.
- CI прогоняет тесты в контейнерах с bash 5.x (ubuntu, debian, almalinux 9) и
  bash 4.4 (almalinux 8) — минимальной версией фреймворка. Не используйте в
  модулях возможности новее bash 4.4.
