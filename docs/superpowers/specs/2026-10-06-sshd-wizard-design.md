# Дизайн: визард создания sshd-конфигов (TUI)

Дата: 2026-10-06
Статус: на ревью
Автор: сессия opencode

## 1. Цель и результат

Интерактивный полноэкранный TUI-визард, который помогает собрать `sshd`
конфигурацию сервера: выбрать профиль жёсткости, точечно настроить параметры
(каждый с коротким русским пояснением «зачем»), при желании добавить
`Match`/chroot-SFTP блоки, увидеть предпросмотр, проверить `sshd -t`, записать
drop-in или managed-блок и перезагрузить сервис — либо просто напечатать
готовый конфиг.

Успех: пользователь без знания всех опций sshd получает валидный
(`sshd -t` проходит) конфиг, применимый безопасно (backup + откат при ошибке),
и понимает назначение каждого параметра.

## 2. Решения по процессу (согласовано)

- UI строится на `lib/tui/tui` (полноэкранное приложение, ручной главный цикл
  в стиле `examples/tui_demo.sh`), а не на линейном `lib/ui/wizard`.
- Логика конфигурации вынесена в отдельный модуль `lib/system/sshd.sh`,
  визард — тонкий UI поверх него.
- Охват параметров: «всё + Match/chroot».
- Каждый параметр имеет русское пояснение на 2 строки (`sshd::param_desc`).
- Профили: `basic` / `strict` / `paranoid` как пресеты + режим `custom`.

## 3. Архитектура

```
lib/system/sshd.sh        модель, каталог, валидация, рендер, установка
examples/sshd_wizard.sh   TUI-приложение (lib/tui/tui + lib/ui/steplog)
documentation/{en,ru}/03-modules/system-sshd.md
tests/unit/testsshdunit.sh          логика модуля
tests/unit/testsshdwizardunit.sh    draw/состояние UI (по образцу testtuiunit)
```

Границы: модуль не знает про TUI и не рисует; визард не содержит знания о
правилах sshd, только UI-навигацию и вызовы `sshd::*`.

## 4. Модуль `lib/system/sshd.sh`

### 4.1 Метаданные и зависимости

- Shebang `#!/usr/bin/env bs`, строка 2 `# shellcheck shell=bash`.
- `# @depends core/lang, core/logger, core/utils, lib/io/files` (атомарная
  запись/backup берётся из `lib/io/files`).
- `bs::guard "LIB_SYSTEM_SSHD"`, `bs::source_relative "../../core/...`.
- `bs::source_relative` не используется для `lib/` — вместо этого `load`
  недопустим внутри модуля, поэтому зависимости подключаются
  `bs::source_relative`.

### 4.2 Хуки (тестируемость)

| Переменная | По умолчанию | Назначение |
|---|---|---|
| `BS_SSHD_DIR` | `/etc/ssh/sshd_config.d` | каталог drop-in |
| `BS_SSHD_MAIN` | `/etc/ssh/sshd_config` | основной конфиг (managed-блок) |
| `BS_SSHD_BIN` | `sshd` | бинарник `sshd -t` (мок в тестах) |
| `BS_SSHD_SERVICE` | `sshd` | имя юнита для `systemctl reload` |
| `BS_SSHD_DRY_RUN` | `0` | `1` — ничего не писать/не reload |
| `BS_SSHD_DROPIN` | `99-bs.conf` | имя drop-in файла |

Хуки объявляются с парным `# @global` (категория `hook`).

### 4.3 Каталог параметров

Ассоциативные массивы (образец — `GPU_TOOLS` в `lib/system/gpu.sh`):

```
SSHD_PARAMS[<param>]='<section>|<type>|<default>|<recommended>'
SSHD_TIPS[<param>]='<строка 1>\n<строка 2>'
```

Секции: `Network`, `Authentication`, `Access Control`, `Forwarding`,
`Logging`, `Cryptography`, `SFTP`, `Match`.
Типы: `bool`, `int`, `enum`, `string`, `userlist`, `grouplist`, `csv`,
`path`, `addr`, `time`.

Базовый набор (уточняется на реализации, все с `SSHD_TIPS` на русском):

- Network: `Port`, `ListenAddress`, `AddressFamily`, `LoginGraceTime`.
- Authentication: `PermitRootLogin`, `PasswordAuthentication`,
  `PubkeyAuthentication`, `PermitEmptyPasswords`,
  `KbdInteractiveAuthentication`, `AuthenticationMethods`, `MaxAuthTries`,
  `MaxSessions`.
- Access Control: `AllowUsers`, `AllowGroups`, `DenyUsers`, `DenyGroups`.
- Forwarding: `X11Forwarding`, `AllowTcpForwarding`, `AllowAgentForwarding`,
  `GatewayPorts`, `PermitTunnel`.
- Logging: `SyslogFacility`, `LogLevel`.
- Cryptography: `Ciphers`, `MACs`, `KexAlgorithms`, `HostKeyAlgorithms`,
  `UsePAM`.
- SFTP: `Subsystem` (спец-строка `internal-sftp`).
- Match: подмножество параметров, допустимых внутри `Match`
  (`ChrootDirectory`, `ForceCommand`, `AllowTcpForwarding`, `X11Forwarding`,
  `PermitTTY`, `PasswordAuthentication`).

### 4.4 Профили

`sshd::profile <basic|strict|paranoid>` печатает строки `param=value`:

- `basic`: `PubkeyAuthentication=yes`, `PasswordAuthentication=no`,
  `PermitRootLogin=prohibit-password`, `X11Forwarding=no`,
  `MaxAuthTries=5`, `LoginGraceTime=60`.
- `strict`: `basic` + `PermitRootLogin=no`, `AllowTcpForwarding=no`,
  `AllowAgentForwarding=no`, `PermitEmptyPasswords=no`,
  `KbdInteractiveAuthentication=no`, `MaxAuthTries=3`,
  `LoginGraceTime=30`, `LogLevel=VERBOSE`,
  `AuthenticationMethods=publickey`.
- `paranoid`: `strict` + `AddressFamily=inet`, `GatewayPorts=no`,
  `PermitTunnel=no`, `MaxSessions=3`, `SyslogFacility=AUTHPRIV`,
  урезанные `Ciphers`/`MACs`/`KexAlgorithms`.

### 4.5 Публичный API

| Функция | Назначение |
|---|---|
| `sshd::init` | выставить дефолты хуков, определить наличие `sshd` |
| `sshd::param_list [section]` | TSV: `name<TAB>section<TAB>type<TAB>default<TAB>recommended` |
| `sshd::param_desc <name>` | stdout: 2-строчный русский tip |
| `sshd::param_type <name>` | тип параметра |
| `sshd::validate <name> <value>` | проверка значения по типу; 0/`LIB_ERROR_INVALID_INPUT` |
| `sshd::profile <name>` | строки пресета |
| `sshd::render` | из stdin (`name=value`, пустая строка = разделитель блоков Match) собрать конфиг в stdout: заголовок + маркеры managed-блока + сортировка по секциям |
| `sshd::test [file]` | `"$BS_SSHD_BIN" -t -f <file>`; код возврата; при отсутствии бинарника — `LIB_ERROR_DEPENDENCY_MISSING` |
| `sshd::backup <file>` | копия `<file>.bak.<timestamp>` |
| `sshd::install <file> [target]` | backup → validate → атомарная запись в target → reload; при провале — откат |
| `sshd::revert <target>` | восстановить из последнего `.bak.*` |

Ошибки — через `LIB_ERROR_*`, никогда молчаливый успех. В `DRY_RUN` —
печать планируемых действий и `E_SUCCESS`.

### 4.6 Match/chroot

`Match`-блоки представляются секцией `Match`. `sshd::render` принимает
маркер начала блока (например строка `@match <критерии>`) и печатает
корректный `Match <criteria>` + параметры. Шаблон SFTP-chroot:
`Match Group sftponly` → `ChrootDirectory %h`, `ForceCommand internal-sftp`,
`AllowTcpForwarding no`, `X11Forwarding no`, `PermitTTY no`.

## 5. TUI-приложение `examples/sshd_wizard.sh`

### 5.1 Каркас

- Shebang `#!/usr/bin/env bs`, строка 2 `# shellcheck shell=bash`.
- `load "lib/system/sshd"`, `load "lib/tui/tui"`, `load "lib/ui/steplog"`,
  `load "core/utils"`.
- `steplog::init` (после обработки `--help`); `--verbose` дублирует лог в stderr.
- `--dry-run` → `BS_SSHD_DRY_RUN=1`.
- Главный цикл: `tui::init` → `{ tui::handle_resize; tui::buf::clear; draw;
  tui::modal::draw_all; tui::render; tui::key_read; обработать TUI_KEY }` →
  `tui::quit`.
- Запуск только при `BASH_EXECUTION_STRING` или `BASH_SOURCE[0]==$0`
  (чтобы тесты могли source без запуска).

### 5.2 Состояние

- `SSHD_WZ_SECTION`, `SSHD_WZ_SELECT` — позиции;
- `declare -A SSHD_WZ_VALUES` — выбранные значения;
- `SSHD_WZ_PROFILE`, `SSHD_WZ_TARGET` (`dropin|main|print`),
  `SSHD_WZ_MATCHES` (массив критериев), `SSHD_WZ_DIRTY`;
- `SSHD_WZ_VIEW` (`params|match|preview|apply`).

### 5.3 Экраны

1. **Профиль** — экран/модалка со списком `basic/strict/paranoid/custom` и
   описанием эффекта; выбор профиля заполняет `SSHD_WZ_VALUES`.
2. **Параметры (основной)** — `tui::box` секции слева, `tui::list`
   `Имя = значение` по центру (изменённые подсвечены), панель 2-строчного
   `sshd::param_desc` снизу/справа, `tui::titlebar`/`tui::statusbar`.
3. **Match/chroot** — список блоков; добавление критериев
   (`User/Group/Address`) и параметров внутри через модалки; шаблон SFTP.
4. **Preview** — `tui::render` конфига в `tui::box` с прокруткой
   (`PGUP/PGDN`, `tui::scrollbar`).
5. **Apply** — выбор target → `tui::confirm` → `sshd::install`/печать →
   результат модалкой; финальный экран NEXT/Control/Files.

### 5.4 Редактирование значений

- `bool` → модалка `Да/Нет` (Space — быстрый toggle).
- `enum` → модалка со списком допустимых значений.
- `int/string/path/userlist/csv` → `tui::input` с курсором (LEFT/RIGHT/
  HOME/END/BACKSPACE/DELETE), подтверждение ENTER.
- Валидация `sshd::validate`; при ошибке — красная строка, модалка открыта.

### 5.5 Клавиши

`←→` секция · `↑↓`/`j/k`(и кириллица `о/л`) параметр · `Enter` правка ·
`Space` toggle bool · `P` профиль · `M` match · `V` preview · `A` apply ·
`r` reset к профилю · `?` справка (модалка) · `q` выход.

## 6. Документация

- `documentation/en/03-modules/system-sshd.md` и RU-зеркало: обзор, хук-таблица,
  API, примеры, коды ошибок.
- `documentation/en|ru/03-modules/lib-modules-overview.md` — добавить
  `sshd.sh` в список системных модулей.
- `README.md` — раздел примеров (TUI-приложение) и/или модулей.

## 7. Тесты

`tests/unit/testsshdunit.sh`:

- форма каталога: каждая запись `SSHD_PARAMS` имеет 4 поля, тип из
  допустимых, `SSHD_TIPS` непустой и содержит кириллицу;
- `sshd::param_list [section]` фильтрует;
- `sshd::validate` для каждого типа (валидные/невалидные значения);
- `sshd::profile` печатает ожидаемые ключи, профили вложены;
- `sshd::render` содержит секции/маркеры и корректный `Match`;
- `sshd::test` на фейковом `sshd` (exit 0 и exit 1), отсутствие бинарника →
  `LIB_ERROR_DEPENDENCY_MISSING`;
- `sshd::install` в временном `BS_SSHD_DIR` создаёт backup и файл;
  провал `sshd -t` → откат; `BS_SSHD_DRY_RUN=1` → без записи;
- `sshd::revert` восстанавливает.

`tests/unit/testsshdwizardunit.sh` (по образцу `testtuiunit.sh`):

- source визарда без запуска main;
- draw-функции заполняют `TUI_BUF` (рамки/список/описание);
- переходы состояния: смена секции/параметра, применённый профиль
  заполняет значения, ошибка валидации не закрывает редактирование.

## 8. Валидация

`bash tests/validatesyntax.sh`, `bash tests/validateshellcheck.sh`,
`bash tests/runalltests.sh` — все зелёные. Обновить
`documentation`-обзор. Коммит в стиле репозитория (Conventional Commits,
сжатое «subject; clarifiers»).

## 9. Вне области (YAGNI)

- Парсинг и слияние существующего `sshd_config` по всем Include.
- Управление ключами/`authorized_keys`.
- Настройка firewall.
- Автоустановка пакета `openssh-server`.
