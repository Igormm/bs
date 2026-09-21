# BS как AI toolchain / toolbox

> Что уже есть в BS для работы с ИИ-агентами, и что достроить, чтобы проект
> стал полноценным toolchain: инструментарием, который агент использует сам,
> без человека-оператора.
>
> BS as an AI toolchain: what already exists, and what to add so the repo
> becomes a self-service toolbox for AI agents.

## 1. Уже готово (as-is)

| Слой | Инструмент | Роль для AI |
|---|---|---|
| Интерпретация | `bs`, `bs run`, `#!/usr/bin/env bs` | детерминированный запуск любого артефакта, сгенерированного моделью |
| Рефлексия | `bs list`, `bs doctor`, `bs lang-doc` | агент обнаруживает модули и их контракты без чтения всего репозитория |
| Языковой сервер | `bs lsp` (JSON-RPC, stdin/stdout) | hover/доки/диагностика для Bash — интеграция с любыми LSP-клиентами |
| Интроспекция REPL | `bs repl` (`:list`, `:doc`, `:info`) | интерактивное исследование API моделью |
| Формализация | `# @depends`, `# @description/@param/@return` docblock'и | машиночитаемые контракты; loader валидирует граф зависимостей |
| Верификация | `validatesyntax.sh`, `validateshellcheck.sh`, `runalltests.sh` | self-check-цикл: агент генерирует → валидирует → исправляет |
| Feedback loop | `tests/testframework.sh` asserts | быстрый (секунды) замыкающий контур для итераций |
| Контекст | `AGENTS.md`, `.agents/prompts/*-prompt.md`, `.agents/skills/*` | роль, правила, готовые workflow-процедуры |
| Интеграции | `lib/integration/llm.sh`, `chat.sh`, `result.sh` | BS сам выступает потребителем LLM (OpenAI/Ollama) |
| Дистрибуция | `bs build` (standalone), `bs update` | агенту не нужен окружение — артефакт самодостаточен |

Ключевое свойство: **у каждого действия агента есть верификатор**. Это
отличает toolchain от «набора скриптов».

## 2. Чего не хватает (gap analysis)

1. **MCP-сервер**. Идеи зафиксированы в `.agents/guides/mcp-integration.md`, но кода нет.
   Минимальный набор инструментов: `bs_list`, `bs_doctor`, `bs_lang_doc`,
   `bs_run`, `validate(all)`, `test(run)`, `read_module`.
   Реализация — тонкая обёртка (node/python или даже `bs` + JSON-RPC по
   строкам), сами инструменты уже есть как CLI.
2. **Машиночитаемый индекс API**. `bs lang-doc` уже отдаёт JSON — не хватает
   стабильной схемы версии + `--filter`, чтобы агент грузил контекст
   точечно, а не весь репозиторий.
3. **Оценка риска диффа**. Валидаторы проверяют корректность, но не «не
   сломано ли поведение»: нужен скорый режим `bs doctor --changed` (git diff →
   затронутые модули → только их тесты).
4. **Прогон в песочнице**. Агенту нужен изолированный запуск: контейнер
   (матрица CI ubuntu/debian/almalinux уже описана) или `bwrap`;
   `lib/system/safety.sh` задаёт точечные guard'ы, но нет generic
   run-in-sandbox-профиля.
5. **Контракты генерации**. `lib/integration/result.sh` задаёт JSON-контракт
   результата — стоит расширить его до формата ответов агента
   (schema + exit-коды + structured log), чтобы оркестраторы (CI, агенты
   второго уровня) парсили результат без эвристик.
6. **Каталог скилов как tool-manifest**. `.agents/skills/*/SKILL.md` читаются
   агентами; не хватает генерации свода (`bs skills ls --json`) для автодополнения.

## 3. Дорожная карта (предложение)

- **Этап A — toolchain ядро (дёшево):**
  `bs doctor --changed`, `bs lang-doc --filter`, запуск скилов (`bs skill run
  <name>`), стабильная JSON-схема вывода `bs list/doctor` (сейчас text).
- **Этап B — интерфейс агентов:** MCP-сервер поверх существующих CLI
  (`lib/integration/*` подход), profile контекста (`--context lib/system/sensor`
  отдаёт модуль+тесты+секцию style-guide — см. AGENTS.md «Context compression»).
- **Этап C — автономный цикл:** CI-workflow, где правку, предложенную
  агентом, проверяет `bs validate`-джоб, а `bs build` собирает артефакт;
  `result.sh`-контракт как протокол обмена агент↔конвейер.
- **Этап D — обратной связь:**Structured logs (`logger` text/json уже есть) +
  прогон тестов с coverage-подобной отметкой «какие функции модуля не
  покрыты», чтобы агент сам дописывал тесты.

## 4. Риски

- Bash-специфика: агенты воспроизводят классические ловушки (`set -e` +
  возвращаемый статус `(( ))`, `exec` на закрытом FD, `read -t` на tty).
  Скилы `bs-review-module`/`bs-new-lib-module` — основная прививка; их надо
  держать в синхроне с реальными багами (см. git log фиксов).
- Разрастание «AI-слоя» без верификаторов противоречит идее toolchain:
  каждый новый инструмент обязан иметь тест в `tests/unit/`.
