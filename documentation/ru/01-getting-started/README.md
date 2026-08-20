[↑ Оглавление](../README.md)

# Начало работы

## Что такое BS

**BS** — модульный фреймворк и стандартная библиотека для Bash 4+. В его
состав входят загрузчик модулей, логирование, обработка ошибок,
декларативные параметры скриптов, абстракция потоков ввода/вывода и набор
системных модулей — всё в едином стиле кода и без единой внешней
зависимости.

## Требования

- Bash 4.0+
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

## Первый скрипт за 5 строк

```bash
#!/usr/bin/env bs
load "core/args"
load "lib/io/streams"

args::define hello
args::require "$@"
io::streams::print "works: $(args::get 1)"
```

- `#!/usr/bin/env bs` — запускает скрипт через интерпретатор `bs`; ядро
  фреймворка загружается до вашего кода, bootstrap-бойлерплейт не нужен.
- `load "core/args"` — подключает модуль по пути относительно `BS_ROOT`, без
  расширения `.sh`. Не подключайте модули фреймворка через `source`.
- `args::define hello` — объявляет позиционный параметр: уровень 1 принимает
  только значение `hello`.
- `args::parse "$@"` — валидирует аргументы; при ошибке сам печатает причину
  и usage в stderr и возвращает ненулевой код. `-h` / `--help` обрабатывается
  автоматически.
- `io::streams::print` — безопасный вывод: обёртка над `printf '%s\n'`,
  которая не ломается на значениях вроде `-n` или `-e`. `args::get 1`
  возвращает первый провалидированный позиционный параметр.

## Запуск скриптов

```bash
# Via the bs command (also works from an uninstalled repository)
./bs run script.sh hello

# Directly, when bs is in PATH and the script is executable
chmod +x script.sh
./script.sh hello
```

Некорректный ввод отклоняется `args::parse`:

```text
$ ./bs run script.sh bye
ERROR: unknown parameter: "bye"
Usage: bash [hello]
```

Попробуйте встроенные примеры:

```bash
./bs run examples/argsparseexample.sh deploy now --env production --dry-run
./bs run examples/passwordgenexample.sh --length 24 --count 5
```

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
