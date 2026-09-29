# BS Framework — полный прогон скиллов

Дата / Date: 2026-09-29
Версия / Version: 0.6.0
Способ запуска: последовательный прогон исполняемых скиллов
(валидаторы, сканеры, линтеры) + статус процессных скиллов.

---

## 1. bs-validate — цикл валидации

- `validatesyntax.sh` — PASS (все файлы, синтаксис корректен)
- `validateshellcheck.sh` — PASS (181 файл, 0 ошибок)
- `runalltests.sh` — PASS (54 теста, 52 passed, 0 failed, 2 skipped)

Замечание: никаких.

---

## 2. bs-check-docs-code — сниппеты кода в документации

401 сниппет проверено, **13 находок** — те же известные намеренные:

| Файл | Класс | Вердикт |
| --- | --- | --- |
| 03-modules/args.md (ru/en) | выдержка не совпадает дословно (пропущен `local`) | намеренная упрощённая выдержка; кандидат на правку |
| 07-testing/README.md `some::failing_command` | иллюстративный фейк-команд | намеренный |
| 08-development/README.md `lib/system/foo` | обучающий плейсхолдер | намеренный |
| 09-migration-bosa-to-bs.md `logger::info/debug` | старый BOSA API в миграции | намеренный |
| examples/README.md `bosa::init`, `telegramintegration` | устаревший BOSA-контент | известный хвост; кандидат на чистку |

---

## 3. bs-check-artifacts — следы генерации и утечки

- CRLF: 0
- zero-width/BOM/скрытые символы: 0
- плейсхолдеры: 11 — все легитимные (dry-run стуб в llm.sh, stubs в
  юнит/интеграционных тестах, `str::format` placeholders в тестах,
  doc-комментарий в core/lang.sh, best-practices.md)
- stray-файлы в git: `changelog-generator/assets/sample_git_log.txt`,
  `skill-creator/LICENSE.txt` — оба в `.agents/`, намеренные (вендор)

Замечание: чисто.

---

## 4. bs-docs-sync — синхронизация en/ru

- missing twin: 0
- расхождений количества секций (`##`): 0

Замечание: чисто.

---

## 5. skill-security-auditor — аудит скиллов

Verdict: **FAIL** (13 находок), но все бенигн — тот же набор, что и
в прошлом прогоне:

- `brainstorming/scripts/server.cjs` (CODE-EXEC) — вендоренный
  obra/superpowers; `cp.exec(BRAINSTORM_OPEN_CMD ...)` — штатное
  открытие браузера
- `ci-cd-pipeline-builder/scripts/pipeline_generator.py` (DEPS-RUNTIME,
  4 шт.) — генерирует YAML с pip install — это его функция
- STRUCTURE — подкаталоги без SKILL.md (assets/expected_outputs и т.п.)

Вывод: реальных рисков в `.agents/skills/` нет.

---

## 6. pr-review-expert — ревью последних изменений (HEAD~2..HEAD)

- 5 файлов, 24 insertions / 69 deletions
- Коммиты: b323571 (CI single job), f0862ef (BS_VERSION single source)
- Blast radius: LOW — версия (core/version.sh), тесты (testinstall.sh),
  CI; ядро не затронуто
- Security-скан диффа: чисто (eval/exec/curl/wget не найдены)
- Содержательно: устранён дублирующий источник BS_VERSION (был в `bs`
  и `const.sh`), тест testinstall.sh теперь читает версию из
  core/version.sh — правильное направление

---

## 7. tech-debt-tracker — сканер техдолга

- Files: 447, Lines: 203 104, Debt items: 14 993, Health: 0/100,
  Density: 33.54 items/file
- **Замечание (важно, повтор)**: скан включает `.agents/` (вендоренные
  скиллы с демо-данными) и `.art/` — цифры нерепрезентативны. Реальный
  вывод требует exclude-конфиг (`.agents/**`, `.art/**`, `.git/**`,
  `examples/`, `CHANGELOG.md`)
- Top items — все из `.agents/skills/skill-creator/` (вендор)

---

## 8. codebase-onboarding — онбординг-анализ

- Файлов: 469; Shell: 180, Python: 38, JS: 3, TS: 1
- Крупнейшие: `.art/lect-bash.pdf` 3.6MB, `.art/all-functions.md`
  139.5KB, core/lang.sh 68.8KB, lib/audit/systemaudit.sh 61.4KB
- Замечание (повтор): в «крупнейших файлах» артефакты `.art/` и
  вендор `.agents/` — нужен exclude для чистого вывода

---

## 9. write-a-skill — валидаторы структуры

**Баг исправлен в этой сессии**: `KeyError: 'max_lines_threshold'`
(строка 228) — ранний return в `analyze()` при отсутствии SKILL.md не
содержал ключ. Фикс: полный dict в раннем return + защитный `.get` в
render_text.

- `skill_structure_validator.py` — больше не крашится; на пустой папке
  корректный отчёт с FAIL. На самом скилле: 4/6 — 2 известных FAIL
  (157 строк > 100; круговая ссылка SKILL.md ↔
  references/companion_tooling.md — намеренная перекрёстная ссылка)
- `skill_description_validator.py` — PASS (3-е лицо, триггер, глагол)
- `skill_review_checklist_runner.py` — не запускался (требует интерактив)

---

## 10. changelog-generator — commit_linter

- 10 последних коммитов: 4 valid, 6 invalid
- Нарушения те же: `release:` не входит в набор типов скилла;
  русские описания со scope парсятся, но `release:` — нет
- **Замечание (повтор)**: `release:` — устоявшаяся практика репозитория;
  линтер шумит, нужна настройка допустимых типов под локальные

---

## 11. skill-doctor — оценка сетапа

- `~/.claude/projects` отсутствует (есть только cache/downloads;
  рабочая среда — opencode) → по правилу скилла оценка невозможна,
  остановлен
- Конвейер (collect_sessions) запускается, ошибка осмысленная

---

## 12. ci-cd-pipeline-builder

- stack_detector: языки не определены (чистый bash — нет
  package.json/pyproject)
- pipeline_generator: пустой скелет (no lint/test/build commands)
- **Must-fix закрыт**: `.github/workflows/ci.yml` запушен коммитом
  b323571 (single job: syntax + ShellCheck + docs-code `|| true` +
  полный тестовый прогон); вместо этого повторно запускать генератор
  не требуется

---

## 13. mcp-server-builder

- Не применялся (нет MCP-сервера в репо). Задел прежний: `bs` CLI
  (list, doctor, run) + OpenAPI-клиент `lib/api` — кандидат на сборку
  MCP-сервера позже

---

## 14. Процессные скилы

- `zero-hallucination-coder` — дисциплина применена в этой сессии при
  починке write-a-skill (Discuss→Map→Decompose→Execute→Verify:
  воспроизведение бага, root-cause, минимальный фикс, верификация)
- `systematic-debugging` — применён неявно (4-фазный разбор KeyError)
- `verification-before-completion` — применён (воспроизвёл краш до фикса,
  прогнал краш-сценарий и рабочий скилл после)
- `named-persona-adversarial-review` — не запускался (нет задачи ревью)
- `grill-me` / `handoff` / `git-worktree-manager` / `skill-creator` /
  `dispatching-parallel-agents` / `subagent-driven-development` — не
  запускались (нет подходящей задачи); скрипты проверены на
  запускаемость (handoff_template_generator, worktree_manager,
  quick_validate — exit 0)

---

## Сводка

| Скилл | Статус |
| --- | --- |
| bs-validate | PASS |
| bs-check-docs-code | 13 намеренных находок |
| bs-check-artifacts | PASS |
| bs-docs-sync | PASS |
| skill-security-auditor | FAIL (13 бенигн) |
| pr-review-expert | PASS (LOW) |
| tech-debt-tracker | работает, нужен exclude-конфиг |
| codebase-onboarding | работает, нужен exclude-конфиг |
| write-a-skill | **баг KeyError исправлен**; структура 4/6 (2 известных) |
| changelog-generator | работает, линтер шумит на `release:` |
| skill-doctor | недоступен без Claude Code истории |
| ci-cd-pipeline-builder | CI запушен (b323571), генератор — скелет |
| mcp-server-builder | не применён (нет задачи) |
| процессные | применены частично |

## Must fix (следующая сессия)

1. ~~`write-a-skill` KeyError~~ — **исправлено в этой сессии**
2. `commit_linter` — настроить допустимые типы под `release:`
3. `tech-debt-tracker` / `codebase-onboarding` — конфиг исключений
   (`.agents/`, `.art/`)
4. ~~`.github/workflows/ci.yml` — запушен~~ — **закрыт (b323571)**
5. Чистка `examples/README.md` (BOSA-хвост) + `args.md` выдержка
6. (необязательно) `write-a-skill/SKILL.md` — уложить в 100 строк

## Вердикт

PASS WITH NOTES — единственный реальный баг (write-a-skill) исправлен;
остальные находки намеренные или конфигурационные.