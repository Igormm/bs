[↑ Table of Contents](../README.md)

# Module `http`

`lib/integration/http.sh` — a simple HTTP client for BS supporting both `curl` and `wget`, dry-run, timeouts, and retries. Returns the response body on stdout and an integration error code.

Source: [lib/integration/http.sh](../../../lib/integration/http.sh)

## Loading

```bash
#!/usr/bin/env bs

load "lib/integration/http"
```

## API

### `http::request <method> <url> [options...]`

Perform an HTTP request. Supported options:

- `--header "Name: Value"` — add a header
- `--data "body"` — request body for POST/PUT
- `--timeout <seconds>` — request timeout
- `--silent` — suppress diagnostics

```bash
http::request GET "https://api.example.com/status"
http::request POST "https://api.example.com/users" \
  --data '{"name":"alice"}' \
  --header "Content-Type: application/json"
```

### `http::get <url> [options...]`

GET request.

```bash
http::get "https://api.github.com"
```

### `http::post <url> <data> [options...]`

POST request.

```bash
http::post "https://api.example.com/users" '{"name":"alice"}'
```

### `http::download <url> <file> [options...]`

Download a file.

```bash
http::download "https://example.com/file.iso" "/tmp/file.iso" --timeout 60
```

### `http::retry <attempts> <delay> <command> [args...]`

Retry a command with a fixed delay.

```bash
http::retry 3 1 http::get "https://api.example.com/status"
```

## Environment variables

| Variable | Purpose |
|---|---|
| `FRAMEWORK_DRY_RUN=true` | Do not execute HTTP requests, only log |

## Example

```bash
bs run examples/http_example.sh
```

Source: [examples/http_example.sh](../../../examples/http_example.sh).

## Dependencies

- `core/const`, `core/logger`, `core/utils`, `core/deps` — BS core modules.
- `curl` or `wget` — one HTTP client.
