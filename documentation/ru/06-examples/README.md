[↑ Оглавление](../README.md)

# Обзор примеров

Каталог [examples/](../../../examples/) содержит запускаемые скрипты,
демонстрирующие модули фреймворка на реальных задачах. Все примеры —
автономные скрипты BS: они начинаются с shebang `#!/usr/bin/env bs`
и подключают модули через `load "core/args"`, `load "lib/io/streams"` и т.п.

## Запуск примеров

Из корня репозитория:

```bash
./bs run examples/<file> [args]
```

Если `bs` находится в `PATH`, скрипты можно запускать напрямую:

```bash
./examples/<file> [args]
```

## Примеры

| Файл | Что демонстрирует | Запуск |
| --- | --- | --- |
| [bs_test.sh](../../../examples/bs_test.sh) | Дымовой тест: загрузка core-модулей (`core/version`, `core/logger`, `core/const`, `core/errorhandler`) и базовый вывод `log::info` / `log::warn` / `log::error` | `./bs run examples/bs_test.sh` |
| [argsparseexample.sh](../../../examples/argsparseexample.sh) | Модуль `args`: дерево параметров (`args::level`, `args::describe`), флаги, автоматическая валидация и help, bash completion | `./bs run examples/argsparseexample.sh deploy now`<br>`./bs run examples/argsparseexample.sh --help` |
| [deploytoolexample.sh](../../../examples/deploytoolexample.sh) | Мини-утилита деплоя: связка `args` + `io::streams` — дерево параметров, флаги `--env` / `--dry-run`, авто-help, логирование секции деплоя в файл через FD `save` / `restore` | `./bs run examples/deploytoolexample.sh deploy --env production --dry-run` |
| [passwordgenexample.sh](../../../examples/passwordgenexample.sh) | Генератор паролей из `/dev/urandom` с флагами `--length`, `--count`, `--hex` и оценкой стойкости | `./bs run examples/passwordgenexample.sh --length 24 --count 5` |
| [logmonitorexample.sh](../../../examples/logmonitorexample.sh) | Живой монитор лога: фоновый «сервис» пишет в pipe, монитор читает его неблокирующе через `io::streams::can_read` и считает статистику по ERROR | `./bs run examples/logmonitorexample.sh` |
| [quizgameexample.sh](../../../examples/quizgameexample.sh) | Викторина с таймаутом: ответ ждётся через `io::streams::wait_readable` (аналог poll/select) вместо блокирующего `read`; без терминала — авто-режим | `./bs run examples/quizgameexample.sh` |
| [iostreams_output_example.sh](../../../examples/iostreams_output_example.sh) | Безопасный вывод: `io::streams::print`, `printn`, `printf`, `eprint`, `tty_print` | `./bs run examples/iostreams_output_example.sh` |
| [iostreams_input_example.sh](../../../examples/iostreams_input_example.sh) | Ввод: `io::streams::read_line`, `read_all`, `feed` | `./bs run examples/iostreams_input_example.sh` |
| [iostreams_redirection_example.sh](../../../examples/iostreams_redirection_example.sh) | Перенаправления: `io::streams::redirect_stdout`, `redirect_stderr`, `redirect_all`, `silence` | `./bs run examples/iostreams_redirection_example.sh` |
| [iostreams_fd_example.sh](../../../examples/iostreams_fd_example.sh) | Управление FD: `io::streams::save`, `restore`, `close` (аналоги dup/dup2) | `./bs run examples/iostreams_fd_example.sh` |
| [iostreams_pipe_buffering_example.sh](../../../examples/iostreams_pipe_buffering_example.sh) | Pipe и буферизация stdio: `io::streams::pipe`, `run_line_buffered`, `run_unbuffered` | `./bs run examples/iostreams_pipe_buffering_example.sh` |
| [iostreams_state_example.sh](../../../examples/iostreams_state_example.sh) | Проверка состояния потоков: `io::streams::is_tty`, `can_read`, `wait_readable` | `./bs run examples/iostreams_state_example.sh` |
| [iostreams_dev_example.sh](../../../examples/iostreams_dev_example.sh) | Специальные файлы `/dev`: `io::streams::null_sink` (`/dev/null`), `random_bytes` (`/dev/urandom`), `fd_path` (`/dev/fd/N`), `list_fds` (`/proc/self/fd`) | `./bs run examples/iostreams_dev_example.sh` |
| [ps1configurationexample.sh](../../../examples/ps1configurationexample.sh) | Интерактивная настройка приглашения PS1 через модуль `lib/ui/ps1config`: темы, git-информация, определение SSH и virtualenv, формат времени | `echo 7 \| ./bs run examples/ps1configurationexample.sh` |

## Дополнительная документация в examples/

- [examples/README.md](../../../examples/README.md) — подробное описание
  набора примеров (частично использует старое именование BOSA).
- [examples/README bs_test.md](../../../examples/README%20bs_test.md) —
  описание дымового теста `bs_test.sh`.
