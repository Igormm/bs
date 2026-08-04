[↑ Оглавление](../README.md)

# Модуль `io::process`

Process Guard — обёртка-сторож для запуска произвольных команд.
Следит за общим временем выполнения (`--timeout`) и активностью вывода
(`--hang-after`), при таймауте или зависании собирает диагностический
снимок и корректно завершает процесс.

Исходник: [lib/io/process.sh](../../../lib/io/process.sh)

## Загрузка

```bash
#!/usr/bin/env bs

load "lib/io/process"
```

Или вручную:

```bash
source bootstrap/init.sh
load "lib/io/process"
```

## API

```bash
io::process::guard [опции] -- команда [аргументы...]
```

**Важно:** если команда сама имеет аргументы с `--`, используйте `--`
перед ней, чтобы сторож не попытался их разобрать как свои опции.

## Опции

| Опция | Env-переменная | Назначение |
|---|---|---|
| `--timeout <сек>` | `BS_PROCESS_GUARD_TIMEOUT` | Общий лимит времени, `0` — без лимита. |
| `--hang-after <сек>` | `BS_PROCESS_GUARD_HANG_AFTER` | Лимит молчания stdout/stderr, `0` — отключён. |
| `--strace-duration <сек>` | `BS_PROCESS_GUARD_STRACE_DURATION` | Сколько секунд вести strace (по умолчанию 5). |
| `--strace-file` / `--no-strace-file` | `BS_PROCESS_GUARD_STRACE_FILE` | strace `read,write,%file`. |
| `--strace-net` / `--no-strace-net` | `BS_PROCESS_GUARD_STRACE_NET` | strace `%net`. |
| `--diagnostic-dir <path>` | `BS_PROCESS_GUARD_DIAGNOSTIC_DIR` | Каталог отчёта. По умолчанию `mktemp -d`. |
| `--kill-signal <SIG>` | `BS_PROCESS_GUARD_KILL_SIGNAL` | Сигнал завершения, по умолчанию `TERM`. |
| `--grace-period <сек>` | `BS_PROCESS_GUARD_GRACE_PERIOD` | Время между сигналом и `KILL`, по умолчанию 5. |
| `--sudo` / `--no-sudo` | `BS_PROCESS_GUARD_SUDO` | Принудительно использовать/игнорировать `sudo` для strace. |

## Коды возврата

- код команды — при нормальном завершении;
- `124` (`IO_PROCESS_EXIT_TIMEOUT`) — сработал `--timeout`;
- `125` (`IO_PROCESS_EXIT_HANG`) — сработал `--hang-after`;
- `126` (`IO_PROCESS_EXIT_KILLED`) — процесс пришлось убивать принудительно;
- `2` (`E_INVALID`) — ошибка в аргументах.

## Примеры

```bash
# Ограничить загрузку файла 60 секундами
io::process::guard --timeout 60 -- wget https://example.com/file.iso

# Считать зависшим, если 30 секунд нет вывода
io::process::guard --timeout 120 --hang-after 30 -- ./long-task

# Собирать сетевой strace при зависании
io::process::guard --timeout 120 --hang-after 30 --strace-net \
  --diagnostic-dir /var/log/bs/guard -- ./server
```

## Диагностический отчёт

При срабатывании сторожа в указанном (или автоматическом) каталоге создаётся:

- `report.log` — время, причина, PID, командная строка, `ps`, `/proc/<pid>/status`,
  `cmdline`, `stack`, список `fd/`, `wchan`;
- `strace_file.log` — strace с фильтром `read,write,%file` (если доступен strace
  и root/парольless sudo);
- `strace_net.log` — strace с фильтром `%net` (если запрошен `--strace-net`).

## Сухой прогон

При `FRAMEWORK_DRY_RUN=true` сторож только логирует команду и не запускает её.

```bash
export FRAMEWORK_DRY_RUN=true
io::process::guard --timeout 60 -- sleep 10
```

## См. также

- [io-streams.md](io-streams.md) — управление потоками ввода/вывода.
- [io-files.md](io-files.md) — файловые операции.
