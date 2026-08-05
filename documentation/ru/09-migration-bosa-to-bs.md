# Миграция с BOSA на BS

Проект переименован из **BOSA** в **BS** (Bash Open Source Architecture).
Эта заметка перечисляет переименования для тех, кто знал старую версию.


## Имена проекта и переменных

| Старое | Новое |
|--------|-------|
| BOSA / BashOSA | BS |
| `bosa::` | `bs::` |
| `BOSA_HOME` | `BS_HOME` |
| `#!/usr/bin/env bash` (как вход во фреймворк) | `#!/usr/bin/env bs` |

Примечания о текущем состоянии:

- Основная переменная корня теперь `BS_ROOT`, её устанавливает
  `bootstrap/init.sh`; `BS_HOME` сохранена как псевдоним `BS_ROOT` для
  lib-модулей (см. `bootstrap/init.sh` и entrypoint `bs`).
- Функции `bs::init` **не существует**. Инициализация — либо через shebang
  `#!/usr/bin/env bs` и `load "core/args"`, либо вручную:
  `source bootstrap/init.sh`, затем `load`.

## Logger переименован в log

| Старое | Новое |
|--------|-------|
| `logger::` | `log::` |

```bash
# Было:
logger::info "Message"
logger::debug "Debug info"

# Стало:
log::info "Message"
log::debug "Debug info"
```

Все функции `log::` находятся в `core/logger.sh` (`log::info`, `log::debug`,
`log::warn`, `log::error`, `log::success` и др.).

## Загрузка модулей

Модули больше не загружаются через `source lib/...`. Используйте `load`:

```bash
#!/usr/bin/env bs

load "core/args"
load "lib/io/streams"
```

Или в обычном bash-скрипте:

```bash
source /path/to/bs/bootstrap/init.sh
load "core/args"
```

## Переименованные файлы

Из имён файлов убраны специальные символы (`_`, `-`). В таблице указан
текущий путь каждого переименованного файла (проверено по репозиторию):

| Старое имя | Текущий путь |
|------------|--------------|
| `error_handler.sh` | `core/errorhandler.sh` |
| `system_audit.sh` | `lib/audit/systemaudit.sh` |
| `data_processor.sh` | `lib/data/dataprocessor.sh` |
| `frameworks_integration.sh` | `lib/frameworks/frameworksintegration.sh` |
| `vk_api.sh` | `lib/integration/vkapi.sh` |
| `vk_music.sh` | `lib/integration/vkmusic.sh` |
| `ssh_network.sh` | `lib/network/sshnetwork.sh` |
| `ps1_status.sh` | `lib/status/ps1status.sh` |
| `distro_logic.sh` | `lib/system/distrologic.sh` |
| `platform_check.sh` | `lib/system/platformcheck.sh` |
| `ps1_config.sh` | `lib/ui/ps1config.sh` |
| `test_framework.sh` | `tests/testframework.sh` |
| `run_all_tests.sh` | `tests/runalltests.sh` |
| `validate_syntax.sh` | `tests/validatesyntax.sh` |

Модули, удалённые после переименования (в репозитории отсутствуют):
`displaysettings.sh`, `interactiveui.sh`, `desktopintegration.sh`,
`telegramintegration.sh`, `bashitintegration.sh`, `datapresentation.sh`.

## См. также

- [README](../../README.md)
- [Best practices](./best-practices.md) — соглашения об именовании
  (`log::`, `bs::`, `BS_*`)
