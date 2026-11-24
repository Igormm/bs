---
name: bs-function-contract
description: Define and review BS function contracts across posix and bash4/zsh tiers and different purposes — predicates, getters, mutators, emitters and callbacks; status/stdout/stderr/output-variable channels; canonical API records and string/json/xml rendering
type: prompt
whenToUse: When adding or reviewing any public BS function, especially when deciding how it returns data, how API and human output are separated, or how posix and bash4 return channels differ
tier: both
arguments:
  - function_signature
---

# Контракт функции BS / BS function contract

Контракт функции — это **назначение + каналы + коды + формат**. Он не зависит
от яруса; ярус меняет только доступные механизмы. Выбери назначение до того,
как написал `printf` или `return`.

A function contract is **purpose + channels + statuses + format**. It is the
same across tiers; the tier only changes the available mechanisms.

## 1. Назначение определяет каналы / Purpose determines channels

| Назначение / Purpose | Признаки имени | stdout | stderr | статус |
| --- | --- | --- | --- | --- |
| **Предикат** / predicate | `is_*`, `has_*`, `exists`, `can_*`, `supports` | пусто | обычно пусто | `0` истина, `1` ложь/нет, `2` неверный вызов |
| **Геттер** / getter | `get_*`, `list_*`, `info`, `stats`, `detect` | данные | диагностика | `0` успех, `1` нет/ошибка, `2` неверный аргумент |
| **Действие** / action | `set_*`, `create`, `delete`, `write_*`, `apply`, `run` | пусто по умолчанию | диагностика | `0` успех, доменный код ошибки |
| **Эмиттер** / emitter | `emit`, `render`, `show`, `print`, `report` | представление | диагностика | `0` успех |
| **Колбэк/хук** / callback | вызывается каркасом | не контрактен | не контрактен | трактует вызывающий |

**Не смешивай назначения.** Если действие вернуло ID — это действие с выходной
переменной, а не «геттер, который случайно меняет состояние».

## 2. Три возвращаемых канала / Three return channels

1. **Статус** — `return` / код завершения. Главный канал для предикатов и действий.
2. **stdout** — только результат геттера или представление эмиттера.
3. **stderr** — только диагностика; никогда не данные результата.

Правила:

- В геттере **нет** `log::info/success/debug/trace/print/section`: они пишут в
  stdout и портят `value=$(func)`. Диагностика — `log::warn/error` или stderr.
- Эмиттер нельзя использовать как источник данных, если его формат не
  документирован как стабильный API.
- Функция не вызывает `exit`; выход — за точкой входа (`bs_exit`,
  `bs_error_exit`, `error::exit`).
- `$(...)` обрезает завершающие переводы строк и выполняет функцию в
  подоболочке: состояние родителя не меняется.

## 3. Когда нужна выходная переменная / When an output variable is required

Используй её, если:

- функция меняет состояние **и** возвращает значение (`pop`, `shift`, `next`);
- значение нужно в горячем пути, где `$(...)` создаёт лишний fork;
- значение может содержать завершающие переводы строк;
- posix-функция возвращает несколько значений.

Формы:

```bash
# Универсальная форма: необязательное имя выходной переменной.
# Empty name => stdout; named variable => no subshell.
bs_arr_pop array_name [out_var]

# bash4: local -n допустим, но публичный контракт остаётся тем же.
group::module::get_into out_var arg
```

В posix имя переменной проверяют **до `eval`** (`bs_data_ret`); нельзя
принимать `a;touch /tmp/x`. В DocBlock это фиксируется:

```bash
# @param $2 [out_var] Имя выходной переменной; пусто — stdout
# @stdout value only when out_var is empty
# @warning Do NOT call a state-mutating getter as $(...); pass an output variable.
```

## 4. Много значений / Multiple values

- **posix:** массив/словарь слоя данных, имя передаёт вызывающий:
  `bs_utils_split out_array text separators`, `bs_map_*`, `bs_arr_*`.
- **bash4/zsh:** настоящий массив или nameref; имя выходной структуры — часть
  публичного контракта.
- stdin/stdout-поток допустим для таблиц/записей, но документируй `@stdin` и
  границы записей.

## 5. API-формат отделён от человеческого вывода / API format is separate

Стабильный машинный контракт BS:

```text
data method -> canonical key=value records -> format::emit -> string|json|xml
human CLI   -> log::section/info/success/error
```

Каноническая запись `lib/data/format.sh`:

- одна пара `key=value` на строку;
- деление по **первому** `=`;
- пустая строка разделяет записи;
- значение может быть пустым;
- метод **не форматирует** сам — он отдаёт записи в `format::emit`.

Пример:

```bash
status_json() {
    format::record name "$name" state "$state" count "$count" \
        | format::emit json
}
```

`string/json/xml` выбирает `BS_OUTPUT_FORMAT` или явный аргумент `--format`.
Человеческие рамки и вердикты — только в CLI-слое, не в геттере.

## 6. Коды возврата / Status codes

| Код | Значение |
| --- | --- |
| `0` | успех / истина |
| `1` | нет / ложь / обычная ошибка (`${E_ERROR:-1}`) |
| `2` | неверный вызов, имя или аргумент (`${E_INVALID:-2}`) |
| `LIB_ERROR_*` | доменная ошибка из `core/const.sh` |

Последняя команда функции — её статус. Если последняя команда может вернуть
не то, ставь явный `return`.

## 7. Документация — часть контракта / Documentation is part of it

Для публичной функции обязательны:

```bash
# @description Что делает функция (RU/EN).
# @contract predicate|getter|action|emitter|callback
# @param $1 {string} ...
# @param [$2=out_var] ...
# @returns 0 ...
# @returns 1 ...
# @stdout ...        # только если stdout — часть контракта
# @stderr ...        # если диагностика обещана
# @example
#   ...
```

`@contract` — невербальный маркер для ревью/генерации; он не меняет поведение.

## 8. Быстрый чек-лист / Quick checklist

- [ ] Назначение выбрано: predicate / getter / action / emitter / callback.
- [ ] stdout содержит только обещанные данные/представление.
- [ ] stderr содержит только диагностику.
- [ ] Нет `exit` внутри библиотечной функции.
- [ ] Stateful getter не вызывается через `$(...)`.
- [ ] Выходная переменная документирована; posix-имя проверено до `eval`.
- [ ] API-метод отдаёт canonical records, форматирует только `format::emit`.
- [ ] Человеческий вывод живёт в CLI-слое.
- [ ] Коды и DocBlock совпадают с реальным поведением.
