[↑ Оглавление](../README.md)

# Начало работы

## Что такое BS

**BS** — модульный фреймворк и стандартная библиотека для Bash 4+. В его
состав входят загрузчик модулей, логирование, обработка ошибок,
декларативные параметры скриптов, абстракция потоков ввода/вывода и набор
системных модулей — всё в едином стиле кода и без единой внешней
зависимости.

## Требования

- Bash 4.4+ (минимум CI)
- Linux (основная платформа; macOS поддерживается частично)

Ничего больше не требуется: BS использует только встроенные команды bash и
стандартные системные утилиты.

## Установка

BS работает прямо из репозитория — установка необязательна и нужна только
для того, чтобы команда `bs` оказалась в `PATH`.

### Запуск из репозитория

```bash
git clone <repo-url> bs
cd bs
./bs doctor
```

### Локальная установка (`~/.local`, без sudo)

```bash
./install.sh --local
```

Копирует фреймворк в `~/.local/lib/bs`, создаёт обёртку `~/.local/bin/bs` и
добавляет `~/.local/bin` в `PATH` в `~/.bashrc` / `~/.zshrc` (идемпотентно).
Помощники для настройки PATH:

```bash
./install.sh --local --path          # print the export snippet
./install.sh --local --update-path   # add to ~/.bashrc / ~/.zshrc
```

### Системная установка (`/usr/local`, нужен root)

```bash
sudo ./install.sh
```

Файлы попадают в `/usr/local/lib/bs`, обёртка — в `/usr/local/bin/bs`.

Каталоги установки можно переопределить переменными окружения `PREFIX`,
`BIN_DIR` и `LIB_DIR`.

### Удаление

```bash
sudo ./install.sh uninstall      # system
./install.sh --local uninstall   # local
```

> **Примечание про исходный каталог.**  
> Установщик **копирует** файлы BS в целевой каталог
> (`~/.local/lib/bs` при `--local`, `/usr/local/lib/bs` при системной
> установке; пути можно переопределить через `PREFIX`/`LIB_DIR`/`BIN_DIR`)
> и создаёт обёртку `bs` в соответствующем `bin/`. После успешной
> установки исходный репозиторий можно удалить — фреймворк будет
> работать из целевого каталога.

## Проверка установки

```bash
./bs doctor    # framework integrity check
./bs list      # list modules
./bs version   # framework version
```

- `bs doctor` проверяет наличие `bootstrap/init.sh`, core-модулей и каталогов
  `core/` и `lib/` в `BS_ROOT` и возвращает ненулевой код, если чего-то не
  хватает.
- `bs list` выводит модули, лежащие непосредственно в `core/` и `lib/`
  (например, `core/args.sh`, `lib/automation.sh`). Вложенные модули вроде
  `lib/io/streams.sh` находятся в подкаталогах и подключаются по пути.

## Первый скрипт

Рабочая копия: [examples/hello.sh](../../../examples/hello.sh).

```bash
#!/usr/bin/env bs
# shellcheck shell=bash
set -euo pipefail

load "lib/io/streams"

io::streams::print "hello from BS ${BS_VERSION}"
```

- `#!/usr/bin/env bs` — запускает скрипт через интерпретатор `bs`; ядро
  фреймворка загружается до вашего кода, bootstrap-бойлерплейт не нужен.
- `# shellcheck shell=bash` — обязательно на строке 2, если shebang — `bs`.
- `set -euo pipefail` — строгий режим только в точках входа (скрипты, тесты),
  никогда внутри модулей `lib/` / `core/`.
- `load "lib/io/streams"` — путь относительно `BS_ROOT`, без `.sh`. Не
  подключайте модули фреймворка через `source` в новых скриптах.
- `io::streams::print` — безопасный вывод: обёртка над `printf '%s\n'`,
  которая не ломается на значениях вроде `-n` или `-e`. `BS_VERSION`
  задаёт ядро.

## Запуск скриптов

```bash
./bs run examples/hello.sh
./examples/hello.sh          # когда bs в PATH
```

Примеры со стартовой страницы:

```bash
./bs run examples/hello.sh     # короткий скрипт
./bs run examples/todo.sh      # TUI todo list (lib/tui)
./bs run examples/pulse.sh     # пульс возможностей машины
```

CLI на `core/args` (авто-help, валидация) — в
[туториале «Первый скрипт»](../05-tutorials/first-script.md).

## Куда идти дальше

- [Архитектура](../02-core-concepts/architecture.md) — стадии загрузки,
  `BS_ROOT`, загрузчик модулей
- [Модуль core/args](../03-modules/args.md) — деревья параметров, флаги,
  bash completion
- [Модуль lib/io/streams](../03-modules/io-streams.md) — безопасный вывод,
  перенаправления, pipe
- [Туториал: первый скрипт](../05-tutorials/first-script.md) — пошаговое
  руководство

См. также [README репозитория](../../../README.md) и рабочие примеры в
[examples/](../../../examples/).
