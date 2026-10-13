[↑ Указатель документации](../README.md)

# Модуль `fail2ban`

Серверная конфигурация джейлов fail2ban: data-driven каталог параметров
`[DEFAULT]` и джейлов с короткой русской подсказкой на каждый, валидация по
типам, профили ужесточения, INI-рендер с маркерами управляемого блока и
безопасная установка (backup → `fail2ban-client -t` → атомарная запись →
reload, с откатом). Плюс каталог джейлов с рекомендованными
`filter`/`logpath`/`port` и автообнаружение фильтров.

Ярус: **только Linux** (пишет под `/etc/fail2ban`, перезагружает через
`fail2ban-client`). Без клиента или прав на запись — чистая деградация с
определёнными кодами `LIB_ERROR_*`, никогда не молчаливый успех.

Источник: [lib/system/fail2ban.sh](../../../lib/system/fail2ban.sh)

## Подключение

```bash
#!/usr/bin/env bs

load "lib/system/fail2ban"
```

## Тестовые хуки

| Переменная | По умолчанию | Назначение |
|---|---|---|
| `BS_FAIL2BAN_DIR` | `/etc/fail2ban` | корень конфигов |
| `BS_FAIL2BAN_DROPIN` | `jail.d/99-bs.conf` | путь drop-in (относительно каталога) |
| `BS_FAIL2BAN_CLIENT` | `fail2ban-client` | клиент или мок для тестов |
| `BS_FAIL2BAN_SERVICE` | `fail2ban` | имя systemd-юнита |
| `BS_FAIL2BAN_DRY_RUN` | `0` | `1` = без записи и reload |

## Каталог

```bash
fail2ban::param_list default   # name<TAB>type<TAB>default<TAB>recommended
fail2ban::param_list jail
fail2ban::param_type bantime   # "time"
fail2ban::param_desc bantime   # двухстрочная русская подсказка
fail2ban::jails                # jail<TAB>filter<TAB>logpath<TAB>port<TAB>rec
```

`[DEFAULT]`: `bantime`, `findtime`, `maxretry`, `ignoreip`, `backend`,
`banaction`, `action`, `chain`, `bantime.increment`, `bantime.factor`,
`bantime.maxtime`, `bantime.rndtime`, `bantime.overalljails`, `destemail`,
`sender`, `mta`.
Джейл: `enabled`, `port`, `filter`, `logpath`, `mode` и оверрайды
`maxretry`/`bantime`/`findtime`/`ignoreip`/`backend`/`action`/`banaction`.
Типы: `time` (напр. `10m`, `1h`, `-1` — навсегда), `int`, `bool`, `enum`,
`iplist`, `pathlist`, `string`.

## Валидация

```bash
fail2ban::validate bantime 1h              # E_SUCCESS
fail2ban::validate maxretry "5;rm"         # LIB_ERROR_INVALID_INPUT
```

Значения с переводами строк/табами отклоняются глобально; списки IP и пути
проверяются по типу.

## Профили

```bash
fail2ban::profile basic      # 10m/5 попыток, включает sshd
fail2ban::profile strict     # 1h, increment×2, включает sshd-ddos + recidive
fail2ban::profile paranoid   # бан навсегда (-1), systemd backend
```

## Рендер

`fail2ban::render` читает строки `@section NAME` / `key=value` и печатает INI с
маркерами управляемого блока; `[DEFAULT]` первым, остальные секции по
алфавиту, пустые значения пропускаются:

```bash
printf '@section DEFAULT\nbantime=1h\nmaxretry=5\n\n@section sshd\nenabled=true\n' | fail2ban::render
```

## Установка / откат

```bash
fail2ban::test /path/jail.local     # fail2ban-client -c <dir> -t (хук-мок)
fail2ban::install /path/jail.local  # backup → тест → атомарная запись → reload
fail2ban::revert /etc/fail2ban/jail.d/99-bs.conf
fail2ban::detect                    # доступные джейлы (filter.d/*.conf)
fail2ban::status                    # статус клиента (учитывает BS_OUTPUT_FORMAT)
```

`BS_FAIL2BAN_DRY_RUN=1` печатает планируемые действия и ничего не пишет.

## Коды ошибок

| Код | Значение |
|---|---|
| `E_SUCCESS` | успех |
| `LIB_ERROR_INVALID_INPUT` | значение отклонено (в т.ч. `-t`) |
| `LIB_ERROR_INVALID_ARGS` | неизвестный параметр/тип/профиль |
| `LIB_ERROR_FILE_NOT_FOUND` | нет источника/цели/backup |
| `LIB_ERROR_PERMISSION_DENIED` | каталог недоступен для записи |
| `LIB_ERROR_DEPENDENCY_MISSING` | нет `fail2ban-client` |
| `LIB_ERROR_FILE_OPERATION` | сбой copy/move |

## Визард

`examples/fail2ban_wizard.sh` — полноэкранный TUI на `lib/tui/tui` (тот же
движок, что у sshd-визарда): выбор джейлов из обнаруженных фильтров, настройка
`[DEFAULT]` и параметров джейлов (с русской подсказкой), предпросмотр и
применение в drop-in (или печать). Запуск:

```bash
bs run examples/fail2ban_wizard.sh --dry-run
```
