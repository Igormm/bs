[↑ Оглавление](../README.md)

# Модуль `http`

`lib/integration/http.sh` — простой HTTP-клиент для BS с поддержкой `curl` и `wget`, dry-run, таймаутов и повторных попыток. Возвращает тело ответа в stdout и код ошибки из диапазона интеграций.

Исходник: [lib/integration/http.sh](../../../lib/integration/http.sh)

## Загрузка

```bash
#!/usr/bin/env bs

load "lib/integration/http"
```

## API

### `http::request <method> <url> [options...]`

Выполнить HTTP-запрос. Поддерживаются опции:

- `--header "Name: Value"` — добавить заголовок
- `--data "body"` — тело POST/PUT-запроса
- `--timeout <seconds>` — таймаут
- `--silent` — подавить диагностику

```bash
http::request GET "https://api.example.com/status"
http::request POST "https://api.example.com/users" \
  --data '{"name":"alice"}' \
  --header "Content-Type: application/json"
```

### `http::get <url> [options...]`

GET-запрос.

```bash
http::get "https://api.github.com"
```

### `http::post <url> <data> [options...]`

POST-запрос.

```bash
http::post "https://api.example.com/users" '{"name":"alice"}'
```

### `http::download <url> <file> [options...]`

Скачать файл.

```bash
http::download "https://example.com/file.iso" "/tmp/file.iso" --timeout 60
```

### `http::retry <attempts> <delay> <command> [args...]`

Повторить команду с фиксированной задержкой.

```bash
http::retry 3 1 http::get "https://api.example.com/status"
```

## Env-переменные

| Переменная | Назначение |
|---|---|
| `FRAMEWORK_DRY_RUN=true` | Не выполнять HTTP-запросы, только логировать |

## Пример

```bash
bs run examples/http_example.sh
```

Исходник: [examples/http_example.sh](../../../examples/http_example.sh).

## Зависимости

- `core/const`, `core/logger`, `core/utils`, `core/deps` — базовые модули BS.
- `curl` или `wget` — один из HTTP-клиентов.
