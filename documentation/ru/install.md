# Установка

BS устанавливается модульным установщиком в корне репозитория: точка входа — [install.sh](../../install.sh), логика находится в [install/](../../install).

## Структура установщика

- [install.sh](../../install.sh) — точка входа. Проверяет структуру репозитория (`core/`, `bootstrap/`, `install/`), подключает `core/utils.sh`, включает строгий режим через `utils::strict`, проверяет версию оболочки через `utils::ensure_shell_version`, затем запускает `install/main.sh`.
- [install/main.sh](../../install/main.sh) — разбор аргументов, выбор режима и путей, вызов действий установки/удаления.
- [install/checks.sh](../../install/checks.sh) — проверки окружения: `is_already_installed`, `check_shell_environment`.
- [install/actions.sh](../../install/actions.sh) — `do_install` и `do_uninstall`.
- [install/path_manager.sh](../../install/path_manager.sh) — помощники PATH: `print_path_hint`, `auto_update_path`, `update_path_bashrc`.

## Режимы

| Режим | Флаг | Префикс | Нужен root |
| --- | --- | --- | --- |
| system | (по умолчанию) | `/usr/local` | да (`sudo`) |
| local | `--local` | `~/.local` | нет |

Значения по умолчанию переопределяются переменными окружения: `PREFIX`, `BIN_DIR` (по умолчанию `$PREFIX/bin`), `LIB_DIR` (по умолчанию `$PREFIX/lib`).

## Что куда устанавливается

- `TARGET_LIB=$LIB_DIR/bs` — файлы фреймворка: `bootstrap/`, `core/`, `lib/` и лаунчер `bs`, скопированные из репозитория.
- `TARGET_BIN=$BIN_DIR/bs` — небольшой wrapper-скрипт:

```bash
#!/usr/bin/env bash
export BS_ROOT="${TARGET_LIB}"
exec "${BS_ROOT}/bs" "$@"
```

Wrapper экспортирует `BS_ROOT` и делегирует вызов настоящей точке входа `bs`, поэтому shebang `#!/usr/bin/env bs` работает в пользовательских скриптах, как только `BIN_DIR` добавлен в `PATH`.

## Использование

Системная установка (действие по умолчанию — `install`):

```bash
sudo ./install.sh
sudo ./install.sh install
```

Локальная установка, без sudo:

```bash
./install.sh --local
./install.sh --local install
```

Собственный префикс:

```bash
PREFIX=/opt/bs sudo ./install.sh
```

## Удаление

```bash
sudo ./install.sh uninstall        # system
./install.sh --local uninstall     # local
```

`uninstall` (псевдоним: `remove`) удаляет `TARGET_BIN` и `TARGET_LIB`. В локальном режиме дополнительно удаляются `BIN_DIR`/`LIB_DIR`, но только если они пустые (`rmdir`), поэтому другие файлы в `~/.local` не затрагиваются.

## Управление PATH (локальный режим)

После локальной установки `auto_update_path` запускается автоматически. Оба флага PATH работают только вместе с `--local`:

```bash
./install.sh --local --path         # вывести сниппет для ручной настройки
./install.sh --local --update-path  # добавить строку в ~/.bashrc и/или ~/.zshrc
```

`--update-path` дописывает следующую строку (идемпотентно — существующие идентичные строки находятся через `grep -Fqx` и не дублируются):

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Правила: `~/.bashrc` обновляется, если он существует или если нет `~/.zshrc`; `~/.zshrc` обновляется, только если уже существует. После этого перезагрузите оболочку (`source ~/.bashrc`) или откройте новую сессию.

## Примечания

- **Исходный каталог можно удалить.**  
  Установщик копирует файлы фреймворка в `TARGET_LIB` и создаёт обёртку в
  `TARGET_BIN`. После успешной установки BS работает из целевого каталога,
  а не из репозитория, из которого запускался `install.sh`. Целевой
  каталог зависит от режима:
  - `system` (по умолчанию): `/usr/local/lib/bs`;
  - `local` (`--local`): `~/.local/lib/bs`;
  - произвольный: значения `PREFIX`, `BIN_DIR`, `LIB_DIR`.
- Требуется bash 4.0+; на более старых оболочках установщик завершается через `utils::ensure_shell_version`.
- Если BS уже установлена в целевой каталог (`is_already_installed`), установщик останавливается и предлагает сначала удалить старую версию или переопределить `PREFIX`/`BIN_DIR`/`LIB_DIR`.
- Установщик работает в строгом режиме (`utils::strict`: `set -euo pipefail`) и проверяет каждый подключаемый файл через `utils::ensure_source`.
