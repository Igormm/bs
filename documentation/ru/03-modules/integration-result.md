[↑ Оглавление](../README.md)

# Модуль `result`

`lib/integration/result.sh` — JSON-контракт результата операций для интеграций
BS с внешними системами (Go-backend, HTTP API, CI).

В bash функции обычно возвращают только exit code, а полезные данные и ошибки
идут в stdout/stderr. Этот модуль оборачивает команды и функции BS в
структурированный JSON-объект, который легко парсить извне.

Исходник: [lib/integration/result.sh](../../../lib/integration/result.sh)

## JSON-контракт

```json
{
  "success": true,
  "exit_code": 0,
  "operation": "copy_file",
  "args": ["src.txt", "dst.txt"],
  "data": null,
  "stdout": "",
  "stderr": "",
  "message": "Function completed",
  "timestamp": "2026-08-04T12:00:00+03:00",
  "duration_ms": 42
}
```

## Загрузка

```bash
#!/usr/bin/env bs

load "lib/integration/result"
```

## API

### `result::ok [data] [message]`

Вернуть успешный результат.

```bash
result::ok "user123" "User created"
```

### `result::error <code> [message] [data]`

Вернуть результат с ошибкой.

```bash
result::error "${LIB_ERROR_FILE_NOT_FOUND}" "Source not found"
```

### `result::run -- <command> [args...]`

Запустить внешнюю команду и вернуть её результат в виде JSON.

```bash
result::run -- ls -la /tmp
result::run -- wget https://example.com/file.iso
```

### `result::wrap <function> [args...]`

Вызвать функцию BS и вернуть её результат в виде JSON.

```bash
load "lib/io/files"
result::wrap io::files::copy_file "src.txt" "dst.txt"
```

### `result::get <json> <key> <var>`

Извлечь значение из JSON-результата по ключу в переменную (требуется `jq`).

```bash
json="$(result::run -- echo hello)"
local exit_code
result::get "${json}" "exit_code" exit_code
echo "Exit code: ${exit_code}"
```

### `result::is_success <json>`

Вернуть `0`, если `success == true`.

```bash
if result::is_success "${json}"; then
  echo "OK"
fi
```

### `result::write <file> <json>`

Записать JSON-результат в файл.

```bash
json="$(result::ok)"
result::write "/tmp/result.json" "${json}"
```

## Env-переменные

| Переменная | Назначение |
|---|---|
| `BS_RESULT_FILE=/path/to/file.json` | Писать результат в файл вместо stdout. |
| `BS_RESULT_SILENT=true` | Подавить логи BS, оставить только JSON (в разработке). |

## Интеграция с Go

Go-backend может вызывать BS тремя способами:

### 1. Запуск скрипта

```bash
./bs run examples/result_example.sh
```

### 2. Inline-вызов функции

```bash
bash -c "source bootstrap/init.sh; load lib/io/files; load lib/integration/result; result::wrap io::files::copy_file src.txt dst.txt"
```

### 3. Запись результата в файл

```bash
bash -c "source bootstrap/init.sh; load lib/integration/result; BS_RESULT_FILE=/tmp/out.json result::run -- uname -a"
cat /tmp/out.json
```

## Пример

```bash
bs run examples/result_example.sh
```

Исходник: [examples/result_example.sh](../../../examples/result_example.sh).

## Зависимости

- `core/const`, `core/logger`, `core/utils`, `lib/io/streams` — базовые модули BS.
- `jq` — опционально, для форматирования/валидации JSON и `result::get`.
- Без `jq` модуль генерирует minified JSON с базовым экранированием строк.
