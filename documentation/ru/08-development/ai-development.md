# Разработка с помощью ИИ / AI-assisted development

BS — это Bash-фреймворк с чёткими соглашениями. LLM и агенты могут эффективно писать модули, если им предоставить правильный контекст и промпты.

## Быстрый старт для ИИ-разработчика

1. Прочитай `AGENTS.md` в корне репозитория.
2. Прочитай `documentation/ru/code-style-guide.md`.
3. Для задач в `lib/` используй промпт `ai/lib-prompt.md`.
4. Для задач в `core/` используй промпт `ai/core-prompt.md`.
5. Для идей по MCP, провайдерам и CI читай `ai/mcp-integration.md`.
5. После изменений запусти:
   ```bash
   bash tests/validatesyntax.sh
   bash tests/validateshellcheck.sh
   bash tests/runalltests.sh
   ```

## Как сократить контекст

Если репозиторий слишком большой для контекстного окна модели, передай только:

- `AGENTS.md`
- `documentation/ru/code-style-guide.md`
- целевой модуль и его тесты
- связанные модули (через `# @depends`)

## Промпты

### Для разработки lib/

```text
Ты — эксперт по Bash и фреймворку BS. Реализуй функцию в lib/<group>/<module>.sh.

Требования:
- Используй shebang #!/usr/bin/env bs и # shellcheck shell=bash
- Защита от повторной загрузки через bs::guard
- Зависимости через bs::source_relative
- Публичные функции в namespace group::module::function
- Без внешних зависимостей, только Bash 4+ и стандартные Unix-утилиты
- Добавь unit-тест в tests/unit/test<module>unit.sh
- Проверь через validatesyntax.sh, validateshellcheck.sh, runalltests.sh

Опиши, что должна делать функция: ...
```

### Для разработки core/

```text
Ты — эксперт по ядру фреймворка BS. Реализуй изменение в core/<module>.sh.

Требования:
- Не подключай core/prereq.sh — bs::guard и bs::source_relative доступны априори
- Используй shebang #!/usr/bin/env bash
- Минимизируй зависимости от других core-модулей
- Соблюдай backward compatibility публичного API
- Добавь/обнови unit-тест и документацию core-api.md
- Проверь через validatesyntax.sh, validateshellcheck.sh, runalltests.sh

Опиши задачу: ...
```

## Интеграция с MCP и API-провайдерами

### MCP (Model Context Protocol)

Рекомендуемые инструменты для экспозиции фреймворка:

- `bs doctor` — проверка целостности
- `bs list` — список модулей
- `bs run <script> [args...]` — запуск скриптов
- `bash tests/validatesyntax.sh` — проверка синтаксиса
- `bash tests/validateshellcheck.sh` — проверка ShellCheck
- `bash tests/runalltests.sh` — прогон тестов

### API-провайдеры

Любой LLM с function calling может вызывать валидаторы для проверки сгенерированного кода. Последовательность:

1. Модель генерирует код по запросу.
2. Агент вызывает `validatesyntax.sh`.
3. Агент вызывает `validateshellcheck.sh`.
4. Агент вызывает `runalltests.sh`.
5. Если есть ошибки — модель получает вывод и исправляет код.

### Подсказки по контексту

- Для небольших задач достаточно `AGENTS.md` + целевой файл.
- Для новых модулей добавь `code-style-guide.md` и примеры из `examples/`.
- Для интеграционных модулей добавь `lib/integration/result.sh` как эталон.

## Чего избегать

- Не предлагай внешние зависимости (Python, Node, jq) без согласования.
- Не изменяй git-историю (`git rebase`, `git reset`, force-push) без явного разрешения.
- Не добавляй `set -euo pipefail` в библиотечные модули.
