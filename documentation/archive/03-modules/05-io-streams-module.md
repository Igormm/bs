# Модуль io::streams (lib/io/streams.sh)

Абстракция потоков ввода/вывода, файловых дескрипторов и перенаправлений:
безопасный вывод, `exec`-перенаправления, save/restore FD, pipe,
буферизация stdio и специальные файлы `/dev`.

An abstraction over I/O streams, file descriptors and redirections:
safe output, `exec` redirections, FD save/restore, pipes, stdio
buffering and `/dev` special files.

## Загрузка / Loading

```bash
load "lib/io/streams"
```

## Вывод / Output

```bash
io::streams::print "hello"        # printf '%s\n' — не ломается на -n, -e
io::streams::printn "no newline"  # printf '%s'
io::streams::printf '%04d' 7      # формат отдельным аргументом (format-string safe)
io::streams::eprint "to stderr"
io::streams::tty_print "bypass"   # в /dev/tty мимо перенаправлений
```

## Ввод / Input

```bash
io::streams::read_line var            # одна строка stdin в переменную
io::streams::read_all < file.txt      # весь поток до EOF
io::streams::feed "input" grep data   # here-string <<< команде
```

## Перенаправления / Redirections

Действуют на текущий shell (`exec`); для изоляции используйте подоболочки:

```bash
io::streams::redirect_stdout "out.log"    # exec 1>file
io::streams::redirect_stderr "err.log"    # exec 2>file
io::streams::redirect_all "all.log"       # exec >file 2>&1 (порядок важен!)
io::streams::silence                      # exec >/dev/null 2>&1
```

## Файловые дескрипторы / File descriptors

```bash
io::streams::save 1 saved_fd      # аналог dup(1); номер — в переменную,
                                  # НЕ через $(...) (подоболочка убьёт FD)
io::streams::redirect_stdout "capture.log"
io::streams::restore "${saved_fd}" 1   # dup2 + close временного FD (нет утечек)
io::streams::close 3
```

## Pipe и буферизация / Pipes and buffering

```bash
io::streams::pipe printf 'a\nb\n' -- grep b   # cmd1 | cmd2
io::streams::run_line_buffered tail -f app.log  # stdbuf -oL -eL
io::streams::run_unbuffered long_task           # stdbuf -o0 -e0
```

## Состояние потоков / Stream state

```bash
io::streams::is_tty 1              # [[ -t 1 ]]
io::streams::can_read 0            # неблокирующая проверка (данные не извлекаются)
io::streams::wait_readable 0 5     # ожидание с таймаутом (poll/select;
                                   # при успехе извлекает 1 байт)
```

## Специальные файлы /dev

```bash
io::streams::null_sink noisy_cmd    # cmd >/dev/null 2>&1, код возврата сохраняется
io::streams::random_bytes 32        # /dev/urandom (не блокирует)
io::streams::fd_path 0              # /dev/fd/0
io::streams::list_fds               # /proc/self/fd
```

## Примеры / Examples

```bash
bs run examples/iostreams_output_example.sh
bs run examples/iostreams_redirection_example.sh
bs run examples/logmonitorexample.sh   # живой монитор: can_read + pipe
```
