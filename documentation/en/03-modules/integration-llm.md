[↑ Table of Contents](../README.md)

# Module `llm`

`lib/integration/llm.sh` — a unified client for LLM providers (OpenAI and Ollama). Returns the response text on stdout so it can be easily parsed by a Go backend, CI pipeline, or web interface. For a structured JSON result use `llm::result` or wrap the call with `result::wrap`.

Source: [lib/integration/llm.sh](../../../lib/integration/llm.sh)

## Loading

```bash
#!/usr/bin/env bs

load "lib/integration/llm"
```

## API

### `llm::providers`

Return a space-separated list of supported providers.

```bash
llm::providers
# openai ollama
```

### `llm::is_available <provider>`

Check whether a provider is configured.

- `openai` — requires `OPENAI_API_KEY` (or `LLM_OPENAI_API_KEY`).
- `ollama` — tries to reach `OLLAMA_HOST` (default `http://localhost:11434`).

```bash
if llm::is_available openai; then
  echo "OpenAI ready"
fi
```

### `llm::chat <provider> <model> <message>`

Send a message and return the response text.

```bash
export OPENAI_API_KEY="sk-..."
llm::chat openai gpt-3.5-turbo "Hello, world!"

export OLLAMA_HOST="http://localhost:11434"
llm::chat ollama llama3 "Explain bash arrays"
```

### `llm::chat_file <provider> <model> <file>`

Send the contents of a file as a chat message.

```bash
llm::chat_file openai gpt-3.5-turbo /path/to/code.sh
```

### `llm::result <provider> <model> <message>`

Return the standard BS JSON result contract (`success`, `exit_code`, `data`, ...). Requires `lib/integration/result`.

```bash
llm::result openai gpt-3.5-turbo "Hello"
```

## Environment variables

| Variable | Purpose | Default |
|---|---|---|
| `OPENAI_API_KEY` | OpenAI API key | — |
| `LLM_OPENAI_API_KEY` | Alternative OpenAI key variable | — |
| `LLM_OPENAI_URL` | OpenAI API base URL | `https://api.openai.com/v1/chat/completions` |
| `LLM_OPENAI_MODEL` | Default model | `gpt-3.5-turbo` |
| `OLLAMA_HOST` | Ollama host | `http://localhost:11434` |
| `LLM_OLLAMA_MODEL` | Default Ollama model | `llama3` |
| `LLM_TIMEOUT` | HTTP request timeout | `60` |

## Example

```bash
bs run examples/llm_example.sh
```

Source: [examples/llm_example.sh](../../../examples/llm_example.sh).

## Dependencies

- `core/const`, `core/logger`, `core/utils`, `lib/integration/http` — BS core modules.
- `curl` or `wget` — for HTTP requests (via `http.sh`).
- `jq` — optional, for more robust JSON response parsing.
