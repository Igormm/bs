[↑ Оглавление](../README.md)

# Архитектура

BS — тонкий слой времени выполнения **поверх bash 4.2+**: на нём написаны вся
библиотека `lib/` (87 модулей) и команды `bootstrap/bs.sh`, которые её запускают. Исключение —
19 небольших файлов ядра `@shell posix`, которые работают в любой оболочке;
остальные оболочки попадают в BS через перезапуск в bash или `bs call`. Он состоит из двух
входных скриптов (`boot.sh`, `bs`) с общим POSIX-прологом, реестра оболочек
(`bootstrap/shell.sh`), инициализатора (`bootstrap/init.sh`),
загрузчика модулей (`bootstrap/loader.sh`), всегда загружаемых модулей `core/`
и подключаемых по требованию модулей `lib/`. Документ описывает, как части
связаны между собой и что происходит между shebang скрипта и его завершением.

## Общая схема загрузки

Схема читается сверху вниз. Три слоя: **POSIX-пролог** (работает в любой
оболочке), **стадии 1–2** (`boot.sh`, `bs` — POSIX: все команды в bash 4.2+, в остальных оболочках POSIX-часть) и **ядро**
(`bootstrap/init.sh` → `bootstrap/loader.sh` → `core/*`).

```
 кто-то запускает:  ./boot.sh <script>   bs <cmd>   #!/usr/bin/env bs   sh install.sh
                    (из bash, zsh, dash, sh, ...: оболочка пользователя неважна)
                                          │
                                          ▼
 ┌─ POSIX-ПРОЛОГ: первые строки bs, boot.sh, install.sh ───────────────────────┐
 │  · запомнить $0 (zsh меняет $0 внутри подключаемого файла)                   │
 │  · readlink -f → BS_ENTRY_DIR (каталог точки входа, ссылки раскрыты)         │
 │  · . bootstrap/shell.sh          реестр оболочек, чистый POSIX               │
 │  · bs_shell_host_ok ?  (это bash 4.2+ в обычном режиме)                      │
 │        да ───────────────────────────────► дальше, ничего не стоит          │
 │        нет ─► . bootstrap/trampoline.sh                                      │
 │                 · защита от цикла: __BS_TRAMPOLINE                           │
 │                 · BS_HOST_BASH или bs_shell_host_find ищет bash 4.2+         │
 │                 · найден  → exec bash <этот же файл> <те же аргументы>       │
 │                             (BS_ORIGIN_SHELL помнит исходную оболочку)       │
 │                 · не найден → двуязычное сообщение «что установить», exit 1  │
 └───────────────────────────────────────────────────────────────────────────────┘
                                          │ (теперь мы в bash 4.2+)
              ┌───────────────────────────┴───────────────────────────┐
              ▼                                                       ▼
   stage-1: boot.sh                                          stage-2: bs
    · . bootstrap/base.sh (pre-kernel, POSIX)                 (boot.sh делает exec сюда)
    · bs_strict                                                      │
    · BS_ROOT: env → рядом с boot.sh →                               ▼
      ~/.local/lib/bs → /usr/local/lib/bs        · BS_CALLER_PATH = PATH вызвавшего
      (не найден → exit 2)                       · source bootstrap/bs.sh:
    · exec "$BS_ROOT/bs" "$@" ─────────────────►     bs::cli::*, bs::shell::*, bs::is_main
                                                 · bs::strict (версию проверил пролог)
                                                 · BS_ROOT (свой каталог → ~/.local/lib/bs
                                                   → $BS_SYSTEM_PREFIX/lib/bs), BS_HOME,
                                                   BS_SILENT=1
                                                 · unset BS_INITIALIZED
                                                 · source bootstrap/init.sh ──┐
                                                 · errorhandler::setup_trap   │ (ниже)
                                                 · --strict-shell → BS_SHELL_STRICT=1
                                                          │
                       ┌──────────────────────────────────┴───────────────┐
                       ▼                                                  ▼
              CLI-диспетчер                                      shebang-режим
              help version env list doctor run                   первый аргумент — файл,
              build init-shell shebang update                    не команда → BS_SHEBANG=1
              uninstall where ... → bs::cli::*_cmd                        │
                                                                          ▼
                                                    bs::cli::run_cmd: exec новый bash
                                                     · BS_RUN_SCRIPT=<script>
                                                     · unset BS_INITIALIZED
                                                     · source bootstrap/init.sh
                                                     · bs::strict
                                                     · source <script> [args]
                                                                          │
                                                                          ▼
                                                              ваш скрипт выполняется
                                                              load "core/args" ...
                                                                          │
                                                                          ▼
                                       exit → EXIT-trap → cleanup::__run_all (LIFO)
```

### Ядро: что делает `bootstrap/init.sh`

```
 source bootstrap/init.sh
   │
   ├─ BS_BOOTSTRAP_DIR (bash: путь файла; zsh: %x; остальные: BS_ENTRY_DIR / BS_ROOT)
   ├─ source bootstrap/base.sh  (pre-kernel, POSIX); в bash ещё bootstrap/bs.sh
   ├─ уже BS_INITIALIZED и есть bs::guard? → return 0   (идемпотентность)
   ├─ BS_ROOT (задан, иначе родитель bootstrap/ с файлом bs)
   ├─ BS_KERNEL_MODE: full (bash 4.2+) или posix (dash, ash, ksh, mksh, zsh); bash старше 4.2 отклоняется
   ├─ bs::append_local_bin_to_path   (~/.local/bin в PATH этого процесса)
   ├─ source bootstrap/kernel.sh      (posix: тот же файл подключают dash, ash, ksh, mksh, zsh)
   │    ├─ BS_HOME (по умолчанию BS_ROOT); появляется загрузчик → bs_load (load и bs::load в bash и zsh)
   │    ├─ load core/prereq первым (bs_guard, bs_source_relative), затем lang, const, var, str, num, msg,
   │    │  logger, quiet, fmt, data, errorhandler, version, utils, config, deps, args   (17 модулей)
   │    └─ bs_config_load      конфигурация из файлов и окружения
   ├─ load lib/compat/deps, lib/compat/lang, lib/compat/args   (только режим full) deps::missing_tools, str::*, arr::*, map::*, ARGS_*
   └─ BS_INITIALIZED=1
```

### Загрузчик: что делает `load "lib/group/module"`

```
 load "lib/io/streams"
   │
   ├─ BS_ROOT задан и это каталог?            нет → ошибка, return 1
   ├─ уже загружен (bs_load_is_loaded)?                да  → return 0
   ├─ --strict-shell: @shell-tier модуля подходит BS_ORIGIN_SHELL?   нет → отказ
   ├─ модуль уже в стеке загрузки?             да  → circular dependency, return 1
   ├─ push в стек загрузки
   ├─ для каждой зависимости из «# @depends» → load (рекурсивно); сбой → return 1
   ├─ BS_CURRENT_FILE=<файл>; source ${BS_ROOT}/lib/io/streams.sh
   ├─ pop из стека загрузки (и при ошибке тоже)
   └─ путь — в реестр загруженных модулей
```

## Ядро по ярусам: что доступно всем оболочкам

Ядро не «только bash» и не «только POSIX»: каждый файл `core/` несёт метку
`# @shell posix` или `# @shell bash4`, и от неё зависит, где он работает. Метки
проверяет `bash .agents/skills/bs-shell-portability/scripts/tier_scan.sh`; что
реально запускалось — таблица приоритетов в
[shell-portability](../08-development/shell-portability.md).

| Ярус | Файлы `core/` | Где работает напрямую | Как попадают остальные оболочки |
|---|---|---|---|
| `posix` (19) | `prereq`, `guard`, `const`, `version`, `quiet`, `fmt`, `logger`, `calc`, `data`, `utils`, `deps`, `errorhandler`, `config`, `lang`, `args`, `var`, `str`, `num`, `msg` | bash, zsh, dash, busybox ash, ksh93, mksh (проверено запуском) | — (подключаются сами) |
| `bash4` (87) | **вся `lib/`**, все модули | только bash 4.2+ (ни один модуль `lib/` не POSIX) | точка входа находит bash и перезапускается в нём (трамплин); функции ядра — командой `bs call` |

Ни один файл `core/` больше не `bash4`: `repl` вынесен в `lib/ui/repl`, а то, что требует настоящих массивов bash (остальной `lang`, `deps::missing_tools`, `ARGS_PARAMS`/`ARGS_FLAGS`/`ARGS_REST` для `args::parse`), живёт в мостах `lib/compat/lang`, `lib/compat/deps` и `lib/compat/args` вне ядра.

Что делает «доступным всем»:

1. **Любая оболочка запускает `bs` и скрипты с `#!/usr/bin/env bs`**: пролог точки
   входа написан на POSIX, при необходимости перезапускает файл в bash 4.2+.
2. **POSIX-ярус подключается напрямую** из bash, zsh, dash, ash, ksh, mksh:
   константы, версия, `bs_utils_has`/`bs_utils_quiet` и др., реестр оболочек
   (`bootstrap/shell.sh`), управление шебангом (`bootstrap/shebang.sh`).
3. **Мост `bs call [--load МОДУЛЬ] ФУНКЦИЯ [АРГУМЕНТЫ]`** вызывает любую функцию
   ядра из fish, nushell и прочих оболочек с другим синтаксисом; функция
   исполняется в bash, вывод и код выхода возвращаются вызывающему.

Чего ядро **не** обещает: исполнять `lib/`, мосты `lib/compat/*` и команды
`bootstrap/bs.sh` (файлы яруса `bash4`) в dash, ash, ksh, mksh, fish или nushell. В них нужны
ассоциативные массивы, nameref и `=~` с `BASH_REMATCH`, которых нет или которые
ведут себя иначе. Оболочки без настоящего запуска (nushell, oksh, osh) не
считаются проверенными. Все 19 файлов `core/` теперь `posix`; переводились по одному (`calc`, `quiet`, `fmt`, `logger`, `data`,
`utils`, `deps`, `errorhandler`, `config` (его ассоциативный массив `BS_CONFIG` стал словарём слоя данных `bs_config`), `lang` (предикаты `bs_is_*`), `args` (дерево, флаги и результат разбора лежат в слое данных; массивы bash `ARGS_PARAMS`, `ARGS_FLAGS`, `ARGS_REST` заполняет `lib/compat/args`) и новые базовые модули `var`, `str`, `num`, `msg`); остальные языковые примитивы bash (`str::*`, `arr::*`, `map::*`, интроспекция) вынесены из `lang` в `lib/compat/lang`; `repl` вне ядра.

## Стадия 0: POSIX-пролог и `trampoline`

Точки входа (`bs`, `boot.sh`, `install.sh`) начинаются с одинакового короткого
пролога, который разбирает любая оболочка (dash, ash, zsh, ksh, bash). Без него
`sh install.sh`, `dash ./bs` или bash 3.2 упали бы с «Bad substitution» ещё до
первой полезной строки.

| Что | Где | Зачем |
|---|---|---|
| `BS_ENTRY_DIR` | пролог | каталог точки входа со снятыми символическими ссылками; от него считаются `BS_ROOT`, `bootstrap/` |
| `bootstrap/shell.sh` | реестр оболочек | POSIX-ответы: какая это оболочка, годится ли в хозяева (`bs_shell_host_ok`), где искать bash 4.2+ (`bs_shell_host_find`), tier |
| `bootstrap/trampoline.sh` | перезапуск | `exec` в найденный bash с теми же файлом и аргументами; иначе сообщение, что установить |
| `BS_HOST_BASH` | окружение | принудительно указать bash для перезапуска |
| `BS_ORIGIN_SHELL` | окружение | оболочка, из которой запустили; нужна `--strict-shell` |
| `__BS_TRAMPOLINE` | окружение | защита от зацикливания перезапуска |

В bash 4.2+ в обычном режиме пролог — одна проверка и ничего не перезапускает.
Подробнее о tier'ах `@shell posix|bash4` и оболочках — в
[shell-portability](../08-development/shell-portability.md).

## Стадия 1: `boot.sh`

[boot.sh](../../../boot.sh) — минимальный предзагрузчик, единственная задача
которого — проверить среду и как можно быстрее передать управление `bs`:

1. **Pre-kernel namespace.** Подключает `bootstrap/base.sh` — POSIX-файл без
   зависимостей — и включает строгий режим (`bs_strict`). Оболочку уже
   рассмотрел POSIX-пролог (`bs_shell_host_ok`): есть bash 4.2+ — перезапуск в
   нём (трамплин), нет — `boot.sh` продолжает в текущей оболочке
   (`BS_POSIX_ENTRY=1`), а что можно выполнить там, решает `bs`.
2. **Поиск BS_ROOT** в порядке приоритета:
   - уже экспортированный `BS_ROOT`;
   - каталог, где лежит сам `boot.sh`, если рядом есть `bs` и
     `bootstrap/init.sh` (клон репозитория);
   - префиксы `~/.local/lib/bs` и `/usr/local/lib/bs` (установленные копии).

   Если ничего не найдено — выход с кодом `2`. Тот же код используется, когда
   `${BS_ROOT}/bs` отсутствует или не исполняемый.
3. **Передача управления.** `exec "${BS_ROOT}/bs" "$@"` заменяет процесс,
   поэтому все аргументы и стандартные потоки попадают на стадию 2 без
   изменений.

Коды выхода: `0` — `bs` успешно запущен; `1` — не найден `bootstrap/base.sh`;
`2` — фреймворк не найден.

## Стадия 2: `bs` — CLI и shebang-интерпретатор

Скрипт [bs](../../../bs) — единая точка входа. Он начинается с POSIX-пролога
(см. схему), затем включает строгий режим через `bs::strict` и выполняет
следующее:

- Берёт свой каталог из `BS_ENTRY_DIR` (его задал пролог), подключает `bootstrap/bs.sh` (pre-kernel
  namespace) и включает `bs::strict`. Гейт bash 4.2+ уже сработал в
  прологе (`bs_shell_host_ok`) — до загрузки чего-либо ещё. Он относится к ярусу `bash4` (так
  запускается ядро); модули `@shell posix` и мост `bs call` его не требуют.
- Подключает `BS_VERSION` из `core/version.sh` (сейчас `0.9.0`); собственного номера у `const.sh` нет.
- Определяет `BS_ROOT`, если тот ещё не задан: сначала каталог самого скрипта
  (если в нём есть `bootstrap/init.sh`), затем `~/.local/lib/bs` и
  `/usr/local/lib/bs`.
- Экспортирует `BS_HOME`, по умолчанию равный `BS_ROOT` (исторический псевдоним,
  используемый частью модулей `lib/`), и `BS_SILENT`, по умолчанию `1`, —
  чтобы загрузка ядра не шумела и не засоряла вывод скрипта.
- Подключает [bootstrap/init.sh](../../../bootstrap/init.sh), который
  загружает ядро (см. ниже).
- Устанавливает EXIT-trap через `errorhandler::setup_trap`, чтобы при выходе
  выполнялся стек очистки (см. `cleanup::add` в
  [core/errorhandler.sh](../../../core/errorhandler.sh)).

После инициализации `bs` выбирает один из двух режимов:

- **Shebang-режим.** Если первый аргумент — путь к существующему файлу и не
  совпадает ни с одной из CLI-команд, выставляется `BS_SHEBANG=1`, и файл
  выполняется через `run_cmd`. Именно так работает `#!/usr/bin/env bs`.
- **CLI-режим.** Иначе первый аргумент диспетчеризуется как команда:
  `help`, `version`, `env`, `list`, `doctor`, `run <script> [args]`, `build`,
  `init-shell`, `shebang`, `update`, `uninstall`, `where` и др. (полный список —
  `bs help`); сами команды живут в `bootstrap/bs.sh` как `bs::cli::*`.

`run_cmd` (используется и командой `bs run`) выполняет целевой скрипт в
**новом процессе bash**: сбрасывает унаследованный `BS_INITIALIZED`, заново
подключает `bootstrap/init.sh` (чтобы скрипт получил свежее полностью
инициализированное окружение) и затем делает `source` скрипта с его
аргументами.

## `bootstrap/init.sh` — инициализация ядра

[bootstrap/init.sh](../../../bootstrap/init.sh) должен **подключаться через
source**, а не запускаться (при прямом запуске он отказывается работать). Он
не включает строгий режим и не меняет `IFS` вызывающего — это ответственность
точек входа. Шаги:

1. **Идемпотентность.** Если `BS_INITIALIZED` уже установлен, выполняется
   немедленный `return 0` (с заметкой `log::debug`, если логгер доступен).
   Это делает повторные `source bootstrap/init.sh` безопасными.
2. **Определение BS_ROOT.** Если `BS_ROOT` не задан или недействителен, он
   выводится из расположения самого файла (родитель `bootstrap/`), что
   проверяется наличием скрипта `bs`. При неудаче инициализация прерывается
   с ошибкой и просьбой задать `BS_ROOT` вручную.
3. **Pre-kernel namespace и режим ядра.** Подключает `bootstrap/base.sh`
   (POSIX: `bs_strict`, `bs_append_local_bin_to_path`, `bs_shell_*`) и, в bash,
   `bootstrap/bs.sh`. Затем выбирает `BS_KERNEL_MODE`: `full` в bash 4.2+,
   `posix` в остальных оболочках (16 POSIX-модулей, без мостов), а bash
   старше 4.2 отклоняет (`bs_shell_ensure_version`) — рантайм-детект через реестр
   оболочек, никогда не `$SHELL` (логин-оболочка врёт при source из другой оболочки).
4. **Твик PATH.** `~/.local/bin` добавляется в начало `PATH` один раз
   (`bs_append_local_bin_to_path`), что покрывает локальные установки.
5. **BS_HOME.** По умолчанию равен `BS_ROOT`, если не задан.
6. **Loader.** Подключает `bootstrap/loader.sh` (с фолбэком на
   `${BS_ROOT}/loader.sh`). Loader тоже подключает `bootstrap/bs.sh` для
   прямых пользователей, так что `bs::shell::*` и другие хелперы доступны
   всегда.
7. **Модули ядра**, загружаемые через `load` в фиксированном порядке:
   - `core/prereq` — первым: базовые примитивы `bs::guard`,
      `bs::guard_loaded` и `bs::source_relative`, доступные априори всем
      остальным модулям (модули не подключают `prereq.sh` вручную);
      хелперы определения оболочки, жившие здесь ранее, теперь в
      `bootstrap/bs.sh`;
   - `core/lang` — `@shell posix`: предикаты `bs_is_empty`, `bs_is_file`,
     `bs_is_dir`, `bs_is_number`, `bs_is_command`, … (`is::*` — псевдонимы в bash
     и zsh). Интроспекция (`bs::func_name`, `bs::call_stack`, `bs::type_of`),
     строки (`str::*`) и коллекции (`arr::*`, `map::*`) вынесены в мост
     `lib/compat/lang`, который `init.sh` грузит в bash;
   - `core/const` — коды ошибок (`E_SUCCESS`, `E_ERROR`, `LIB_ERROR_*`),
     цветовые константы, флаги фреймворка (`FRAMEWORK_DEBUG`,
     `FRAMEWORK_DRY_RUN`);
   - `core/logger` — семейство `log::` (`log::info`, `log::warn`,
     `log::error`, …); `@shell posix`: настоящие функции `bs_log_info`, `bs_log_warn`, …,
     `log::*` — их псевдонимы в bash и zsh;
   - `core/errorhandler` — `errorhandler::throw`, `errorhandler::setup_trap`,
     стек очистки (`cleanup::add`) и помощники выхода (`bs::exit`,
     `error::exit`);
   - `core/version` — экспорт `BS_VERSION` / `BS_NAME` и помощники
     `bs::version::*`;
   - `core/quiet` (`@shell posix`) — идиомы тишины `utils::has`,
     `utils::quiet`, `utils::quiet_err`, `utils::ignore`, `utils::attempt`
     (замены для `command -v … >/dev/null 2>&1`, `>/dev/null 2>&1`,
     `2>/dev/null`, `>/dev/null 2>&1 || true` и `2>/dev/null || true`
     соответственно); настоящие имена `bs_utils_has`, `bs_utils_quiet`, …;
   - `core/fmt` (`@shell posix`) — размеры и метки времени: `utils::human_size`,
     `utils::head_bytes`, `utils::now_s`, `utils::now_ms`, `utils::now_float`,
     `utils::stamp`, `utils::log_stamp` (настоящие имена `fmt_*`);
   - `core/data` (`@shell posix`) — массивы и словари для оболочек, где их нет:
     `bs_arr_*`, `bs_map_*`, `bs_quote` (на переменных и `eval`, ключ любого вида);
   - `core/utils` — остальные помощники среды (`utils::tempfile`, `utils::split`,
     `utils::ensure_source`, …);
   - `core/config` — единый загрузчик конфигурации (`config::load`,
     `config::get`, `config::set`);
   - `core/deps` — разбор зависимостей модулей (`# @depends`).

Файл [core/guard.sh](../../../core/guard.sh) сохранён как
обратносовместимая обёртка над [core/prereq.sh](../../../core/prereq.sh).
8. **Маркер.** Экспортируется `BS_INITIALIZED=1`. Если `BS_SILENT` не равен
   `1`, выводится путь, откуда выполнен bootstrap.

Так как `core/utils` загружается всегда, любой BS-скрипт может пользоваться
`utils::has`/`utils::quiet` и остальными без явного `load`.

## Загрузчик модулей: `bootstrap/loader.sh`

[bootstrap/loader.sh](../../../bootstrap/loader.sh) предоставляет одну
публичную функцию:

```bash
load "core/args"        # подключает ${BS_ROOT}/core/args.sh
load "lib/io/streams"   # подключает ${BS_ROOT}/lib/io/streams.sh
```

`load` принимает путь **относительно `BS_ROOT` без расширения `.sh`** и делает
`source` соответствующего файла. Внутренние механизмы:

- **Защита от повторной загрузки.** Загруженные модули фиксируются в
  строке `__bs_ld_loaded` (по модулю на строку; был массивом bash `BS_LOADED_MODULES` — загрузчик работает до `core/data.sh` и слоем данных не пользуется; спрашивать через `bs_load_is_loaded`); повторный `load` того же модуля —
  холостая операция, возвращающая `0`.
- **Обнаружение циклов.** Модули, находящиеся в процессе загрузки, хранятся в
  строке `__bs_ld_stack` (был `BS_LOAD_STACK`; глубину даёт `bs_load_stack_size`). Если модуль запрашивается, пока он уже есть в
  стеке, загрузка завершается ошибкой `circular dependency detected` с полной
  цепочкой. Элемент стека удаляется в любом случае, включая ошибку.
- **Директива `# @depends`.** Перед подключением модуля загрузчик ищет в его
  файле первую строку комментария с `@depends`, например:

  ```bash
  # @depends core/logger, lib/system/utils
  ```

  Каждая перечисленная зависимость рекурсивно загружается первой; ошибка
  зависимости прерывает всю загрузку. Список может разделяться запятыми и/или
  пробелами и разбирается с локальным `IFS=' '` независимо от `IFS`
  вызывающего.
- **Обработка ошибок.** Отсутствующий `BS_ROOT`, несуществующий файл модуля
  или неудачный `source` дают диагностику в stderr и ненулевой код возврата —
  `load` никогда не делает `exit` за вызывающего.
- **Псевдоним.** `bs::load` сохранён для обратной совместимости и просто
  делегирует в `load`.

Заметьте: `load` — это обычный `source` с учётом состояния, файлы модулей
выполняются в shell вызывающего, поэтому всё определённое ими доступно
напрямую.

## Жизненный цикл скрипта: от shebang до выхода

Типичный BS-скрипт выглядит так:

```bash
#!/usr/bin/env bs

load "core/args"
load "lib/io/streams"

# ... логика скрипта ...
```

По шагам:

1. Ядро ОС запускает `bs` с путём к скрипту в первом аргументе.
2. `bs` обнаруживает shebang-режим (`BS_SHEBANG=1`) и вызывает `run_cmd`.
3. `run_cmd` порождает чистый bash, сбрасывает `BS_INITIALIZED`, подключает
   `bootstrap/init.sh` (полная загрузка ядра) и затем подключает скрипт.
4. Скрипт подтягивает дополнительные модули через `load`. Уже загруженные
   модули ничего не стоят благодаря реестру загруженных модулей.
5. Во время работы скрипт может регистрировать функции очистки через
   `cleanup::add <fn>`.
6. При выходе — обычном, через `bs::exit [code]` или через
   `error::exit "msg" [code]` — EXIT-trap, установленный
   `errorhandler::setup_trap`, запускает `cleanup::__run_all`, который
   выполняет стек в порядке LIFO и очищает его.

Альтернатива — ручное встраивание в обычный bash-скрипт (полезно, когда
shebang контролировать нельзя):

```bash
#!/usr/bin/env bash
set -euo pipefail

source "${BS_ROOT:-$HOME/.local/lib/bs}/bootstrap/init.sh"
errorhandler::setup_trap   # опционально: стек очистки при выходе

load "lib/io/streams"
```

`init.sh` определяет `BS_ROOT` по собственному пути, поэтому достаточно
подключить его по абсолютному пути — предварительные экспорты не нужны.

## Соглашение: `core/` против `lib/`

| | `core/` | `lib/` |
|---|---|---|
| Загрузка | всегда, из `bootstrap/init.sh` | по требованию, через `load` |
| Структура | плоская (`core/logger.sh`) | группировка по подкаталогам (`lib/io/streams.sh`, `lib/system/info.sh`, …) |
| Роль | рантайм, нужный самому фреймворку: константы, логирование, обработка ошибок, версия, утилиты, разбор аргументов | предметная функциональность: потоки ввода-вывода, системная информация, UI, сеть, данные, статус, … |
| Контракт стабильности | можно опираться в любом BS-скрипте | подключать явно; следить за `# @depends` |

Практические правила:

- Никогда не подключайте файлы `lib/...` или `core/...` напрямую через
  `source` — всегда используйте `load`, чтобы работали разрешение зависимостей
  и защита от повторов.
- Помещайте новый механизм в `core/`, только если `bootstrap/init.sh` должен
  загружать его безусловно; всё остальное относится к `lib/<область>/`.
- Файлы модулей несут shebang `#!/usr/bin/env bs` как маркер, но
  предназначены для загрузки через `load`, а не для прямого запуска.

## См. также

- [core/errorhandler.sh](../../../core/errorhandler.sh) — стек очистки и помощники выхода
- [core/utils.sh](../../../core/utils.sh) — `utils::has`, `utils::quiet` и другие помощники среды
- [examples/](../../../examples) — исполняемые скрипты, использующие описанные шаблоны
