[↑ Руководство разработчика](README.md)

# Переносимость между оболочками

**BS требует bash 4.2+.** На bash написаны вся `lib/` (87 модулей, ни один не POSIX) и команды
`bootstrap/bs.sh`, которые её запускают; от bash не зависят только 19 небольших файлов ядра `@shell posix` (весь `core/`) и пролог точек
входа. «Работает из большинства оболочек» значит: `bs` можно запустить из любой оболочки (он
перезапускается в bash), а `install.sh` работает даже без bash вообще (dash, ash, ksh, mksh, zsh; см.
«Установщик и `init.sh` без bash» ниже); функции ядра вызываются из любой оболочки через `bs call`, а
POSIX-файлы подключаются напрямую. Эта
страница — дизайн ветки `fix/kernel-security-p0`; рабочие правила для авторов
— в скилле `.agents/skills/bs-shell-portability/SKILL.md`.

## Три оболочки, а не одна

| Роль | Смысл | Кто определяет |
|---|---|---|
| **host** | интерпретатор, исполняющий код BS | всегда bash ≥ 4.2 (находит трамплин) |
| **оболочка пользователя** | где человек набирает команды; чей rc-файл получает PATH | `--shell`, `BS_USER_SHELL`, родительский процесс, логин-оболочка |
| **оболочка скрипта** | шебанг пользовательского скрипта (`#!/usr/bin/env bs`) | скрипт |

Ядру и `lib/` нужны массивы, namerefs, `[[ ]]`, `local -r`; они остаются
bash. От оболочки освобождено всё *вокруг*: точки входа, установщик, настройка
PATH, проверки, удаление, `bs where`.

## Режимы доступа

- **exec** — `bs ...` из любой оболочки. Точка входа начинается с
  POSIX-пролога; если интерпретатор — не bash ≥ 4 (или bash в режиме POSIX),
  подключается `bootstrap/trampoline.sh`: он находит подходящий bash и делает
  `exec` того же файла с теми же аргументами.
- **source** — `source bootstrap/init.sh`. Только bash 4.2+. В других
  оболочках — двуязычное сообщение вместо `Bad substitution`.
- **call** — `bs call [--load МОДУЛЬ] ФУНКЦИЯ [АРГУМЕНТЫ]`: мост для оболочек с
  другим синтаксисом (fish, nushell, dash, ash, ksh). Функция ядра или модуля
  исполняется в bash, который запускает `bs`; её stdout и stderr — ваши, код
  выхода функции становится кодом `bs call`. Исполняется только существующая
  функция с допустимым именем (`rm`, `a;b`, `$(id)` отвергаются), путь модуля —
  только `core/...` или `lib/...` без `..`. Пример: `bs call utils::human_size
  1536000`; из fish: `set size (bs call utils::human_size 1536000)`.
- **trampoline** — механизм первого режима. `BS_HOST_BASH=/path`
  переопределяет поиск (невалидное значение — ошибка, без тихого fallback).
  Если bash 4.2+ нет — подсказки по установке (apk/apt/dnf/brew) и код 1.

## Tier-ы

Две независимые оси:

- `@tier core | gnu-linux` — какой *userland* нужен модулю (без изменений).
- `@shell posix | bash4` — на каком *языке* написан файл. Отсутствие = `bash4`.
  После тире — двуязычная причина:
  `# @shell bash4 — используются массивы и [[ ]]`.

Итог для пользователя — `platform::get shell_tier`:

| tier | смысл |
|---|---|
| `native` | оболочка пользователя — bash 4.2+; BS можно подключать через source |
| `hosted` | другая оболочка; BS работает командой `bs`, исполняемой найденным bash |
| `unsupported` | на машине нет bash 4.2+ |

Неустранимая зависимость не скрывается: модуль помечен `bash4` и объясняет
причину в аннотации.

## Реестр оболочек — `bootstrap/shell.sh`

POSIX-код. Функции называются `bs_shell_*` (dash не принимает `::` в именах);
алиасы `bs::shell::*` создаются через `eval` только в bash/zsh. Знает семейства
`bash zsh dash ash sh ksh mksh oksh osh fish nu` и отвечает: `family`, `user`,
`rc_file`, `path_line`, `reload_hint`, `fresh_flags`, `all_rc_files`,
`host_find`, `tier`, `tier_desc`.

| оболочка | rc-файл | строка PATH |
|---|---|---|
| bash | `~/.bashrc` | `export PATH="$HOME/.local/bin:$PATH"` |
| zsh | `${ZDOTDIR:-~}/.zshrc` | та же |
| dash, ash, sh, ksh, mksh, oksh | `~/.profile` | та же |
| osh | `~/.config/oils/oshrc` | та же |
| fish | `~/.config/fish/conf.d/bs.fish` | `contains -- … $PATH; or set -gx PATH …` |
| nu | `~/.config/nushell/env.nu` | `$env.PATH = ($env.PATH \| prepend …)` |

nushell: если `env.nu` нет, установщик его не создаёт, а печатает точную
строку для добавления.

## Строгий режим — `bs --strict-shell`

По умолчанию трамплин даёт любой оболочке любой модуль (код всегда исполняется
в bash). `--strict-shell` (или `BS_SHELL_STRICT=1`, нужен для shebang-режима)
делает tier `@shell` обязательным: модуль `lib/` загружается, только если его
tier подходит оболочке, из которой BS **запущен** (`BS_ORIGIN_SHELL`, её
экспортирует трамплин; bash, дошедший до трамплина, считается `sh`).

| tier модуля | разрешён из |
|---|---|
| `posix` | любой оболочки |
| `bash4` (по умолчанию) | bash 4.2+ |
| другое слово (`zsh`, `fish`, `nu`, …) | оболочки с этим именем |
| список `zsh,bash4` | любой из них |

Синонимы (слова tier и имена оболочек): `sh`, `shell`, `posix` = `posix`; `bash`, `bash4` = `bash4`; `fs`, `fish` = `fish`; `nu`, `nushell` = `nu`. Неизвестное слово остаётся как есть.

`core/` (ядро) разрешено всегда, иначе ничего не запустится. Отказ называет
модуль, его tier и исходную оболочку и завершается кодом 1:

```bash
dash ./bs --strict-shell run script.sh   # модуль lib/io/streams (@shell bash4) нельзя исполнять из 'dash'
```

**Параметр: указать оболочку.** `--strict-shell=ОБОЛОЧКА` (или `--strict-shell ОБОЛОЧКА`, если слово — известное имя оболочки) проверяет tier против **указанной** оболочки, где бы ни запустили `bs`: это ответ на вопрос «заработает ли это в dash». Имя — одно из `bash zsh ash dash sh ksh mksh oksh osh fish nu`; неизвестное имя — ошибка. Без имени поведение прежнее: проверка против оболочки запуска.

```bash
bs --strict-shell=dash run script.sh   # откажет, если скрипту нужен модуль @shell bash4
bs --strict-shell=bash run script.sh   # bash 4.2+ допускает всё
./install.sh --local --strict-shell=zsh   # ставить для zsh: PATH и rc под zsh; отказ, если на машине нет bash 4.2+
```

Установщик понимает ту же опцию как оболочку, **для которой ставится** BS (то же, что `--shell ОБОЛОЧКА`, но с отказом для tier `unsupported`).

## Где можно проверять оболочку

Только в слое абстракции: `bootstrap/bs.sh`, `bootstrap/shell.sh`, `bootstrap/trampoline.sh`. Везде в другом месте прямое использование `BASH_SOURCE`, `BASH_VERSION`, `FUNCNAME`, `ZSH_*`, `$SHELL`, `$0` как пути должно либо звать слой (`bs::is_main`, `bs::script_dir`, `bs::func_name`, `bs::stack_*`, `bs_shell_host_ok`), либо нести тег `shell-gate` с причиной. Проверяет `.agents/skills/bs-shell-abstraction/scripts/find_leaks.sh`; у точек входа один общий пролог, каталог они берут из `BS_ENTRY_DIR` / `BS_BOOTSTRAP_DIR`.

Помимо определения, слой даёт: `bs::shell::host` (запущенный bash: дочерние оболочки стартуют как `"$(bs::shell::host)" -c`, не голым `bash`), вопросы к реестру вместо сравнений семейства (`bs_shell_can_source`, `bs_shell_rc_create_ok`, `bs_shell_default_login_path`) и `args::completion PROG [bash|zsh|fish|nu]` (zsh проверен в настоящем zsh; fish и nushell — только как текст).

## Приоритеты оболочек

Приоритет считается по двум вещам: **где оболочка встречается** (оценка по
дистрибутивам и платформам, не измерение) и **что реально проверено на
этой машине** (Fedora 43; команды `./bs version`, скрипт с `#!/usr/bin/env bs`,
`install.sh --help`, `bs init-shell`, `probe_shells.sh`). Таблицу пополняйте
только результатами настоящих запусков.

| # | Оболочка | Где встречается | Версия здесь | Запуск `bs` и скрипта | Родное ядро (`bash4`) | Что делать |
|---|---|---|---|---|---|---|
| 1 | bash | почти все Linux, Termux, WSL; macOS — старый 3.2 | 5.3.0 | да | да | хозяин ядра; эталон |
| 1 | zsh | macOS по умолчанию, много Linux-разработчиков | 5.9 | да | парсится, ведёт себя иначе (массивы с 1, нет `FUNCNAME`, `BASH_REMATCH`) | слой совместимости, дополнения |
| 2 | dash | `/bin/sh` в Debian/Ubuntu, скрипты установки | 0.5.12 | да (трамплин) | нет | POSIX-ядро (`core/`) |
| 2 | busybox ash | Alpine, контейнеры, роутеры, Termux | 1.37.0 | да (трамплин) | нет; терпимее dash (`[[ ]]`, `pipefail`, `::`) | POSIX-ядро, проверка в Termux |
| 3 | fish | популярная интерактивная оболочка | 4.2.0 | да, только как команда `bs` и скрипт с shebang | не применимо (другой синтаксис) | мост (`bs call`), текст дополнений |
| 3 | ksh93 | Unix, BSD, корпоративные системы | 93u+m 1.0.10 | да | парсится; нет `local`, `local -r`, `::` | POSIX-ядро; ядро bash4 не обещаем |
| 3 | mksh | **системная оболочка Android**, OpenBSD (форк) | R59 | да | парсится не полностью | POSIX-ядро |
| 4 | nushell | растёт, разработчики | не установлен | не проверено | не применимо | мост, проверка после установки |
| 4 | oksh, osh | редкие | не установлены | не проверено | — | не развивать |

Что значит «да» в колонке запуска: `./bs version` через эту оболочку и скрипт с
`#!/usr/bin/env bs` отработали; `install.sh --help` показал справку.
Отдельное «нет» ядра bash4 — не ошибка: ядро запускается в найденном bash
(трамплин), а другим оболочкам даются POSIX-модули и мост.

Порядок разработки: **1 → 2 → 3 → 4**. Внутри уровня 2–3 главный вклад —
расширение POSIX-ядра (см. «POSIX-модули ядра») и мост для оболочек с другим
синтаксисом.

## Что проверено

Реально запускалось на этой машине: bash 5.3.0, zsh 5.9, dash 0.5.12, busybox
ash 1.37.0, ksh93u+m 1.0.10, mksh R59, fish 4.2.0 — запуск `bs version`, скрипт с
shebang `bs`, `install.sh --help`, проба возможностей. **Не запускалось:**
nushell (не установлен), oksh, osh. Для fish проверен только вызов команды
`bs` и скрипта с shebang; его синтаксис ядро не читает.

## Схемы доступа: перезапуск, мост, POSIX-ярус

Три способа добраться до ядра из других оболочек. Полная картина — в [Начале работы](../01-getting-started/README.md).

### Запуск из dash: перезапуск в bash

![Сценарий 2: запуск из dash — перезапуск в bash](../../assets/uml/scenario-2-ru.svg)

### Вызов из fish и nushell: `bs call`

![Сценарий 3: bs call из fish или nushell](../../assets/uml/scenario-3-ru.svg)

### POSIX-ярус без bash

![Сценарий 4: POSIX-ярус без bash](../../assets/uml/scenario-4-ru.svg)

## Тесты и инструменты

- `tests/unit/testshellunit.sh` — реестр; `testtrampolineunit.sh` — точки входа
  под dash/zsh/bash как sh; `testshelltierunit.sh` — аннотации;
  `tests/integration/testinstallshells.sh` — установщик по оболочкам.
- `bash .agents/skills/bs-shell-portability/scripts/tier_scan.sh --check <пути>`
  — аннотация против реальных конструкций.
- `bash .agents/skills/bs-shell-portability/scripts/probe_shells.sh` — проба
  возможностей установленных оболочек.

## POSIX-модули ядра

Файлы `core/` с меткой `@shell posix` переводятся по одному (порядок: `prereq`,
`guard`, `const`, `version`, `logger`, ...). Такой модуль следует контракту
реестра: настоящие функции имеют допустимые идентификаторы (`bs_guard`,
`bs_source_relative`), имена вида `bs::guard` — псевдонимы, которые
`bs_shell_alias` создаёт только в bash и zsh, поэтому все прежние вызовы
работают. Помощники слоя для этих модулей: `bs_shell_alias`,
`bs_shell_readonly` (глобальный `readonly`: в zsh `readonly` внутри функции
локален, поэтому у zsh `readonly -g`). Каталог подключаемого файла берётся из
`BS_CURRENT_FILE`, который загрузчик ставит на время подключения модуля; bash
дополнительно читает его из стека вызовов.
`core/const.sh` показывает ветки по оболочкам: байты ESC берутся из `printf` (без `$'\033'`),
`SUPPORTED_DISTROS` — массив в bash и zsh и строка через пробел там, где массивов нет;
имена `const::*` — псевдонимы `const_*`.

`core/quiet.sh` (`@shell posix`) — идиомы «тишины»: `bs_utils_has`, `bs_utils_quiet`,
`bs_utils_quiet_err`, `bs_utils_ignore`, `bs_utils_attempt` (в bash и zsh — прежние
`utils::*`). Загружается перед `core/utils.sh`; проверен в bash, zsh, dash,
busybox ash, ksh93 и mksh (`unit/testquietportableunit.sh`).

`core/calc.sh` (`@shell posix`) — RPN-калькулятор на `dc`: `bs_calc_help`, `bs_calc_autop`,
`bs_calc_eval`, `bs_calc_interactive`, `bs_calc_main` (в bash и zsh — прежние `calc::*`, их зовёт `bs calc`).
Логгер он берёт, только если тот загружен (`bs_calc_log`), иначе пишет в stderr; приглашение интерактивного режима —
только на терминале (`[ -t 0 ]`), как у `read -p`. Проверен в bash, zsh, dash, busybox ash, ksh93 и mksh
(`unit/testcalcportableunit.sh`).

`core/fmt.sh` (`@shell posix`) — размеры и метки времени: `bs_utils_human_size`, `bs_utils_head_bytes`, `bs_utils_now_s`,
`bs_utils_now_ms`, `bs_utils_now_float`, `bs_utils_stamp`, `bs_utils_log_stamp` (в bash и zsh — прежние `utils::human_size` и др.).
Умножение размера считается в `awk`, а не в `$(( ))`: арифметика `mksh` 32-битная, и `3 GiB` в ней переполняется —
это нашёл тест. Проверен в шести оболочках (`unit/testfmtportableunit.sh`).

`core/logger.sh` (`@shell posix`) — логирование: `bs_log_trace … bs_log_fatal`, `bs_log_print`, `bs_log_header`, `bs_log_list`,
`bs_log_table`, `bs_log_progress`, `bs_log_clear_line` и приватные `bs_log_timestamp`, `bs_log_is_color_enabled`,
`bs_log_level_to_number`, `bs_log_format_message` и др. (в bash и zsh — прежние `log::*` и `log::__*`, ими пользуется
весь фреймворк). От `core/lang.sh` больше не зависит. Вывод проверен **побайтно** против прежнего bash-логгера на
48 комбинациях (формат text/structured/json × цвет × уровень × метка времени, кириллица, кавычки, переводы строк,
рамки, прогресс), затем в шести оболочках (`unit/testloggerportableunit.sh`, 122 проверки). Единственное отличие:
ширину рамки `bs_log_header` считает `${#}`, а он в dash и ash считает байты, так что у заголовка с не-ASCII
рамка в этих оболочках получится шире.

`core/utils.sh` и `core/deps.sh` (`@shell posix`, фаза 2) — `bs_utils_strict/guard/tempfile/split/ensure_source/ensure_shell_version/detect_root/boot_dir` и `bs_deps_has/require/list_missing/check_module/missing_tools/parse_optdeps` (прежние `::`-имена в bash и zsh). `bs_utils_split` заполняет массив слоя данных и совпадает с `read -ra` на 3000 случайных входов; `detect_root`/`boot_dir` читают `BS_ROOT`/`BS_BOOTSTRAP_DIR` вместо стека вызовов; `deps::missing_tools` (результат — настоящий массив bash, 10 вызывающих) живёт в мосте `lib/compat/deps.sh`. Проверено в шести оболочках (`unit/testutilsportableunit.sh`, 126 проверок; `unit/testdepsportableunit.sh`, 108 проверок); второй тест нашёл ловушку ksh93: голая `|` в шаблоне `${x%%|*}` — это альтернатива, её надо экранировать.

`core/errorhandler.sh` (`@shell posix`, фаза 2) — `bs_cleanup_add/run_all`, `bs_on_exit`, `bs_errorhandler_*`, `bs_error_*`, `bs_signal_on/ignore/reset`, `bs_exit` (число или имя кода, проверяется до `eval`), `bs_function_exists`. Стек очистки — массив слоя данных `bs_cleanup_stack`, обработчики — словарь `bs_error_handlers`. Проверено в шести оболочках (`unit/testerrorhandlerportableunit.sh`, 248 проверок); найдено тестами: `command -v` отсутствующей команды даёт 127 в dash и ash, поэтому `bs_utils_has` и `bs_function_exists` возвращают ровно 1.

`core/config.sh` (`@shell posix`, фаза 2) — `bs_config_load/get/set/list/user_file/local_file` и приватные `bs_config_set_defaults/load_file/export_to_env/key_usable` (прежние `config::*` в bash и zsh). Настройки — словарь слоя данных `bs_config` (был ассоциативным массивом `BS_CONFIG`); файл разбирается через `case` и подстановки параметров вместо `=~`; `bootstrap/init.sh` подключает модуль и вызывает `bs_config_load` и в режиме ядра `posix` (16 из 19 файлов `core/`). Ключ — ещё и имя переменной, поэтому до любого `eval` его проверяет `bs_var_*`: недопустимое, служебное (`__bs_*`) или только для чтения имя `bs_config_set` отклоняет (статус 2), а в файле пропускает с предупреждением: присваивание readonly-переменной завершает dash (нашёл тест: `bs_config_set BS_CONFIG_LOCAL_KEYS x`). Проверено в шести оболочках (`unit/testconfigportableunit.sh`, 314 проверок: трудные значения из файла пользователя, из `set` и из окружения, плохие имена для каждого `eval`; без проверок тест падает) и дифференциальным прогоном со старой bash-версией (56 кейсов × 4 окружения = 224 прогона, `diff_old_new.sh --also bootstrap/init.sh`): побайтно равно, кроме намеренного различия — `config::set` с недопустимым, служебным или readonly-ключом раньше печатал ошибку bash, возвращал 0 и оставлял мусорный ключ в словаре, теперь возвращает 2.

`core/lang.sh` (`@shell posix`, фаза 2) — только предикаты, которыми пользовалось ядро: `bs_is_empty/not_empty/exists/file/dir/symlink/file_not_empty/executable/readable/writable/number/command` (прежние `is::*` остаются псевдонимами в bash и zsh). `is::function` остаётся снаружи: функцию от команды отличает только bash. Интроспекция (`bs::func_name`, `bs::call_stack`, `bs::type_of`), `str::*`, `arr::*`, `map::*` и `bs::slice` работают с настоящими массивами bash и без изменений вынесены в `lib/compat/lang.sh` (`@shell bash4`), который `bootstrap/init.sh` подключает в режиме `full`, как `lib/compat/deps`. Проверено в шести оболочках (`unit/testlangportableunit.sh`).

`core/var.sh`, `core/str.sh`, `core/num.sh`, `core/msg.sh` (`@shell posix`) — базовые абстракции ядра: то, что копировалось из файла в файл, теперь живёт в одном месте, у каждой группы своё пространство и свой переносимый тест. Грузятся сразу после `core/const`, кроме оболочки ничего не используют; прежних имён с `::` у них нет, поэтому псевдонимов нет.
- `bs_var_*` — переменные по имени: `is_name`, `is_set`, `is_readonly` (проба в подоболочке: присваивание readonly-переменной завершает неинтерактивную оболочку во всех оболочках, которые мы запускали), `get` (в stdout или в переменную), `set`, `unset`, `default`, `append`. Имя проверяется до каждого `eval`; имена на `__bs_var_` зарезервированы. 147 проверок в шести оболочках (`unit/testvarportableunit.sh`).
- `bs_str_*` — `upper`, `lower`, `trim`, `ltrim`, `rtrim`, `replace` (ДОСЛОВНАЯ подстрока), `contains`, `starts_with`, `ends_with`, `repeat`, `join` (не зависит от `IFS`), `before`, `after`. Имена `str::upper` … `str::repeat` принадлежат `lib/compat/lang.sh` (bash, шаблон замены — glob) и остаются как есть: псевдонимы не создаются, тест проверяет, что `str::replace` не подменён. Длины и дополнения до ширины намеренно нет: `${#s}` считает байты в dash и mksh и символы в остальных. 238 проверок (`unit/teststrportableunit.sh`).
- `bs_num_*` — целые до 15 цифр через `awk`, а не `$(( ))`: `is_uint`, `is_int`, `dec` (`007` → `7`), `add`, `sub`, `mul`, `div`, `mod`, `cmp`. Вход или результат за пределом — статус 1, деление на ноль — 2. Совпадает с `$(( ))` bash на 300 случайных парах в dash, ksh, zsh, bash и ash (и на 120 в mksh: первый прогон испортил его собственный 32-битный генератор — та самая ловушка, ради которой модуль и нужен). 117 проверок (`unit/testnumportableunit.sh`).
- `bs_msg_*` — сообщения модулей: `error`, `warn`, `info` через логгер, если он загружен, иначе `УРОВЕНЬ: текст` в stderr (info — в stdout); `fail` возвращает `E_ERROR`, `invalid ФУНКЦИЯ текст` — `E_INVALID`; ни одна не завершает скрипт. 93 проверки (`unit/testmsgportableunit.sh`).
На них переведено (переносимые тесты всех пяти файлов дают прежнее число пройденных проверок): `bs_exit` берёт код по имени через `bs_str_upper` и `bs_var_get`, `bs_error_retry` проверяет число попыток через `bs_num_*`, `bs_data_ret` присваивает через `bs_var_set`, `bs_utils_error` и `bs_calc_log` заменены на `bs_msg_*` (заодно починен `calc` в dash: он искал псевдоним `log::warn`, которого там нет, и логгером не пользовался). Заметные изменения: без логгера ошибка печатается как `ERROR: текст`, а не голым текстом, и `bs_error_retry` цитирует аргумент как он передан (`00`, а не `0`). Намеренно оставлено как есть: `bs_log_replace_all` (он возвращает через переменную, потому что `$(...)` срезал бы завершающий перевод строки в тексте), `bs_guard` в `prereq` (грузится раньше всего), сообщения в `guard.sh` и `data.sh`. В `core/data.sh` все слоты массивов теперь читают и пишут пять маленьких помощников (`bs_data_len_of/set_len/get_at/put_at/drop_at`), поэтому строки с `eval` и индексами из публичных функций ушли; 272 проверки и случайное сравнение с настоящими массивами bash (6 × 2500 операций) в dash, mksh, zsh, ksh, ash и bash без изменений.

`bootstrap/loader.sh` (`@shell posix`) — загрузчик модулей: `bs_load` (прежние `load` и `bs::load` в bash и zsh) и приватные `bs_load_*`. Реестр загруженных — словарь слоя данных `bs_loaded_modules` (был `BS_LOADED_MODULES`), стек загрузки — массив `bs_load_stack` (был `BS_LOAD_STACK`), стек значений `BS_CURRENT_FILE` — `bs_load_files`; `repl` и `unit/testloaderunit.sh` читают их через `bs_map_*`/`bs_arr_*`. Нижний слой (`prereq`, `var`, `str`, `data`) загрузчик подключает сам при первом вызове: ниже него ничего нет. `@depends` читается через `case` и подстановки параметров вместо `[[ =~ ]]`; `bs_load` рекурсивен, а временные переменные глобальны, поэтому путь модуля всегда берётся с вершины `bs_load_stack`. Сообщения прежние; единственное заметное изменение — цепочка цикла склеена пробелом (`${a[*]}` склеивал первым символом `IFS`, в скриптах BS это перевод строки). 133 проверки в шести оболочках (`unit/testloaderportableunit.sh`), 16 в ядре (`unit/testloaderunit.sh`), вывод шести сценариев побайтно равен прежнему загрузчику (`diff_old_new.sh`), ядро грузится за то же время. `bootstrap/init.sh` пока остаётся `bash4`: он ещё использует pre-kernel помощники `bootstrap/bs.sh`.

## Установщик и `init.sh` без bash

`bootstrap/base.sh` (`@shell posix`) — POSIX-половина прежнего `bootstrap/bs.sh`: `bs_strict`, `bs_append_local_bin_to_path`, `bs_shell_name/host/version/ok` и `bs_shell_ensure_version` (прежние `bs::strict`, `bs::shell::*` остаются псевдонимами bash/zsh). Что читает стек вызовов, `BASH_REMATCH` и `BASH_SOURCE`, осталось в `bootstrap/bs.sh` (bash) вместе с командами `bs::cli::*`. 83 проверки в шести оболочках (`unit/testbaseportableunit.sh`).

`bootstrap/init.sh` (`@shell posix`) грузит ядро в двух режимах, `BS_KERNEL_MODE`: `full` в bash 4.2+ (16 модулей и мосты `lib/compat/deps`, `lib/compat/lang` и `lib/compat/args`; `args` и `calc` подключаются по запросу) и `posix` в dash, ash, ksh, mksh и zsh (те же 16 модулей без мостов: `prereq`, `lang`, `const`, `var`, `str`, `num`, `msg`, `logger`, `quiet`, `fmt`, `data`, `errorhandler`, `version`, `utils`, `config`, `deps`); `bs_config_load` работает в обоих; bash старше 4.2 отклоняется. Свой каталог init.sh находит так: bash читает путь файла, zsh — `%x`, остальные берут `BS_BOOTSTRAP_DIR`, `BS_ENTRY_DIR` (его ставит пролог точек входа) или `BS_ROOT`. Отличить «подключён» от «исполнен» умеет только bash, поэтому прямой запуск отклоняет только он. 75 проверок в шести оболочках (`unit/testinitportableunit.sh`).

`install.sh` и `install/*.sh` — `@shell posix` (`bs_install_*`, `bs_do_install`, `bs_do_uninstall`, `bs_auto_update_path`, …; прежние имена остаются псевдонимами): массивы стали массивами слоя данных, `[[ =~ ]]` и `printf -v` — `case` и подстановками параметров, `local` — временными `__bs_<файл>_`, а рамка уведомления считает символы UTF-8 через `bs_str_width`/`bs_str_head` (голый `${#s}` в dash и mksh считает байты и сломал бы границы с кириллицей). Вывод уведомлений и помощников PATH побайтно равен прежней bash-версии на 19 сценариях (`diff_old_new.sh`), кроме номера строки в одном сообщении оболочки об rc-файле только для чтения. Точка входа, умеющая работать без bash, ставит `BS_POSIX_ENTRY=1` до пролога: трамплин по-прежнему перезапускает её в bash 4.2+, если он есть, а иначе возвращается и даёт продолжить в текущей оболочке (явный, но неподходящий `BS_HOST_BASH` остаётся ошибкой). `unit/testinstallnobashunit.sh` прячет каждый bash в пространстве монтирования (`unshare -Urm`) и гоняет установка → отказ повторной → удаление в ash, dash, ksh, mksh и zsh. Это нашло две вещи: в mksh нет встроенного `printf` (нужен бинарник), а пустой шаблон `"$var"*` в `case` совпадает со всем, поэтому помощник не должен верить переменной, которую пропавшая команда оставила пустой. Не проверено: настоящая машина с Alpine/musl (тест использует апплеты busybox на хосте с glibc).

`boot.sh` (стадия 1: найти `BS_ROOT`, `exec bs`) тоже `@shell posix` и подключает `bootstrap/base.sh` вместо bash-слоя; `unit/testtrampolineunit.sh` гоняет его во всех оболочках, `unit/testbsnobashunit.sh` — при скрытых bash.

Точка входа `bs` тоже `@shell posix` (она ставит `BS_POSIX_ENTRY=1`): в bash 4.2+ все команды работают как раньше (вывод 43 из 45 командных строк побайтно равен прежнему `bs`; ещё две отличаются лишь тем, что у копии для сравнения не было `.git`), а без bash работают команды, уже ушедшие на POSIX, — `help`, `version`, `env`, `list`, `calc`, `init-shell`, `shebang`, `call`, `uninstall`, `where`, `update` и `doctor` (кроме `doctor --capabilities`) в `bootstrap/cli.sh` (`bs_cli_*`, прежние `bs::cli::*` остаются псевдонимами); остальные печатают «команда пока требует bash 4.2+» и завершаются с кодом 1 (`bs_cli_delegate`). 5 оболочек в `unit/testbsnobashunit.sh` (включая удаление тестовой установки). Пока на bash: 9 команд `bs::cli::*`, которые запускают код `lib/` (`run`, `build`, `api`, `rfc`, `ts`, `audit`, `chat`, `lsp`, `lang-doc`; они остаются в `bootstrap/bs.sh`), `repl` и сам `lib/`. `bs update` без bash делает всё: транзакционную замену `bs`, `bootstrap/`, `core/`, `lib/`, самопроверку новой копии, откат, замок, манифест, клонирование с GitHub (`git`, иначе `curl`/`wget`) и вопрос «pull / github / local». `bs call` в оболочке без bash принимает только имена, которые действительно функции (`command -V`, а не программа из `PATH`) — прежний `declare -F` в POSIX не записать.

## Пространство имён `bs_`

Весь код ядра (`bootstrap/`, `core/`, `install/`, точки входа) живёт в **одном** пространстве имён: настоящая функция называется `bs_` + имя через `::`, где `::` заменено на `_` (`utils::has` ↔ `bs_utils_has`, `log::info` ↔ `bs_log_info`, `bs::version::get` ↔ `bs_version_get`). Прежние имена с `::` остаются псевдонимами для bash и zsh (их создаёт `bs_shell_alias`), поэтому 87 модулей `lib/` и все скрипты работают без правок. Правило проверяет `check_posix_tier.sh`: функция вне `bs_`/`__bs_` или определённая с `::` — нарушение. Приватные функции теряют ведущие `__` (`log::__timestamp` ↔ `bs_log_timestamp`); временные переменные внутри — `__bs_<модуль>_…`.

## Слой данных `core/data.sh`

В POSIX sh нет массивов и ассоциативных массивов, а ядру они нужны (список загруженных модулей, стек очистки, конфигурация, параметры скрипта). `core/data.sh` (`@shell posix`) даёт им замену на переменных и `eval`, одинаковую в dash, ash, ksh, mksh, zsh и bash:

- массивы: `bs_arr_new/push/len/get/set/pop/shift/remove_at/index_of/contains/join/clear/copy/from_lines/to_args/each`;
- словари: `bs_map_set/get/has/remove/count/keys/keys_to/clear/each` (ключ любого вида: пробелы, кавычки, `$`, `*`, кириллица, пустой; порядок вставки сохраняется);
- `bs_quote` — строка в одинарных кавычках, которую `eval` вернёт как есть (`eval "$(bs_arr_to_args имя)"` кладёт массив в `"$@"`).

Что важно знать: функции, которые меняют состояние и возвращают значение (`bs_arr_pop`, `bs_arr_shift`), нельзя вызывать как `$(…)` — изменение останется в подоболочке; результат берут в переменную (`bs_arr_pop имя результат`). Проверено 272 проверками в шести оболочках и случайным сравнением с родными массивами bash (6 наборов по 2500 операций, расхождений нет). Прежние `arr::*` и `map::*` (теперь в `lib/compat/lang.sh`) работают с настоящими массивами bash и остаются как есть; само ядро пользуется этим слоем.

## `repl` вне ядра

`bs repl` — интерактивная сессия bash с загруженным ядром, то есть по смыслу не часть ядра. Модуль перенесён из `core/repl.sh` в `lib/ui/repl.sh` (загружается `load "lib/ui/repl"`); в ядре остаётся 19 файлов.

## Курс на независимость от оболочки

Цель — чтобы `bootstrap/`, `core/`, `install/`, `boot.sh`, `bs` и `install.sh` жили в одном пространстве имён `bs_*` и не зависели от оболочки. Состояние: готовы все 19 файлов `core/` (`prereq`, `guard`, `const`, `version`, `quiet`, `fmt`, `logger`, `calc`, `data`, `utils`, `deps`, `errorhandler`, `config`, `lang`, `args`, `var`, `str`, `num`, `msg`), слой оболочек и шебанга, загрузчик, `base.sh`, `init.sh` и `cli.sh` в `bootstrap/`, `install/*` и точки входа `install.sh`, `bs` и `boot.sh`. Пока на bash 4.2+: `bootstrap/bs.sh` (стек вызовов и `BASH_REMATCH`, с 9 командами `bs::cli::*`, которые запускают `lib/`) и 87 модулей `lib/`; поэтому полному BS по-прежнему нужен bash 4.2+ (см. начало страницы), а без него работает POSIX-часть выше.

## Не сделано

Автодополнение для zsh/fish/nushell (есть только bash); аннотации `@shell`
вне bootstrap/install (по умолчанию `bash4`).
