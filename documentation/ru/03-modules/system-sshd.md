[↑ Указатель документации](../README.md)

# Модуль `sshd`

Серверная конфигурация OpenSSH: data-driven каталог параметров с короткой
русской подсказкой на каждый, профили ужесточения, валидация по типам,
рендер конфига с маркерами управляемого блока и безопасная установка
(backup → `sshd -t` → атомарная замена → reload, с откатом).

Ярус: **только Linux** (пишет под `/etc/ssh`, перезагружает через
`systemctl`). Без бинарника `sshd` или прав на запись — чистая деградация с
определёнными кодами `LIB_ERROR_*`, никогда не молчаливый успех.

Источник: [lib/system/sshd.sh](../../../lib/system/sshd.sh)

## Подключение

```bash
#!/usr/bin/env bs

load "lib/system/sshd"
```

## Тестовые хуки

| Переменная | По умолчанию | Назначение |
|---|---|---|
| `BS_SSHD_DIR` | `/etc/ssh/sshd_config.d` | каталог drop-in конфигов |
| `BS_SSHD_MAIN` | `/etc/ssh/sshd_config` | основной конфиг (управляемый блок) |
| `BS_SSHD_BIN` | `sshd` | бинарник sshd или мок для тестов |
| `BS_SSHD_SERVICE` | `sshd` | имя systemd-сервиса для reload |
| `BS_SSHD_DRY_RUN` | `0` | `1` = без записи и reload |
| `BS_SSHD_DROPIN` | `99-bs.conf` | имя drop-in файла |

## Каталог

Каждый параметр несёт `section|type|default|recommended` и двухстрочную
русскую подсказку:

```bash
sshd::param_list            # name<TAB>section<TAB>type<TAB>default<TAB>recommended
sshd::param_list Network    # фильтр по секции
sshd::param_type Port       # "port"
sshd::param_desc Port       # двухстрочная русская подсказка
sshd::param_default Port    # 22
sshd::param_recommended Port # 22
```

Типы: `bool`, `int`, `port`, `enum:...`, `string`, `userlist`,
`grouplist`, `csv`, `path`, `addr`, `time`.

Секции: `Network`, `Authentication`, `Access Control`, `Forwarding`,
`Logging`, `Cryptography`, `SFTP`, `Match`.

## Валидация

```bash
sshd::validate PasswordAuthentication no   # E_SUCCESS
sshd::validate Port 70000                   # LIB_ERROR_INVALID_INPUT
```

Значения с переводами строк, возвратом каретки, табами или пробелами
отклоняются — значение не может внедрить новую директиву в конфиг.

## Профили

```bash
sshd::profile basic      # вход только по ключам, root по ключу, без X11
sshd::profile strict     # + запрет root, без проброса, только publickey
sshd::profile paranoid   # + только inet, урезанные ciphers/MACs/Kex
```

`strict` включает `basic`, `paranoid` включает `strict` (при потреблении в
карту побеждают поздние строки).

## Рендер

`sshd::render` читает из stdin строки `name=value` и печатает конфиг с
маркерами управляемого блока. Основные параметры упорядочены по каталогу;
`@match <критерии>` открывает Match-блок, пустая строка закрывает его.

```bash
printf 'Port=2222\nPasswordAuthentication=no\n' | sshd::render
printf '@match Group sftponly\nChrootDirectory=%%h\nForceCommand=internal-sftp\n\n' | sshd::render
```

Пустые значения пропускаются. Директивы Match идут с отступом.

## Установка / откат

```bash
sshd::test /tmp/sshd.conf          # sshd -t -f; 101 если sshd нет
sshd::install /tmp/sshd.conf       # drop-in: backup → валидация → замена → reload
sshd::install_main /tmp/block.conf # управляемый блок внутри BS_SSHD_MAIN
sshd::revert /etc/ssh/sshd_config.d/99-bs.conf  # восстановить новейший .bak.*
```

`sshd::install` пишет атомарно и валидирует до и после замены; при провале
восстанавливает backup (или удаляет новый файл). `BS_SSHD_DRY_RUN=1`
печатает планируемые действия и ничего не пишет.

## Коды ошибок

| Код | Значение |
|---|---|
| `E_SUCCESS` | успех |
| `LIB_ERROR_INVALID_INPUT` | значение/директива отклонены (в т.ч. `sshd -t`) |
| `LIB_ERROR_INVALID_ARGS` | неизвестный параметр/тип/профиль |
| `LIB_ERROR_FILE_NOT_FOUND` | нет источника/цели/backup |
| `LIB_ERROR_PERMISSION_DENIED` | каталог/файл недоступен для записи |
| `LIB_ERROR_DEPENDENCY_MISSING` | нет `sshd`/`systemctl` |
| `LIB_ERROR_FILE_OPERATION` | сбой copy/move |

## Визард

`examples/sshd_wizard.sh` — полноэкранный TUI на `lib/tui/tui`: выбрать
профиль, настроить параметры по секциям (у каждого своя русская подсказка),
добавить Match/chroot блоки, посмотреть предпросмотр и применить в drop-in
или основной конфиг (либо просто распечатать). Запуск:

```bash
bs run examples/sshd_wizard.sh --dry-run
```
