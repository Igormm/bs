---
name: bs-cli-flags-style
description: Разрабатывать структуру ключей/значений и код-стайл CLI-скриптов BS в конвенциях docker/podman/go — --flag value, --flag=value, bool без значения, повторяемые флаги, подкоманды, -- разделитель; поверх core/args, с трезвой оценкой, что парсер уже умеет, а что требует расширения
type: prompt
whenToUse: При написании нового скрипта BS с параметрами; при ревью ключей существующих скриптов; при проектировании расширений core/args (шорт-алиасы, repeat-флаги, негация)
tier: both
arguments:
  - script
---

Применяй к `${script}` (или к любому новому CLI-скрипту BS) **грамматику ключей/значений и код-стайл в конвенциях docker/podman/go**: параметры организуются единообразно, help читается как справка взрослого CLI, а не как догадка по исходникам.

## 0. Основа: что уже умеет core/args

Не изобретай парсер — `core/args` уже даёт:

| Грамматика | В core/args |
|---|---|
| `--name value` и `--name=value` | ✅ оба варианта |
| bool-флаг без значения (`--wizard`) | ✅ `args::flag wizard` |
| value-флаг с дефолтом и валидатором | ✅ `args::flag name value default validator` |
| валидаторы number / enum / колбэк | ✅ |
| подкоманды (`docker container run`) | ✅ `args::level 1 run stop` |
| вариадик-уровень (`server server server`) | ✅ `args::level 3 server...` |
| `--` разделитель (всё после — позиционные) | ✅ `args::rest` |
| автогенерация `--help` | ✅ `args::parse` / `args::require` |
| bash-completion | ✅ `args::completion` |
| шорт-алиасы (`-p 8080`) | ✅ `args::flag_short port p` |
| повторяемые флаги (`--env A --env B`) | ✅ `args::flag_repeat env` |
| явное bool-значение (`--color=false`) | ✅ `args::flag_bool_value color` |
| автоматическая негация (`--no-cache`) | ❌ non-goal; объявите отдельный bool-флаг |

## 1. Грамматика ключей и значений

1. **Длинный флаг — единственная норма.** `--max-retries 3` и `--max-retries=3` эквивалентны; в скрипте читай через `args::flag_get` — синтаксис ввода не важен.
2. **Bool — без значения.** `--wizard` включает режим; проверка через `args::flag_is_set`. Исключение — явно объявленный `args::flag_bool_value`: тогда допустимы `--flag=true` и `--flag=false`. Не принимай `--wizard yes`.
3. **Негация** — только где семантика требует «включить по умолчанию, выключить флагом»: для bool-value используйте `--flag=false` либо объявите отдельный bool-флаг `--no-cache`. Автоматическое преобразование `--no-*` не поддерживается.
4. **Повторяемые флаги — массив значений.** `--env A=1 --env B=2` → список. Один флаг — одна сущность; не кодируй списки через разделители в одном значении (`--env A=1,B=2` — запрещено).
5. **Один флаг — одно значение/одно действие.** Нет скрытых режимов: флаг не меняет поведение другого флага (стыкуется с `bs-cli-markdown-style`, критерий 3).
6. **`--` — конец флагов.** Всё после — позиционные аргументы (`args::rest`), даже если начинается с `-`.
7. **Подкоманды — дерево.** Взаимоисключающие режимы — это уровни (`args::level`), не флаги: `opencode_serve.sh wizard` и `opencode_serve.sh serve --port 4096`, а не `--mode=wizard`.
8. **Именование флагов** — `lower_snake`, без аббревиатур-сюрпризов: `--max-retries`, не `--mr`. Один символ — одно значение (см. `bs-cli-markdown-style`).
9. **Порядок не важен.** Флаги можно смешивать с позиционными — парсер это позволяет; не требуй «сначала флаги, потом аргументы».

## 2. Код-стайл скрипта

### Структура main()

```
load "core/args" (+ модули по нужде)

main() {
    # 1) Декларации: флаги и уровни — все в начале, по алфавиту имён
    args::flag wizard
    args::flag port value "" number
    args::flag env value
    args::flag_repeat env
    args::flag_describe wizard "…"
    args::flag_describe port "…"
    args::level 1 serve wizard
    args::describe serve "…"
    args::require "$@"

    # 2) Ранний выход: режимы/команды, не требующие остальной проверки
    if args::flag_is_set wizard; then …; fi

    # 3) Чтение: args::flag_get с дефолтом или проверкой
    local -r port="$(args::flag_get port)"
    …
}
```

### Правила чтения

- Значение — через `args::flag_get` (дефолт приходит из декларации).
- Присутствие — через `args::flag_is_set` (отличает «задали явно» от «дефолт»).
- Позиционные — через `args::get N [default]`; «хвост» после `--` — через `args::rest`.
- Валидация значения — колбэк-валидатором в декларации, а НЕ `if [[ … ]]` после парсинга.
- Ошибки валидации — `args::parse` сам пишет `flag "--x" has an invalid value: …`; не дублируй.

### Help

- `--help` обязателен для любого скрипта с флагами (генерируется автоматически).
- Описания двуязычные (RU/EN через `/`), как в примерах фреймворка.
- Первая строка help — `Usage: … [flags]`, дальше выровненные колонки `--flag <value>` / `--flag`.
- Стыкуется с `bs-cli-markdown-style`: help читается без рендеринга.

### Ошибки и exit-коды

- Коды из `core/const` (`E_INVALID`, `E_ERROR`, …), не магические числа.
- Невалидный флаг → парсер, `E_INVALID`; неверные данные → `log::error` + `bs::exit invalid`.
- Сообщение: `flag "--name" …` — называем флаг, а не позицию.

### Документация

В README/шапке скрипта — таблица флагов:

| Flag | Alias | Type | Default | Description |
|---|---|---|---|---|
| `--port` | — | number | 4096 | Порт сервера / server port |
| `--wizard` | — | bool | — | Запустить визард / run wizard |

## 3. Пример: до / после

До (позиционные-угадайка):

```bash
bs run examples/foo.sh 4096 192.168.1.140 true
```

После (docker/go-грамматика):

```bash
bs run examples/foo.sh serve --port 4096 --ip 192.168.1.140 --verbose
```

```bash
args::level 1 serve
args::flag port value 4096 number
args::flag ip value "" validate_ipv4
args::flag verbose
args::require "$@"
```

## 4. Часть C: расширения core/args (реализовано)

- **Шорт-алиас:** `args::flag_short port p`; парсер принимает `-p 8080`,
  `-p=8080` и `-p8080`.
- **Repeat-флаг:** `args::flag_repeat env`; `args::flag_get env` возвращает
  первое значение, `args::flag_get_all env` — все по строкам, а
  `args::flag_values env environments` lossless-копирует значения в bash-массив.
- **Bool-value:** `args::flag_bool_value color`; принимаются `--color`,
  `--color=true` и `--color=false`.
- **Группы коротких флагов:** `-abc`; значение может идти у последнего флага
  группы (`-abp8080`).
- Каждое расширение покрыто unit/portable-тестами, help/completion и примером
  `examples/argsparseexample.sh`.
- Явный non-goal: автоматическое `--no-flag`; для отрицания используйте
  `args::flag_bool_value` с `--flag=false` или отдельный bool-флаг.

## 5. Чеклист ревью ключей

- [ ] Флаги декларированы через `args::flag`, не разобраны руками по `$@`?
- [ ] `--flag value` и `--flag=value` оба принимаются (парсер) и не дублируются в коде?
- [ ] Bool-флаги без значений; нет `--flag yes`? Исключение — объявленный `args::flag_bool_value` с `true`/`false`.
- [ ] Списки — повторяемыми флагами, не `a,b,c`?
- [ ] Взаимоисключающие режимы — подкоманды (`args::level`), не `--mode`?
- [ ] `--` обрабатывается (`args::rest`), если позиционные могут начинаться с `-`?
- [ ] `--help` есть и описывает каждый флаг?
- [ ] Значения валидируются колбэком в декларации, ошибки — `E_INVALID`?
- [ ] README-таблица флагов синхронна с декларациями?
- [ ] Имена `lower_snake`, семантичные, без аббревиатур?
- [ ] Чего не хватает из части C — зафиксировано как задача, а не молчаливый костыль?

## 6. Смежные скиллы

- `bs-cli-markdown-style` — простота вывода/интерфейса (7 критериев).
- `bs-new-lib-module` / `bs-new-core-module` — если расширение парсера оформляется как модуль.
- `bs-write-test` — тесты для новых фич core/args.