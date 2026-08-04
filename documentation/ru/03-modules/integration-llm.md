[↑ Оглавление](../README.md)

# Модуль `llm`

`lib/integration/llm.sh` — единый клиент для LLM-провайдеров (OpenAI и Ollama). Возвращает текст ответа в stdout, что позволяет легко парсить результат из Go-backend, CI или веб-интерфейса. Для структурированного JSON-ответа используйте `llm::result` или оберните вызов в `result::wrap`.

Исходник: [lib/integration/llm.sh](../../../lib/integration/llm.sh)

## Загрузка

```bash
#!/usr/bin/env bs

load "lib/integration/llm"
```

## API

### `llm::providers`

Вернуть список поддерживаемых провайдеров через пробел.

```bash
llm::providers
# openai ollama
```

### `llm::is_available <provider>`

Проверить, настроен ли провайдер.

- `openai` — требует `OPENAI_API_KEY` (или `LLM_OPENAI_API_KEY`).
- `ollama` — пытается достучаться до `OLLAMA_HOST` (по умолчанию `http://localhost:11434`).

```bash
if llm::is_available openai; then
  echo "OpenAI ready"
fi
```

### `llm::chat <provider> <model> <message>`

Отправить сообщение и вернуть текст ответа.

```bash
export OPENAI_API_KEY="sk-..."
llm::chat openai gpt-3.5-turbo "Hello, world!"

export OLLAMA_HOST="http://localhost:11434"
llm::chat ollama llama3 "Explain bash arrays"
```

### `llm::chat_file <provider> <model> <file>`

Отправить содержимое файла как сообщение.

```bash
llm::chat_file openai gpt-3.5-turbo /path/to/code.sh
```

### `llm::result <provider> <model> <message>`

Вернуть стандартный JSON-контракт результата BS (`success`, `exit_code`, `data`, ...). Требует `lib/integration/result`.

```bash
llm::result openai gpt-3.5-turbo "Hello"
```

## Env-переменные

| Переменная | Назначение | Значение по умолчанию |
|---|---|---|
| `OPENAI_API_KEY` | API-ключ OpenAI | — |
| `LLM_OPENAI_API_KEY` | Альтернативное имя ключа OpenAI | — |
| `LLM_OPENAI_URL` | Базовый URL OpenAI API | `https://api.openai.com/v1/chat/completions` |
| `LLM_OPENAI_MODEL` | Модель по умолчанию | `gpt-3.5-turbo` |
| `OLLAMA_HOST` | Хост Ollama | `http://localhost:11434` |
| `LLM_OLLAMA_MODEL` | Модель Ollama по умолчанию | `llama3` |
| `LLM_TIMEOUT` | Таймаут HTTP-запроса | `60` |

## Пример

```bash
bs run examples/llm_example.sh
```

Исходник: [examples/llm_example.sh](../../../examples/llm_example.sh).

## Зависимости

- `core/const`, `core/logger`, `core/utils`, `lib/integration/http` — базовые модули BS.
- `curl` или `wget` — для HTTP-запросов (через `http.sh`).
- `jq` — опционально, для более надёжного парсинга JSON-ответа.
