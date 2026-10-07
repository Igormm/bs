# BS Framework Examples / Примеры фреймворка BS

This directory contains runnable scripts that demonstrate BS modules and
conventions. Each script is self-contained and can be launched with `./bs run`
or directly if `bs` is on `PATH`.

В этом каталоге — запускаемые скрипты, демонстрирующие модули и конвенции BS.
Каждый скрипт самодостаточен: запускайте через `./bs run` или напрямую,
если `bs` есть в `PATH`.

Full guides: [documentation/en/06-examples](../documentation/en/06-examples/README.md)
· [ru](../documentation/ru/06-examples/README.md).

## Quick start / Быстрый старт

```bash
# Run a tiny script
./bs run examples/hello.sh

# Or make it executable and run directly
chmod +x examples/hello.sh
./examples/hello.sh
```

A minimal BS script looks like this / минимальный скрипт BS выглядит так:

```bash
#!/usr/bin/env bs
# shellcheck shell=bash

load "lib/io/streams"

io::streams::print "hello from BS"
```

## Examples index / Оглавление примеров

### Core and parsing / Ядро и парсинг аргументов

- `argsparseexample.sh` — parameter tree, flags, auto-help and bash completion /
  дерево параметров, флаги, авто-help и bash-completion
- `bs_test.sh` — smoke test of core and basic lib modules /
  дымовой тест ядра и базовых lib-модулей
- `greet.sh` — short script with `core/args` tree and flags /
  короткий скрипт с деревом параметров и флагами
- `hello.sh` — shortest useful BS script / самый короткий полезный скрипт BS

### Input/output / Ввод-вывод

- `filesops_example.sh` — `lib/io/files` usage demo (copy, move, find) /
  демо модуля файловых операций
- `filesops_atomic_example.sh` — atomic copy, backup and move-fallback /
  атомарное копирование, бэкапы и move-fallback
- `iostreams_output_example.sh` — safe output (`print`, `printf`, `eprint` …) /
  безопасный вывод
- `iostreams_input_example.sh` — input helpers (`read_line`, `read_all`, `feed`) /
  функции ввода
- `iostreams_redirection_example.sh` — `exec`-based redirections /
  перенаправления на `exec`
- `iostreams_fd_example.sh` — FD save/restore/close /
  управление файловыми дескрипторами
- `iostreams_pipe_buffering_example.sh` — pipes and stdio buffering control /
  pipe и управление буферизацией
- `iostreams_state_example.sh` — TTY detection and non-blocking reads /
  определение терминала и неблокирующее чтение
- `iostreams_dev_example.sh` — `/dev/null`, `/dev/urandom`, `/dev/fd/N` /
  специальные файлы `/dev`
- `processguard_example.sh` — `io::process::guard` timeout/respawn wrapper /
  обёртка-сторож с таймаутом

### System and hardware / Система и оборудование

- `sysdiag.sh` — system diagnostics CLI with args, logger and result contract /
  CLI диагностики системы
- `hw_example.sh` — CPU, memory, block and GPU info getters /
  геттеры информации об оборудовании
- `gpu_diag.sh` — GPU diagnostic and stress CLI /
  диагностика и нагрузочный тест видеокарты
- `pulse.sh` — capability pulse of the host (tier, userland, tools, hardware) /
  пульс возможностей машины
- `sensor_diag.sh` — touch sensor device diagnostic /
  диагностика сенсорных устройств
- `sensor_tui.sh` — touch sensor real-time monitor TUI /
  TUI-монитор сенсорного устройства

### Integration modules / Интеграции

- `http_example.sh` — HTTP client demo / демо HTTP-клиента
- `llm_example.sh` — LLM client demo / демо LLM-клиента
- `k8s_example.sh` — Kubernetes client helpers demo / демо Kubernetes-клиента
- `result_example.sh` — JSON result contract for integrations /
  JSON-контракт результата для интеграций

### TUI, wizards and apps / TUI, визарды и приложения

- `app_demo.sh` — beginner TUI window with buttons /
  TUI для новичков: окно и кнопки
- `menu.sh` — minimal interactive menu / минимальное интерактивное меню
- `tui_demo.sh` — full TUI framework demo (lists, modals, progress) /
  полноценное демо TUI-фреймворка
- `todo.sh` — terminal todo list on `lib/tui/app` /
  терминальный список задач
- `wizard_example.sh` — interactive setup wizard with Unicode frames /
  интерактивный установщик
- `sshd_wizard.sh` — interactive sshd config builder /
  визард сборки конфига sshd
- `ai_user_wizard.sh` — restricted AI-user sandbox wizard /
  визард песочницы для ИИ-пользователя
- `opencode_serve_wizard.sh` — interactive wizard for the opencode server /
  визард запуска opencode-сервера
- `opencode_serve.sh` — helper that starts the opencode server /
  помощник запуска opencode-сервера

### Complete small tools / Законченные мини-инструменты

- `deploytoolexample.sh` — mini deploy tool with args + FD logging /
  мини-утилита деплоя
- `passwordgenexample.sh` — `/dev/urandom` password generator /
  генератор паролей
- `logmonitorexample.sh` — live log monitor with non-blocking reads /
  живой монитор лога
- `quizgameexample.sh` — timed quiz with `wait_readable` /
  викторина с таймаутом

### Other / Прочее

- `ps1configurationexample.sh` — PS1 prompt configuration examples /
  примеры настройки приглашения PS1
- `tree_example.sh` — generate a project tree from YAML/TXT/INI/CSV /
  дерево проекта из текстовых форматов
- `demo.sh` — asciinema-style framework demo / демо в стиле asciinema

### Output contract examples / Примеры контракта вывода

The `output_contract/` subdirectory contains focused demos of BS output
primitives. Run them with `./bs run examples/output_contract/<name>.sh`.

Подкаталог `output_contract/` содержит узкие демо примитивов вывода BS.
Запуск: `./bs run examples/output_contract/<name>.sh`.

- `boxed.sh` — boxed text / рамка-текст
- `bullets.sh` — bulleted lists / маркированные списки
- `formats.sh` — string/json/xml representations / представления данных
- `header_box.sh` — header boxes / рамка-заголовок
- `log_levels.sh` — logger levels / уровни лога
- `noop_box.sh` — "nothing to do" framed notice / рамка «ничего не сделано»
- `notices.sh` — one-line notices / однострочные уведомления
- `progress.sh` — inline progress bars / инлайн-бары прогресса
- `steplog.sh` — step log with guaranteed flush / журнал шагов
- `table.sh` — plain and framed tables / таблицы
- `tui_elements.sh` — full-screen TUI elements / полноэкранные TUI-элементы

## Creating new examples / Создание новых примеров

When adding an example, follow the existing conventions:

1. Use `#!/usr/bin/env bs` and `# shellcheck shell=bash` on the first two lines.
2. Load framework modules with `load "core/..."` or `load "lib/..."`;
   do not `source` them directly.
3. Add bilingual comments: English line followed by Russian line (or vice versa).
4. Include a short "Run / Запуск" usage comment.
5. Keep the script self-contained and runnable non-interactively when possible.
6. Update this README with the file and a one-line description.

При добавлении примера соблюдайте существующие конвенции:

1. Первые две строки: `#!/usr/bin/env bs` и `# shellcheck shell=bash`.
2. Загружайте модули фреймворка через `load "core/..."` или `load "lib/..."`;
   не используйте прямой `source`.
3. Добавляйте двуязычные комментарии: строка на английском и строка на русском.
4. Включайте короткий комментарий «Run / Запуск».
5. Скрипт должен быть самодостаточным и по возможности запускаться
   неинтерактивно.
6. Обновляйте этот README: имя файла и однострочное описание.

## License / Лицензия

Examples are part of the BS framework and follow the same licensing terms.
Примеры являются частью фреймворка BS и распространяются на тех же условиях.
