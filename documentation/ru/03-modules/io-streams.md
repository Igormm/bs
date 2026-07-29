[↑ Оглавление](../README.md)

# Модуль `io::streams`

Абстракция потоков ввода/вывода, файловых дескрипторов и перенаправлений:
безопасный вывод, `exec`-перенаправления, save/restore FD, pipe,
буферизация stdio и специальные файлы `/dev`.

Исходник: [lib/io/streams.sh](../../../lib/io/streams.sh)

## Загрузка

```bash
#!/usr/bin/env bs

load "lib/io/streams"
```

Или вручную:

```bash
source bootstrap/init.sh
load "lib/io/streams"
```

## Вывод

`print` использует `printf '%s\n'` вместо `echo`, поэтому значения `-n`, `-e`
и строки с обратными слэшами выводятся как есть. `printf` принимает формат
отдельным аргументом — данные никогда не попадают в строку формата.

```bash
io::streams::print "hello"        # строка с переводом строки
io::streams::printn "no newline"  # без перевода строки
io::streams::printf '%04d' 7      # форматированный вывод (format-string safe)
io::streams::eprint "to stderr"   # строка в stderr
io::streams::tty_print "bypass"   # в /dev/tty мимо перенаправлений
```

`tty_print` пишет в управляющий терминал, даже когда stdout/stderr
перенаправлены в файл или pipe; возвращает 1, если управляющего терминала нет.

## Ввод

```bash
io::streams::read_line var            # одна строка из stdin в переменную
io::streams::read_line var 3          # одна строка из FD 3
io::streams::read_all < file.txt      # весь поток до EOF
io::streams::feed "input" grep data   # подать строку на stdin команды (<<<)
```

`read_line` возвращает 1 при EOF, поэтому её удобно использовать в циклах
`while`. `feed` — обёртка над here-string (`<<<`); возвращает код возврата
команды.

## Перенаправления и save/restore FD

Перенаправления действуют на **текущий** shell (`exec`). Если нужно сохранить
свои потоки, выполняйте их в подоболочке `( ... )`.

```bash
io::streams::redirect_stdout "out.log"    # exec 1>file
io::streams::redirect_stderr "err.log"    # exec 2>file
io::streams::redirect_all "all.log"       # exec >file 2>&1 — порядок важен:
                                          # сначала >file, затем 2>&1
io::streams::silence                      # exec >/dev/null 2>&1
```

Для временного перенаправления сначала сохраните FD, а затем восстановите его:

```bash
io::streams::save 1 saved_fd        # аналог dup(1); номер нового FD — в
                                    # переменную, НЕ через $(...)
                                    # (подоболочка закроет дескриптор)
io::streams::redirect_stdout "capture.log"
# ... вывод уходит в capture.log ...
io::streams::restore "${saved_fd}" 1   # dup2 + close временного FD (нет утечек)
io::streams::close 3                   # exec 3>&-
```

Сохранять и восстанавливать можно только стандартные FD 0, 1, 2. `restore`
закрывает временный дескриптор, чтобы избежать утечки FD (`EMFILE`).

## Pipe и буферизация stdio

```bash
io::streams::pipe printf 'a\nb\n' -- grep b   # cmd1 | cmd2, '--' — разделитель
io::streams::run_line_buffered tail -f app.log  # stdbuf -oL -eL
io::streams::run_unbuffered long_task           # stdbuf -o0 -e0
```

Напоминание: stdout построчно буферизуется на терминале и полностью — в
pipe/файле; stderr не буферизуется вовсе. Хелперы `run_*` требуют `stdbuf`
и проверяют его наличие через `utils::has`; если `stdbuf` нет, возвращают 1.

## Специальные файлы `/dev`

```bash
io::streams::null_sink noisy_cmd      # cmd >/dev/null 2>&1, код возврата сохраняется
io::streams::random_bytes 32 | base64 # N байт из /dev/urandom (не блокирует)
io::streams::fd_path 0                # выводит /dev/fd/0
io::streams::list_fds                 # открытые FD через /proc/self/fd (или /dev/fd)
```

Для разового подавления вывода вне этого модуля используйте идиомы из
[core/utils.sh](../../../core/utils.sh): `utils::quiet cmd`
(`cmd >/dev/null 2>&1`), `utils::quiet_err cmd` (`cmd 2>/dev/null`) или
`utils::ignore cmd` (`cmd >/dev/null 2>&1 || true`) — `null_sink` является
эквивалентом `utils::quiet` на уровне модуля.

## Проверки состояния потоков

```bash
io::streams::is_tty 1              # привязан ли FD 1 к терминалу ([[ -t 1 ]])
io::streams::can_read 0            # неблокирующая проверка готовности к чтению
                                   # (данные не извлекаются)
io::streams::wait_readable 0 5     # ожидание данных до 5 с (аналог poll/select);
                                   # при успехе извлекает 1 байт
```

Типичное применение `is_tty`: включать цвета и прогресс-бары только на
терминале. Обратите внимание на разницу: `can_read` проверяет без извлечения
данных, а `wait_readable` при успехе извлекает один байт.

## Примеры

Запускаемые демо (из корня репозитория):

```bash
bs run examples/iostreams_output_example.sh           # print/printn/printf/eprint/tty_print
bs run examples/iostreams_input_example.sh            # read_line/read_all/feed
bs run examples/iostreams_redirection_example.sh      # redirect_*/silence
bs run examples/iostreams_fd_example.sh               # save/restore/close
bs run examples/iostreams_pipe_buffering_example.sh   # pipe/run_line_buffered/run_unbuffered
bs run examples/iostreams_dev_example.sh              # null_sink/random_bytes/fd_path/list_fds
bs run examples/iostreams_state_example.sh            # is_tty/can_read/wait_readable
bs run examples/logmonitorexample.sh                  # живой монитор: can_read + pipe + /dev/fd
```

Исходники: [examples/iostreams_output_example.sh](../../../examples/iostreams_output_example.sh),
[examples/iostreams_input_example.sh](../../../examples/iostreams_input_example.sh),
[examples/iostreams_redirection_example.sh](../../../examples/iostreams_redirection_example.sh),
[examples/iostreams_fd_example.sh](../../../examples/iostreams_fd_example.sh),
[examples/iostreams_pipe_buffering_example.sh](../../../examples/iostreams_pipe_buffering_example.sh),
[examples/iostreams_dev_example.sh](../../../examples/iostreams_dev_example.sh),
[examples/iostreams_state_example.sh](../../../examples/iostreams_state_example.sh),
[examples/logmonitorexample.sh](../../../examples/logmonitorexample.sh).
