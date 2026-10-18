[↑ Оглавление](../README.md)

# Начало работы

## Что такое BS

**BS** — модульный фреймворк и стандартная библиотека на Bash. В его
состав входят загрузчик модулей, логирование, обработка ошибок,
декларативные параметры скриптов, абстракция потоков ввода/вывода и набор
системных модулей — всё в едином стиле кода и без единой внешней
зависимости.

Команду `bs` и скрипты на BS можно запускать из любой оболочки: bash, zsh,
dash, ash/busybox, sh, ksh, fish, nushell. Какой bash исполнит код и что
разрешено вашей оболочке, решает механизм tier — см.
[«Работа из любой оболочки»](#работа-из-любой-оболочки).

## Требования

- **bash 4.2+** где-то в `PATH`: на нём исполняется ядро (ярус `bash4`). Версии
  4.2 и 4.3 допускаются кодом, но CI проверяет с **4.4** (почти все платформы
  поставляют 4.4 и новее).
- Запускать `bs` и `install.sh` можно **из любой оболочки** (dash, ash, zsh, ksh,
  fish, nushell): пролог найдёт bash и перезапустится в нём. Модули `@shell
  posix` подключаются из bash, zsh, dash, ash, ksh, mksh напрямую (см. раздел
  «Как устроено ядро»); fish и nushell вызывают функции ядра через `bs call`.
  Подробнее — [«Работа из любой оболочки»](#работа-из-любой-оболочки).
- Linux (основная платформа; macOS поддерживается частично: системный bash там
  3.2, нужен bash 4.2+ из Homebrew)
- Termux (Android): первую строку скриптов подгоняет
  [`bs shebang`](#shebang-под-эту-машину).

Ничего больше не требуется: BS использует только встроенные команды
оболочки и стандартные системные утилиты.

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
добавляет `~/.local/bin` в `PATH` в rc-файл вашей оболочки (и в уже
существующие `~/.bashrc` / `~/.zshrc`; `--shell NAME` задаёт оболочку явно),
идемпотентно.
Помощники для настройки PATH:

```bash
./install.sh --local --path          # print the export snippet
./install.sh --local --update-path   # add to the rc file of your shell
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
- `bs doctor` также показывает строки `shell (host)` (какой bash исполняет
  BS), `shell (yours)` (ваша оболочка и её tier) и число модулей с
  аннотациями `@shell posix` / `@shell bash4`.
- `bs where` — где лежит эта копия BS, видна ли команда `bs` в `PATH`, и
  раздел «Оболочка»: хозяин, ваша оболочка (login и родительский процесс),
  tier.
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

## Работа из любой оболочки

Ядро и `lib/` написаны на bash 4.2+ (массивы, `[[ ]]`, `local -r`), но
запускать BS можно из любой оболочки. Код всегда исполняет найденный на
машине bash, а оболочка, из которой вы пришли, влияет только на настройку
`PATH`, подсказки и — в строгом режиме — на то, какие модули разрешены.

### Три оболочки

| Роль | Что это | Кто определяет |
|---|---|---|
| **хозяин (host)** | интерпретатор, который исполняет код BS | всегда bash 4.2+: тот, что запустил `bs`, либо найденный трамплином (`BS_HOST_BASH` главнее поиска) |
| **ваша оболочка** | где вы набираете команды; её rc-файл получает `PATH` | `BS_USER_SHELL`, иначе родительский процесс, иначе login-оболочка |
| **исходная оболочка** | оболочка, которая первой прочитала файл `bs` | трамплин экспортирует `BS_ORIGIN_SHELL`; без трамплина — `bash` |

### Схема запуска

```mermaid
flowchart TD
    U["Ваша оболочка<br/>bash · zsh · dash · ash · sh · ksh · fish · nu"]
    U -->|"bs команда"| E
    U -->|"./script.sh<br/>#!/usr/bin/env bs"| E
    U -->|"source bootstrap/init.sh"| SRC{"это bash 4.2+?"}
    SRC -->|да| K
    SRC -->|нет| SRCX["двуязычное сообщение<br/>вместо Bad substitution"]
    E["точка входа bs<br/>POSIX-пролог"] --> OK{"bs_shell_host_ok<br/>bash 4.2+ в обычном режиме?"}
    OK -->|да| K
    OK -->|"нет: dash, zsh, sh,<br/>bash 3.2, bash как sh"| T["bootstrap/trampoline.sh"]
    T --> F{"bs_shell_host_find<br/>BS_HOST_BASH → PATH →<br/>/usr/local/bin, /opt/homebrew/bin, …"}
    F -->|найден| X["exec найденного bash<br/>с тем же файлом и аргументами<br/>BS_ORIGIN_SHELL = исходная оболочка"]
    F -->|нет| N["tier unsupported:<br/>что установить, exit 1"]
    X --> K["ядро BS в bash 4.2+<br/>core/ загружается всегда"]
    K --> L["load lib/…"]
    L --> S{"--strict-shell или<br/>BS_SHELL_STRICT=1?"}
    S -->|нет| R["модуль загружен"]
    S -->|да| A{"@shell модуля разрешён<br/>для BS_ORIGIN_SHELL?"}
    A -->|да| R
    A -->|нет| D["отказ: модуль, tier, оболочка<br/>exit 1"]
```

В bash 4.2+ пролог — одна проверка, ничего не перезапускается. Повторный
заход в трамплин после `exec` считается сбоем и останавливается, поэтому
зациклиться запуск не может. Пошагово эти пути, а также `bs call`, POSIX-ярус
без bash, установка и обновление, — в разделе
[«Как устроено ядро: схемы UML»](#как-устроено-ядро-схемы-uml).

### Tier вашей оболочки

Ответ на вопрос «как BS работает именно у меня»:

| tier | смысл |
|---|---|
| `native` | ваша оболочка — bash 4.2+: работают и команды `bs`, и подключение библиотеки через `source` |
| `hosted` | другая оболочка: BS работает как команда `bs`, код исполняет найденный bash 4.2+; `PATH` и rc-файл настраиваются под вашу оболочку |
| `unsupported` | bash 4.2+ на машине нет: BS не запустится и подскажет, что установить |

Где посмотреть:

```bash
bs where                  # раздел «Оболочка»: хозяин, ваша оболочка, tier
bs doctor                 # строки shell (host) и shell (yours)
bs init-shell --list      # все известные оболочки: tier, rc-файл, перезагрузка
bs init-shell             # что добавить в rc-файл ВАШЕЙ оболочки
```

### Tier модуля: аннотация `@shell`

Каждый файл может объявить, на каком языке оболочки он написан, — строкой
`# @shell` в шапке, с двуязычной причиной после тире:

```bash
# @shell bash4 — нужны массивы и [[ ]] / needs arrays and [[ ]]
```

| tier модуля | разрешён из |
|---|---|
| `posix` | любой оболочки |
| `bash4` (по умолчанию, если аннотации нет) | bash 4.2+ |
| имя оболочки (`zsh`, `fish`, `nu`, …) | только этой оболочки |
| список через запятую (`zsh,bash4`) | любой из перечисленных |

Синонимы: `sh`, `shell`, `posix` = `posix`; `bash`, `bash4` = `bash4`;
`fs`, `fish` = `fish`; `nu`, `nushell` = `nu`.

Эта ось не связана с `@tier core | gnu-linux` — тот описывает нужный модулю
userland (утилиты), а `@shell` — язык файла.

### Строгое указание оболочки

По умолчанию трамплин даёт любой оболочке любой модуль: код всё равно
исполняет bash. Если нужно гарантировать, что скрипт использует только
модули, написанные для оболочки, из которой его запустили, включите строгий
режим:

```bash
dash ./bs --strict-shell run script.sh   # флаг ставится ДО команды
BS_SHELL_STRICT=1 dash ./bs run script.sh
```

Тогда модуль `lib/` загружается, только если его `@shell` разрешён для
исходной оболочки. Отказ называет модуль, его tier и оболочку и завершается
кодом 1:

```text
BS: модуль 'lib/io/streams' (@shell bash4) нельзя исполнять из оболочки 'dash' (--strict-shell)
```

Правила строгого режима:

- `core/` разрешён всегда — без ядра ничего не запустится.
- Исходная оболочка — та, что первой прочитала файл `bs`. bash, который
  дошёл до трамплина (bash 3.2 или bash в режиме POSIX), считается `sh`.
- Скрипт с `#!/usr/bin/env bs`, запущенный как `./script.sh`, всегда
  стартует через `#!/usr/bin/env bash` самого `bs`, поэтому его исходная
  оболочка — `bash`, из какой бы оболочки вы его ни вызвали. Флаг в шебанг
  не передать — используйте `BS_SHELL_STRICT=1`, а проверку по конкретной
  оболочке делайте запуском `<оболочка> ./bs --strict-shell run script.sh`.

### Вызов из fish и nushell: `bs call`

У fish и nushell другой синтаксис, подключить ядро в них нельзя. Функцию ядра
или модуля можно вызвать командой: она исполняется в bash, stdout, stderr и
код выхода — её.

```bash
bs call utils::human_size 1536000                  # 1.5 MiB
bs call --load lib/system/info system::info::os     # с загрузкой модуля
```

Из fish: `set size (bs call utils::human_size 1536000)`. Исполняется только
существующая функция с допустимым именем (иначе код 2 или 127); путь модуля —
только `core/...` или `lib/...`.

### Переменные, которые задают оболочку явно

| Переменная | Что задаёт |
|---|---|
| `BS_HOST_BASH=/path/to/bash` | какой bash берёт трамплин, когда BS запущен не из bash 4.2+; невалидное значение — ошибка, без тихого перехода к поиску |
| `BS_USER_SHELL=zsh` | вашу оболочку: от неё зависят rc-файл, строка `PATH` и tier |
| `BS_SHELL_STRICT=1` | строгий режим, то же, что `--strict-shell` |

### Shebang под эту машину

Шебанг требует абсолютного пути. На большинстве Linux это `/usr/bin/env`, а в
Termux каталога `/usr` нет. Команда `bs shebang` проверяет и переписывает
первую строку скриптов:

```bash
bs shebang info                 # где env на этой машине, какие режимы работают
bs shebang check examples/      # работает ли шебанг каждого файла здесь
bs shebang set --mode auto examples/   # переписать, где нужно
```

Режимы: `portable` (`#!/usr/bin/env bs`, для обмена), `env` (env этой
машины), `abs` (полный путь к `bs`), `auto` (по умолчанию: `portable`, если
есть `/usr/bin/env`, иначе `env`).

Подробности — в [«Переносимость между оболочками»](../08-development/shell-portability.md)
и [«Архитектура»](../02-core-concepts/architecture.md).

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
  D->>q: utils_has ls
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
