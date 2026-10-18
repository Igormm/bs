[↑ Оглавление](../README.md)

# Начало работы

## Что такое BS

**BS** — модульный фреймворк и стандартная библиотека на **Bash 4.2+**. В его
состав входят загрузчик модулей, логирование, обработка ошибок,
декларативные параметры скриптов, абстракция потоков ввода/вывода и набор
системных модулей — всё в едином стиле кода и без единой внешней
зависимости.

## Требования

- **bash 4.2+ — обязательное требование.** На bash написаны вся библиотека `lib/`
  (87 модулей) и 6 из 15 файлов ядра `core/`, поэтому без bash BS не работает.
  Версии 4.2 и 4.3 допускаются кодом, но CI проверяет с **4.4** (почти все
  платформы поставляют 4.4 и новее).
- Исключение — 9 файлов ядра с меткой `@shell posix`: они не зависят от bash и
  подключаются из dash, ash, ksh, mksh, zsh и bash (см. раздел «Как устроено
  ядро»). Это небольшой набор помощников (константы, версия, `bs_utils_has`,
  `bs_log_info`, `calc` и др.), а не весь BS.
- Запускать `bs` и `install.sh` можно **из любой оболочки** (dash, ash, zsh, ksh,
  fish, nushell): пролог найдёт bash и перезапустится в нём, так что bash должен
  быть в системе, но не обязан быть вашей оболочкой.
- Linux (основная платформа; macOS поддерживается частично: системный bash там
  3.2, нужен bash 4.2+ из Homebrew)

Ничего больше не требуется: BS использует только встроенные команды bash и
стандартные системные утилиты.

**Курс на независимость от оболочки.** Цель — ядро (`bootstrap/`, `core/`, `install/`,
`boot.sh`, `bs`, `install.sh`) в одном пространстве имён `bs_*`, не зависящее от
оболочки (dash, ash, ksh, mksh, zsh, bash). Уже готово 9 из 15 файлов `core/`
(включая слой массивов и словарей `core/data.sh`) и слой оболочек в `bootstrap/`;
остальное переводится по плану (см. [shell-portability](../08-development/shell-portability.md#курс-на-независимость-от-оболочки)).
Вся библиотека `lib/` пока написана для bash 4.2+ (zsh разбирает 85 из 87 файлов,
но работа `lib/` в zsh не проверялась).

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
./bs version --full   # + where this copy is from
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

load "lib/io/streams"

io::streams::print "hello from BS $(bs::version::get)"
```

- `#!/usr/bin/env bs` — запускает скрипт через интерпретатор `bs`; ядро
  фреймворка загружается до вашего кода, bootstrap-бойлерплейт не нужен.
- `# shellcheck shell=bash` — обязательно на строке 2, если shebang — `bs`.
- Строгий режим уже включён интерпретатором (`set -euo pipefail` до source
  вашего скрипта) — строка здесь не нужна. Её ставят только обычные точки
  входа `#!/usr/bin/env bash` — через `utils::strict` (после загрузки ядра)
  или pre-kernel `bs::strict` из `bootstrap/bs.sh`.
- `load "lib/io/streams"` — путь относительно `BS_ROOT`, без `.sh`. Не
  подключайте модули фреймворка через `source` в новых скриптах.
- `io::streams::print` — безопасный вывод: обёртка над `printf '%s\n'`,
  которая не ломается на значениях вроде `-n` или `-e`. Версию отдаёт
  функция ядра `bs::version::get`.

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

## Как устроено ядро: схемы UML

Схемы ниже — в формате [Mermaid](https://mermaid.js.org/) (GitHub рисует их сам). Цвет несёт смысл: **бирюзовый** — ярус `@shell posix` (работает в любой оболочке), **фиолетовый** — ярус `@shell bash4` (нужен bash 4.2+), серый — точки входа. Сначала общая картина, затем шесть сценариев.

### Компоненты

```mermaid
flowchart TB
  classDef entry fill:#F1EFE8,stroke:#5F5E5A,color:#2C2C2A
  classDef posix fill:#E1F5EE,stroke:#0F6E56,color:#04342C
  classDef bash4 fill:#EEEDFE,stroke:#534AB7,color:#26215C
  subgraph E["entry points"]
    bs["bs"]:::entry
    boot["boot.sh"]:::entry
    inst["install.sh"]:::entry
  end
  subgraph P["bootstrap/ · POSIX"]
    shell["shell.sh<br/>shell registry"]:::posix
    tramp["trampoline.sh<br/>re-run in bash"]:::posix
    sheb["shebang.sh<br/>#! management"]:::posix
  end
  subgraph B["bootstrap/ · bash4"]
    bssh["bs.sh<br/>pre-kernel, bs::cli"]:::bash4
    init["init.sh"]:::bash4
    loader["loader.sh<br/>load, @depends"]:::bash4
  end
  subgraph C["core/"]
    direction TB
    subgraph CP["@shell posix"]
      prereq:::posix
      guard:::posix
      const:::posix
      version:::posix
      quiet:::posix
    end
    subgraph CB["@shell bash4"]
      lang:::bash4
      args:::bash4
      errorhandler:::bash4
      config:::bash4
      logger:::bash4
      utils:::bash4
      deps:::bash4
      calc:::bash4
      repl:::bash4
    end
  end
  bs -.-> shell
  boot -.-> shell
  inst -.-> shell
  shell -.-> tramp
  bs -.-> bssh
  bssh -.-> init
  init -.-> loader
  loader -.-> CP
  loader -.-> CB
  CB -.-> CP
  inst -.-> sheb
```

Стрелки — зависимости (кто кого подключает). Файлы `core/` внутри пакета загружает `init.sh`, в порядке сверху вниз.

### Сценарии

#### 1. `bs script.sh` или `#!/usr/bin/env bs` из bash 4.2+

![Сценарий 1: bs script.sh из bash 4.2+](../../assets/uml/scenario-1-ru.svg)

<details>
<summary>Текст диаграммы (Mermaid)</summary>

```mermaid
sequenceDiagram
  autonumber
  actor U as Пользователь
  participant bs as bs
  participant sh as shell.sh
  participant bsh as bs.sh
  participant init as init.sh
  participant core as core/*
  participant S as script.sh
  U->>bs: ./script.sh (через shebang запускается bs)
  bs->>sh: bs_shell_host_ok (пролог: оболочка годится?)
  sh-->>bs: да: bash ≥ 4.2, не режим POSIX
  bs->>bsh: source (bs::strict, bs::cli::*)
  bs->>init: source
  init->>core: load prereq, lang, const, logger, errorhandler, version, quiet, utils, config, deps
  init-->>bs: BS_INITIALIZED=1
  bs->>bs: BS_SHEBANG=1: первый аргумент — файл
  bs->>S: новый bash: init.sh, затем source скрипта
  S->>core: load "lib/..." по требованию
  S-->>U: выход: EXIT-trap, стек очистки (LIFO)
```

</details>

#### 2. Запуск из dash, ash или другой оболочки: перезапуск в bash

![Сценарий 2: запуск из dash — перезапуск в bash](../../assets/uml/scenario-2-ru.svg)

<details>
<summary>Текст диаграммы (Mermaid)</summary>

```mermaid
sequenceDiagram
  autonumber
  actor U as Пользователь
  participant d as dash ./bs
  participant sh as shell.sh
  participant tr as trampoline.sh
  participant b as bash 4.2+
  U->>d: dash ./bs version
  d->>sh: bs_shell_host_ok
  sh-->>d: нет: это dash
  d->>tr: source
  tr->>sh: bs_shell_host_find (ищет bash 4.2+: BS_HOST_BASH, PATH, типовые пути)
  alt bash 4.2+
    tr->>b: найден: exec bash тот же файл и аргументы
    Note over tr,b: BS_ORIGIN_SHELL=dash (для --strict-shell)
    b-->>U: продолжение как в сценарии 1
  else
    tr-->>U: не найден: сообщение, что установить (apk, apt, dnf, brew)
  end
```

</details>

#### 3. Вызов функции ядра из fish или nushell: `bs call`

![Сценарий 3: bs call из fish или nushell](../../assets/uml/scenario-3-ru.svg)

<details>
<summary>Текст диаграммы (Mermaid)</summary>

```mermaid
sequenceDiagram
  autonumber
  participant F as fish / nushell
  participant bs as bs call
  participant core as ядро загружено (как в сценарии 1)
  participant fn as FUNCTION
  F->>bs: bs call --load lib/system/info system::info::os
  bs->>core: ядро загружено (как в сценарии 1)
  bs->>bs: проверка: имя функции и путь модуля по шаблону
  alt ✗
    bs-->>F: неверно: код 2
  else
    bs->>core: --load: load модуля
    alt ✗ declare -F
      bs-->>F: функции нет: код 127
    else
      bs->>fn: run
      fn-->>F: stdout, stderr и код функции
    end
  end
```

</details>

#### 4. POSIX-ярус напрямую, без bash

![Сценарий 4: POSIX-ярус без bash](../../assets/uml/scenario-4-ru.svg)

<details>
<summary>Текст диаграммы (Mermaid)</summary>

```mermaid
sequenceDiagram
  autonumber
  participant D as скрипт на dash: подключает слой
  participant sh as shell.sh
  participant pre as prereq.sh
  participant q as quiet.sh
  D->>sh: . bootstrap/shell.sh
  D->>pre: . core/prereq.sh
  D->>q: . core/quiet.sh
  D->>q: bs_utils_has ls
  q-->>D: код 0 или 1; bash не запускался
```

</details>

#### 5. Установка: `./install.sh --local`

![Сценарий 5: установка](../../assets/uml/scenario-5-ru.svg)

<details>
<summary>Текст диаграммы (Mermaid)</summary>

```mermaid
sequenceDiagram
  autonumber
  actor U as Пользователь
  participant i as install.sh
  participant k as kernel
  participant a as install/actions.sh
  participant sb as shebang.sh
  participant fs as ~/.local/lib/bs
  U->>i: ./install.sh --local
  i->>k: пролог и ядро: как в сценарии 1 или 2
  i->>a: копия bootstrap, core, bs, lib в staging
  a->>sb: подгоняет #! под машину (Termux)
  a->>a: манифест .install и обёртка
  a->>fs: атомарный rename staging в ~/.local/lib/bs
  i-->>U: PATH для оболочки пользователя
```

</details>

#### 6. Обновление: `bs update`

![Сценарий 6: обновление](../../assets/uml/scenario-6-ru.svg)

<details>
<summary>Текст диаграммы (Mermaid)</summary>

```mermaid
sequenceDiagram
  autonumber
  actor U as Пользователь
  participant bs as bs update
  participant sb as shebang.sh
  participant t as копия источника во в…
  participant inst as installed bs
  U->>bs: bs update
  bs->>t: копия источника во временный каталог
  bs->>sb: shebang bs и обёртки под машину
  bs->>inst: обмен частей, старое в .update-old
  bs->>inst: smoke-test: bs version как программа
  alt ok
    bs-->>U: ок: манифест, чистка
  else
    bs-->>U: сбой: откат
  end
```

</details>


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
