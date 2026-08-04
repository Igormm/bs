[↑ Оглавление](../README.md)

# Модуль `io::files`

File System Helper (FSH) — высокоуровневые файловые операции с единым
`dry-run`, логированием и обработкой ошибок.

Исходник: [lib/io/files.sh](../../../lib/io/files.sh)

## Загрузка

```bash
#!/usr/bin/env bs

load "lib/io/files"
```

Или вручную:

```bash
source bootstrap/init.sh
load "lib/io/files"
```

## Проверки

```bash
io::files::exists  "/etc/passwd"
io::files::is_file "/etc/passwd"
io::files::is_dir  "/etc"
```

## Создание каталогов

```bash
io::files::ensure_dir "/tmp/myapp"      # mkdir -p
io::files::ensure_dir "/tmp/myapp" "755" # + chmod 755
```

## Копирование

```bash
# Один файл
io::files::copy_file "src.txt" "dst.txt"

# Рекурсивно каталог
io::files::copy_dir "project" "project_backup"

# Синхронизация: при delete=true назначение становится зеркалом источника.
# Если rsync доступен — используется он, иначе cp + ручная очистка лишнего.
io::files::sync_dir "project" "project_backup" false  # только добавить новое
io::files::sync_dir "project" "project_backup" true   # зеркало

# Копирование по маскам (include/exclude — списки шаблонов через пробел)
io::files::copy_matching "project" "release" "*.sh *.md" "*.tmp *.log"

# Атомарное копирование с резервной копией
# Файл сначала пишется во временный файл рядом с dst, затем atomically
# переименовывается. Существующий dst сохраняется как dst<suffix>.
io::files::copy_file "src.txt" "dst.txt" true ".bak"
io::files::copy_dir "project" "project_backup" true ".bak"
```

## Перемещение и удаление

```bash
io::files::move "old.txt" "new.txt"   # mv --
io::files::cut  "old.txt" "new.txt"   # семантика «вырезать» = move

# Move с fallback на copy+remove при cross-device ситуации (по умолчанию включён)
io::files::move "old.txt" "new.txt" true ".bak"

io::files::remove "file.txt"
io::files::remove "dir" true          # рекурсивно
```

## Атомарность, backup и env-переменные

Модуль поддерживает безопасное изменение целевых объектов:

- **Атомарное копирование** — `copy_file`/`copy_dir` с `atomic=true` пишут
  во временный объект рядом с назначением и только потом делают `mv`.
  Внешний наблюдатель всегда видит либо старую версию, либо полную новую.
- **Backup** — если задан `backup_suffix` (или `BS_FILES_BACKUP_SUFFIX`),
  существующее назначение переименовывается в `dst<suffix>` до операции.
- **Move fallback** — если `mv` не сработал (например, разные ФС),
  `move` с `atomic_fallback=true` выполняет `cp -a` + `rm -rf`.

Глобальные env-дефолты:

| Переменная | Назначение |
|---|---|
| `BS_FILES_ATOMIC=true\|false` | Дефолт для атомарного копирования |
| `BS_FILES_ATOMIC_FALLBACK=true\|false` | Дефолт для fallback в `move` |
| `BS_FILES_BACKUP_SUFFIX=.suffix` | Дефолтный суффикс backup'а |

Пример с env:

```bash
export BS_FILES_ATOMIC=true
export BS_FILES_BACKUP_SUFFIX=.bak
io::files::copy_file "src.txt" "dst.txt"   # atomic=true, backup=.bak
```

## Режим сухого прогона

Если установлена переменная `FRAMEWORK_DRY_RUN=true`, все операции только
логируются через `log::warn` с префиксом `[DRY-RUN]`, файловая система не
изменяется, а функции возвращают `0`.

```bash
export FRAMEWORK_DRY_RUN=true
io::files::copy_dir "project" "project_backup"  # только покажет команду
```

## Коды ошибок

Используются константы из `core/const`:

- `E_INVALID` — не передан обязательный аргумент или `src == dst`.
- `LIB_ERROR_FILE_NOT_FOUND` — источник не существует.
- `LIB_ERROR_FILE_OPERATION` — сбой `cp`/`mv`/`rm`/`find` или источник не
  файл/каталог.
- `LIB_ERROR_CONFLICT` — цель уже существует и перезапись не разрешена
  (зарезервировано для будущих опций).

## Зависимости

- `core/const`, `core/logger`, `core/utils` — базовые идиомы и коды ошибок.
- `lib/system/permissions` — установка прав для `ensure_dir`.
- Опционально `rsync` для `sync_dir` (без него работает fallback на `cp`).

## Примеры

```bash
bs run examples/filesops_example.sh
bs run examples/filesops_atomic_example.sh
```

Исходники:
- [examples/filesops_example.sh](../../../examples/filesops_example.sh) — базовые операции.
- [examples/filesops_atomic_example.sh](../../../examples/filesops_atomic_example.sh) — атомарное копирование, backup, move fallback, env-дефолты и dry-run.
