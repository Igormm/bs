[↑ Оглавление](../README.md)

# Модуль `io::tree`

Создать дерево файлов проекта из спецификации **yaml / yml / txt / ini / csv**.
Одна каноническая модель: каталоги и файлы с опциональным содержимым. Пути
только относительные; `..` и абсолютные пути отклоняются.

Исходник: [lib/io/tree.sh](../../../lib/io/tree.sh)

## Подключение

```bash
#!/usr/bin/env bs

load "lib/io/tree"
```

## Одна строка

```bash
io::tree::create spec.yaml ./my-app
io::tree::create --force --format txt paths.txt /tmp/app
io::tree::create --dry-run tree.ini ./preview
```

Флаги: `--force` (перезаписать файлы), `--dry-run` (только план),
`--format yaml|yml|txt|ini|csv` (перекрыть расширение / эвристику).

## Форматы

### YAML / YML (ограниченное дерево отображений)

Чистый bash. `yq` не нужен. Вложенные map — каталоги, скаляры — файлы,
`|` — блочный скаляр. Ключ с `/` на конце — пустой каталог.

```yaml
src:
  hello.sh: "#!/usr/bin/env bs"
  lib/:
README.md: |
  # title
  body
```

Не поддерживаются: якоря, теги, merge keys, flow-последовательности как дерево.

### TXT

Список путей (один путь на строку, хвост `/` = каталог) или дерево отступами
(2 пробела / рамка `tree(1)`). Комментарии `#`.

```
src/
  lib/
    util.sh
README.md
```

### INI

Секция = каталог. `ключ = содержимое` = файл. Пустая секция всё равно
создаёт каталог. `[.]` или `[root]` — корень назначения.

```ini
[src]
hello.sh = #!/usr/bin/env bs

[docs]
```

### CSV

Колонки: `path`, `kind` (`file`/`dir`/`f`/`d`), опционально `content`.
Строка заголовка необязательна. Поля в кавычках через
[lib/rfc/csv.sh](../../../lib/rfc/csv.sh).

```csv
path,kind,content
src,dir,
src/app.sh,file,"hello"
```

## API

| Функция | Роль |
| --- | --- |
| `io::tree::detect path` | stdout: `yaml`/`yml`/`txt`/`ini`/`csv` |
| `io::tree::parse path [format]` | заполнить массивы `IO_TREE_*` |
| `io::tree::parse_text text format` | то же из строки |
| `io::tree::dump` | stdout `kind<TAB>path` |
| `io::tree::plan dest` | stdout `MKDIR`/`WRITE`/`SKIP`/`KEEP` |
| `io::tree::apply dest [force]` | создать на диске |
| `io::tree::create [flags] spec dest` | parse + apply |
| `io::tree::reset` | очистить массивы |

Существующие файлы не трогаются без `force=1` / `--force`.
`FRAMEWORK_DRY_RUN=true` или `IO_TREE_DRY_RUN=1` отключает запись.
Каталоги через `io::files::ensure_dir`.

## Безопасность

- Только относительные пути.
- Компоненты `.` и `..` — ошибка (`E_INVALID`).
- Конфликт файл/каталог — `LIB_ERROR_CONFLICT`.

Пример: [examples/tree_example.sh](../../../examples/tree_example.sh).
