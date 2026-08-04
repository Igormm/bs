[↑ Table of Contents](../README.md)

# Module `result`

`lib/integration/result.sh` — a JSON result contract for BS integrations
with external systems (Go backend, HTTP API, CI).

In bash, functions usually return only an exit code, while useful data and
errors go to stdout/stderr. This module wraps BS commands and functions in a
structured JSON object that is easy to parse from the outside.

Source: [lib/integration/result.sh](../../../lib/integration/result.sh)

## JSON contract

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

## Loading

```bash
#!/usr/bin/env bs

load "lib/integration/result"
```

## API

### `result::ok [data] [message]`

Return a successful result.

```bash
result::ok "user123" "User created"
```

### `result::error <code> [message] [data]`

Return an error result.

```bash
result::error "${LIB_ERROR_FILE_NOT_FOUND}" "Source not found"
```

### `result::run -- <command> [args...]`

Run an external command and return its result as JSON.

```bash
result::run -- ls -la /tmp
result::run -- wget https://example.com/file.iso
```

### `result::wrap <function> [args...]`

Call a BS function and return its result as JSON.

```bash
load "lib/io/files"
result::wrap io::files::copy_file "src.txt" "dst.txt"
```

### `result::get <json> <key> <var>`

Extract a value from a result JSON by key into a variable (requires `jq`).

```bash
json="$(result::run -- echo hello)"
local exit_code
result::get "${json}" "exit_code" exit_code
echo "Exit code: ${exit_code}"
```

### `result::is_success <json>`

Return `0` if `success == true`.

```bash
if result::is_success "${json}"; then
  echo "OK"
fi
```

### `result::write <file> <json>`

Write a JSON result to a file.

```bash
json="$(result::ok)"
result::write "/tmp/result.json" "${json}"
```

## Environment variables

| Variable | Purpose |
|---|---|
| `BS_RESULT_FILE=/path/to/file.json` | Write the result to a file instead of stdout. |
| `BS_RESULT_SILENT=true` | Suppress BS logs, leave only JSON (in development). |

## Integration with Go

A Go backend can invoke BS in three ways:

### 1. Run a script

```bash
./bs run examples/result_example.sh
```

### 2. Inline function call

```bash
bash -c "source bootstrap/init.sh; load lib/io/files; load lib/integration/result; result::wrap io::files::copy_file src.txt dst.txt"
```

### 3. Write result to a file

```bash
bash -c "source bootstrap/init.sh; load lib/integration/result; BS_RESULT_FILE=/tmp/out.json result::run -- uname -a"
cat /tmp/out.json
```

## Example

```bash
bs run examples/result_example.sh
```

Source: [examples/result_example.sh](../../../examples/result_example.sh).

## Dependencies

- `core/const`, `core/logger`, `core/utils`, `lib/io/streams` — BS core modules.
- `jq` — optional, for JSON formatting/validation and `result::get`.
- Without `jq` the module still produces minified JSON with basic string escaping.
