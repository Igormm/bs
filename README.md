# 🐚 BS Framework

> 🇷🇺 Русская версия · 🇬🇧 [English version](README.en.md)

[![CI](https://github.com/Igormm/bs/actions/workflows/ci.yml/badge.svg)](https://github.com/Igormm/bs/actions/workflows/ci.yml)
![bash 4.2+](https://img.shields.io/badge/bash-4.2%2B-4EAA25?logo=gnubash&logoColor=white)
![kernel POSIX sh](https://img.shields.io/badge/ядро-POSIX%20sh-blue)
[![MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

**BS — модульный фреймворк и стандартная библиотека для shell-скриптов.**
Пишешь скрипт, подключаешь нужные модули через `load`, остальное берёт на
себя фреймворк.

<p align="center">
  <img src="documentation/assets/tui-demo.gif" alt="TUI на BS: скруглённые рамки, задачи, модалка и прогресс" width="760">
</p>

## ✨ Почему BS

- 📦 **Загрузчик модулей** с разрешением зависимостей: `load "lib/io/streams"`, и всё нужное подтянется само
- 📝 **Логирование** и 🛡️ **обработка ошибок** из коробки
- ⚙️ **Параметры скрипта одной декларацией**: валидация, `--help` и автодополнение сами
- 🖥️ **TUI на чистом bash**: окна, меню, модалки, мышь
- 🧰 **100+ модулей**: файлы, процессы, сеть, железо, сервисы, HTTP, LLM, Kubernetes
- 📦 **`bs build`**: скрипт и фреймворк в одном файле, который работает без установки
- 🐚 **Ядро на POSIX sh**, стандартная библиотека на Bash 4.2+
- 🎯 **Ноль внешних зависимостей** и единый стиль кода

## 🚀 Быстрый старт

```bash
git clone https://github.com/Igormm/bs.git && cd bs   # скачать репозиторий и перейти в него

./bs run examples/hello.sh     # запустить первый скрипт
./bs repl                      # открыть интерактивную консоль
./bs doctor                    # проверить, что все файлы фреймворка на месте
```

Понравилось? Установите команду `bs` себе в `PATH`:

```bash
./install.sh --local           # установить в ~/.local, права root не нужны
```

## 👋 Примеры

### Hello, world

```bash
#!/usr/bin/env bs
# ↑ шебанг: скрипт запускает интерпретатор bs, а не голый bash

load "lib/io/streams"          # подключить модуль вывода (зависимости подтянутся сами)

io::streams::print "hello from BS $(bs::version::get)"   # напечатать строку с версией BS
```

```console
$ bs run examples/hello.sh
hello from BS 0.20.0
```

### 📝 Логи без лишнего кода

Логгер и проверки вроде `is::file` доступны сразу, без `load`:

```bash
#!/usr/bin/env bs
# ↑ шебанг: логгер и is::* уже загружены, load не нужен

log::info "Начинаю резервную копию"                # обычное сообщение с меткой времени
if is::file "/etc/hostname"; then                   # есть ли такой обычный файл?
    log::success "Файл на месте, можно копировать"  # да: зелёное сообщение об успехе
else                                                # иначе
    log::warn "Файла нет, пропускаю"                # нет: жёлтое предупреждение
fi                                                  # конец условия
```

```console
[2026-11-11 08:06:35] INFO  Начинаю резервную копию
[2026-11-11 08:06:35] SUCCESS Файл на месте, можно копировать
```

### ⚙️ Скрипт с параметрами

Описываете параметры один раз, а проверку, сообщения об ошибках и `--help`
BS делает сам. Значения читаются по смыслу: `args::param 1` (первое слово
команды) и `args::flag_get name` (значение `--name`).

```bash
#!/usr/bin/env bs
# ↑ шебанг: запуск через интерпретатор bs

load "core/args"                       # модуль разбора параметров командной строки
load "lib/io/streams"                  # модуль вывода

main() {                               # главная функция скрипта
    args::level 1 hello goodbye        # первое слово команды: hello или goodbye
    args::flag name value world        # флаг --name со значением, по умолчанию world
    args::flag loud                    # флаг-переключатель --loud без значения
    args::required 1                   # первое слово обязательно
    args::require "$@"                 # разобрать аргументы; при ошибке показать справку и выйти

    local -r command="$(args::param 1)"      # первое слово после имени скрипта
    local -r name="$(args::flag_get name)"   # значение --name или дефолт world
    local msg                                # переменная для итогового текста
    case "${command}" in                     # выбрать текст по команде
        hello)   msg="Hello, ${name}!" ;;    # приветствие
        goodbye) msg="Goodbye, ${name}!" ;;  # прощание
    esac                                     # конец выбора
    args::flag_is_set loud && msg="${msg^^}" # с --loud перевести текст в ВЕРХНИЙ регистр
    io::streams::print "${msg}"              # напечатать результат
}

main "$@"                              # вызвать main со всеми аргументами скрипта
```

```console
$ bs run examples/greet.sh hello --name Мир
Hello, Мир!
$ bs run examples/greet.sh goodbye --loud
GOODBYE, WORLD!
```

Полная версия с описаниями для `--help`: [examples/greet.sh](examples/greet.sh).

### 🎛️ Меню в терминале

<img src="documentation/assets/tui-menu.png" alt="TUI-меню со скруглённой рамкой" width="320" align="right">

`↑↓` выбор, `Enter` действие, `q` выход. Полный пример с циклом
обработки клавиш: [examples/menu.sh](examples/menu.sh).

```bash
load "lib/tui/tui"                                       # подключить TUI-библиотеку

main() {                                                 # главная функция
    local -a items=("Run checks" "Show status" "Quit")   # пункты меню
    local -i sel=0                                       # номер выбранного пункта

    tui::init                                # включить полноэкранный режим
    tui::menu 2 2 items "${sel}" "Menu"      # меню в строке 2, колонке 2, в скруглённой рамке
    tui::render                              # вывести кадр на экран
    tui::key_read                            # ждать клавишу: она окажется в $TUI_KEY
    # ...                                    # дальше: обработать клавишу и перерисовать
}
```

<br clear="right">

## 🖼️ Что можно собрать на BS

Всё это лежит в [examples/](examples/) и запускается одной командой.

| | |
|---|---|
| ✅ **Список задач** `examples/todo.sh`<br>Окна, модалки, файл задач. | <img src="documentation/assets/todo.gif" alt="TUI todo: добавление, отметка и удаление задач" width="420"> |
| 🔐 **Мастер настройки sshd** `examples/sshd_wizard.sh --dry-run`<br>Профили, подсказка к каждому параметру, безопасное применение. | <img src="documentation/assets/tui-sshd.gif" alt="Мастер sshd: секции, параметры и подсказки" width="420"> |
| 🌍 **Мастер локали** `examples/locale_wizard.sh`<br>Шаги, выбор языка, кодировки и раскладки. | <img src="documentation/assets/tui-locale.gif" alt="Мастер локали по шагам" width="420"> |
| 🌐 **Сеть** `examples/netconn.sh`<br>Интерфейсы, адреса, трафик в реальном времени. | <img src="documentation/assets/tui-netconn.png" alt="Сетевой TUI" width="420"> |
| 🧩 **Демо TUI** `examples/tui_demo.sh`<br>Секции, список задач, модалка ввода, прогресс. | <img src="documentation/assets/tui-demo.png" alt="Демо TUI" width="420"> |

Ещё примеры:

- 🛡️ `fail2ban_wizard.sh`, `ntp_wizard.sh`, `locale_wizard.sh`: мастера настройки системы
- 🔑 `openbao_wizard.sh`: установка OpenBao, [подробнее](documentation/ru/03-modules/system-openbao.md)
- 🛰️ `vpn.sh`: VPN-клиент на sing-box и Xray с TUI, [подробнее](documentation/ru/03-modules/network-vpn.md)
- 💓 `pulse.sh`, `sysdiag.sh`: быстрый осмотр машины
- 🌍 `http_example.sh`, `llm_example.sh`, `k8s_example.sh`: интеграции

## 🧰 Инструменты `bs`

<p align="center">
  <img src="documentation/assets/bs-cli.gif" alt="bs version, bs version --full и bs help в терминале" width="640">
</p>

| Команда | Что делает |
|---|---|
| `bs run script.sh` | запустить скрипт (или `#!/usr/bin/env bs` в шапке) |
| `bs repl` | консоль с загруженным ядром, `:list`, `:doc`, `:info` |
| `bs calc '2 3 4 * +'` | RPN-калькулятор |
| `bs list` | список модулей |
| `bs build script.sh` | один самодостаточный файл, работает без установки BS |
| `bs doctor` | проверка целостности |
| `bs update` | обновить установленные копии |
| `bs where` | найти все установки BS на машине |
| `bs version [--full]` | версия; с `--full` ещё путь, вид установки и коммит |
| `bs help [команда]` | список команд или подробная справка по одной |

<details>
<summary>📸 Скриншоты <code>bs version</code> и <code>bs help</code></summary>

![bs version и bs version --full](documentation/assets/bs-version.png)

![bs help: все команды по группам](documentation/assets/bs-help.png)

</details>

## 📦 Установка

```bash
./install.sh --local      # для себя: ~/.local/bin/bs, без sudo
sudo ./install.sh         # для всех пользователей: /usr/local/bin/bs
```

Установщик копирует фреймворк, так что клон потом можно удалить. Виды
установки, обновление и удаление описаны в
[documentation/ru/install.md](documentation/ru/install.md).

**Что нужно:** Linux и Bash 4.2+ (CI проверяет 4.4–5.x на ubuntu, debian и
almalinux 8–9). Запускать `bs` можно из любой оболочки: он сам найдёт bash.

## 🗂️ Устройство

```
bs              CLI и интерпретатор
bootstrap/      загрузчик модулей
core/           ядро: args, logger, errorhandler, utils, lang …
lib/            стандартная библиотека: io, tui, system, network, integration …
examples/       примеры
tests/          тесты
documentation/  документация на русском и английском
```

## 🧪 Тесты

```bash
bash tests/runalltests.sh          # запустить весь набор тестов
bash tests/validateshellcheck.sh   # проверить код линтером ShellCheck
```

## 📚 Документация

- 🏁 [Начало работы](documentation/ru/01-getting-started/README.md)
- ✍️ [Первый скрипт: пошаговый урок](documentation/ru/05-tutorials/first-script.md)
- 🏗️ [Архитектура](documentation/ru/02-core-concepts/architecture.md)
- 🧩 [Обзор модулей](documentation/ru/03-modules/lib-modules-overview.md)
- 📖 [Справочник API ядра](documentation/ru/04-api-reference/core-api.md)
- 🎨 [Стиль кода](documentation/ru/code-style-guide.md)
- 🇬🇧 [English documentation](documentation/en/README.md)

## 💡 Принципы

- **Bash есть везде:** ничего не нужно ставить.
- **Это bash, а не новый язык:** вся экосистема bash открыта, `bash -x` работает.
- **Без магии:** каждая строка читается как обычный bash.
- **Для эксплуатации:** cron, CI, Docker, один файл через `bs build`.
- **Честные границы:** тяжёлую работу с данными отдаём jq или Go через JSON.

## 📄 Лицензия

MIT, см. [LICENSE](LICENSE).
