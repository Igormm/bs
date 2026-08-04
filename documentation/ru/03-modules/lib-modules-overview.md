# Обзор модулей lib

[↑ Оглавление](../README.md)

Каталог `lib/` содержит необязательные функциональные модули, построенные поверх `core/`. В отличие от `core/`, ничто здесь не загружается автоматически — скрипт загружает только нужные ему модули.

Модули загружаются функцией `load`, которая разрешает пути относительно `BS_ROOT` (расширение `.sh` опускается):

```bash
#!/usr/bin/env bs

load "core/args"
load "lib/io/streams"
load "lib/system/info"
```

Или из обычного bash-скрипта:

```bash
source bootstrap/init.sh
load "lib/data/dataprocessor"
```

Большинство модулей lib следуют одним соглашениям: функция `<module>::init`, пара `<module>::check_dependencies` / `<module>::install_dependencies` там, где нужны внешние инструменты, и справочная функция `<module>::info`. Внутри модули опираются на идиомы core, описанные в [core-utils.md](core-utils.md), — например, `utils::has cmd` вместо `command -v cmd >/dev/null 2>&1` и `utils::quiet cmd` вместо `cmd >/dev/null 2>&1`.

## io — `lib/io/`

- [streams.sh](../../../lib/io/streams.sh) — низкоуровневое управление потоками ввода-вывода: вывод, чтение, перенаправление файловых дескрипторов, каналы и определение TTY.
- [files.sh](../../../lib/io/files.sh) — высокоуровневые файловые операции: копирование, перемещение, синхронизация и удаление файлов/каталогов с dry-run и единой обработкой ошибок.
- [process.sh](../../../lib/io/process.sh) — обёртка-сторож процесса: таймаут, hang-детекция по stdout/stderr, диагностический снимок `/proc/<pid>` и `strace`.

Ключевые функции: `io::streams::print`, `io::streams::read_line`, `io::streams::redirect_stdout`, `io::streams::pipe`, `io::files::copy_dir`, `io::files::sync_dir`, `io::files::copy_matching`, `io::files::move`, `io::files::remove`, `io::process::guard`.

Подробнее: [io-streams.md](io-streams.md), [io-files.md](io-files.md), [io-process.md](io-process.md)

## system — `lib/system/`

Самая большая группа: обёртки над повседневным администрированием Linux. Модули: [devices.sh](../../../lib/system/devices.sh), [display.sh](../../../lib/system/display.sh), [distro.sh](../../../lib/system/distro.sh) (определение дистрибутива), [distrologic.sh](../../../lib/system/distrologic.sh) (логика пакетов и сервисов по дистрибутивам), [info.sh](../../../lib/system/info.sh), [keyboard.sh](../../../lib/system/keyboard.sh), [locale.sh](../../../lib/system/locale.sh), [logging.sh](../../../lib/system/logging.sh), [network.sh](../../../lib/system/network.sh), [packages.sh](../../../lib/system/packages.sh), [permissions.sh](../../../lib/system/permissions.sh), [platformcheck.sh](../../../lib/system/platformcheck.sh), [processes.sh](../../../lib/system/processes.sh), [routing.sh](../../../lib/system/routing.sh), [safety.sh](../../../lib/system/safety.sh) (dry-run / подтверждение действий), [security.sh](../../../lib/system/security.sh), [services.sh](../../../lib/system/services.sh), [system.sh](../../../lib/system/system.sh), [time.sh](../../../lib/system/time.sh), [users.sh](../../../lib/system/users.sh), [utils.sh](../../../lib/system/utils.sh).

Ключевые функции: `system::distro::detect`, `system::info::all`, `system::packages::install`, `safety::execute`.

## ui — `lib/ui/`

Терминальная презентация: помощники цветного вывода ([presentation.sh](../../../lib/ui/presentation.sh)), настраиваемые PS1-приглашения ([ps1config.sh](../../../lib/ui/ps1config.sh)) и тема приглашения BS ([bosatheme.sh](../../../lib/ui/bosatheme.sh)).

Ключевые функции: `presentation::header`, `presentation::table`, `ps1config::set_theme`, `bosatheme::apply`.

## network — `lib/network/`

- [sshnetwork.sh](../../../lib/network/sshnetwork.sh) — операции по SSH в локальной сети: обнаружение устройств, удалённое выполнение команд, передача файлов и туннели.

Ключевые функции: `sshnetwork::discover_devices`, `sshnetwork::execute_remote`, `sshnetwork::transfer_file`, `sshnetwork::create_tunnel`.

## data — `lib/data/`

- [dataprocessor.sh](../../../lib/data/dataprocessor.sh) — обработка и конвертация JSON, XML, CSV, YAML и TSV с запросами в стиле jq / XPath / JSONPath. Требует внешних инструментов (`jq`, `xmllint`, `python3`), устанавливаемых через `dataprocessor::install_dependencies`.

Ключевые функции: `dataprocessor::json::query`, `dataprocessor::xml::to_json`, `dataprocessor::csv::filter`, `dataprocessor::convert`.

## integration — `lib/integration/`

Клиенты для внешних сервисов, VPN-инструменты, LLM, Kubernetes и коннекторы к другим системам:
- [http.sh](../../../lib/integration/http.sh) — HTTP-клиент на базе `curl`/`wget` с dry-run, таймаутами и retries.
- [llm.sh](../../../lib/integration/llm.sh) — единый клиент для OpenAI и Ollama.
- [k8s.sh](../../../lib/integration/k8s.sh) — обёртка над `kubectl` с namespace по умолчанию и dry-run.
- [vkapi.sh](../../../lib/integration/vkapi.sh) — обёртка VK API с кэшированием и ограничением частоты запросов.
- [vkmusic.sh](../../../lib/integration/vkmusic.sh) — поиск и загрузка музыки VK.
- [wireguard.sh](../../../lib/integration/wireguard.sh) — управление интерфейсами и пирами WireGuard.
- [result.sh](../../../lib/integration/result.sh) — JSON-контракт результата операций для интеграции с Go-backend, HTTP API и CI.

Ключевые функции: `http::get`, `http::post`, `http::retry`, `llm::chat`, `llm::chat_file`, `k8s::pod::list`, `k8s::deployment::restart`, `k8s::apply`, `vkapi::api_call`, `vkmusic::search_and_download`, `wireguard::create_interface`, `wireguard::add_peer`, `result::run`, `result::wrap`, `result::ok`, `result::error`.

Подробнее: [integration-http.md](integration-http.md), [integration-llm.md](integration-llm.md), [integration-k8s.md](integration-k8s.md), [integration-result.md](integration-result.md)

## frameworks — `lib/frameworks/`

- [frameworksintegration.sh](../../../lib/frameworks/frameworksintegration.sh) — прослойки совместимости, которые предоставляют идеи других bash-фреймворков (bash-it, bashinator, bashly, ShellSpec, MBFL) через единый API `frameworks::*`.

Ключевые функции: `frameworks::bashit::load_plugin`, `frameworks::bashly::parse_args`, `frameworks::shellspec::describe`, `frameworks::shellspec::run`.

## status — `lib/status/`

- [ps1status.sh](../../../lib/status/ps1status.sh) — живые индикаторы состояния, встраиваемые в PS1-приглашение: WireGuard, задержка сети, скорость загрузки, громкость, CPU/память. Компоненты включаются по отдельности и обновляются фоновым циклом мониторинга.

Ключевые функции: `ps1status::enable_component`, `ps1status::enable`, `ps1status::disable`, `ps1status::audio::toggle_mute`.

## audit — `lib/audit/`

- [systemaudit.sh](../../../lib/audit/systemaudit.sh) — аудит безопасности и соответствия Linux-хоста: конфигурация SSH, файрвол, пользователи и sudo, открытые порты, права файловой системы, сервисы. Отчёты формируются в text, JSON, CSV или XML.

Ключевые функции: `systemaudit::run`, `systemaudit::run_full`, `systemaudit::security::check_ssh_config`, `systemaudit::network::check_open_ports`.

## automation — `lib/automation.sh`

Единый высокоуровневый модуль, который собирает строительные блоки `lib/system/` в рабочие процессы вида «проверить/выполнить/удостовериться»: настройка локали и часового пояса, устройства ввода, установка display-сервера и desktop-окружения, сетевые интерфейсы и маршруты, сервисы и пакеты.

Ключевые функции: `automation::locale::set_locale`, `automation::system::manage_packages`, `automation::display::detect_desktop_environment`, `automation::network::manage_interface`.

## См. также

- [args.md](args.md) — модуль разбора аргументов `core/args`, используемый многими скриптами
- [io-streams.md](io-streams.md) — подробный справочник по `lib/io/streams`
- [core-utils.md](core-utils.md) — идиомы core-утилит (`utils::has`, `utils::quiet`, `utils::ignore`)
