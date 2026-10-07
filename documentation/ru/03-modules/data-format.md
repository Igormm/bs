[↑ Указатель документации](../README.md)

# Модуль `format`

Рендер канонических записей данных в `string`, `json` или `xml` — формат
выбирается параметром. Метод выдаёт данные один раз как канонические записи
`key=value`; слой формата превращает их в выбранное представление. Без внешних
зависимостей (чистый Bash); `jq`/`python3` не нужны.

Ярус: **портируемый** (чистый Bash 4+).

Источник: [lib/data/format.sh](../../../lib/data/format.sh)

## Подключение

```bash
#!/usr/bin/env bs

load "lib/data/format"
```

## Тестовые хуки

| Переменная | По умолчанию | Назначение |
|---|---|---|
| `BS_OUTPUT_FORMAT` | `string` | выбранный формат (`string`/`json`/`xml`) |
| `BS_FORMAT_ROOT` | `record` | имя корневого XML-элемента (одна запись) |

## Каноническая грамматика

- Поле на строку: `key=value`; деление по **первому** `=`, поэтому значение
  может содержать `=`.
- Пустая строка разделяет записи (геттер, вернувший несколько строк).
- Порядок полей сохраняется как выведен.

## API

```bash
format::list                    # string, json, xml (по одному в строке)
format::validate json           # E_SUCCESS / LIB_ERROR_INVALID_INPUT
format::record iface eth0 ip 192.0.2.10   # канонические строки в stdout
format::emit json               # stdin записи → stdout отрендерено
format::emit_lines route        # каждая входная строка → своя запись (блоб-геттеры)
format::render::string          # рендереры по форматам
format::render::json
format::render::xml
```

## Рендер

`string` — единственное поле печатает **только значение** (человеческий дефолт
для скаляра, например IP); несколько полей — `key=value`:

```bash
printf 'ip=192.0.2.10\n' | format::emit string      # 192.0.2.10
printf 'iface=eth0\nip=192.0.2.10\n' | format::emit string
# iface=eth0
# ip=192.0.2.10
```

`json` — одна запись → объект, несколько → массив объектов; экранирует
`" \ \n \r \t` и управляющие символы:

```bash
printf 'ip=192.0.2.10\n' | format::emit json        # {"ip":"192.0.2.10"}
printf 'a=1\n\na=2\n'    | format::emit json        # [{"a":"1"},{"a":"2"}]
format::emit json </dev/null                        # {}
```

`xml` — одна запись → `<record>…</record>`, несколько →
`<records><record>…</record>…</records>`; экранирует `& < > " '`; имя корня —
`BS_FORMAT_ROOT`:

```bash
printf 'ip=192.0.2.10\n' | format::emit xml
# <record><ip>192.0.2.10</ip></record>
BS_FORMAT_ROOT=node format::emit xml <<< 'k=v'
# <node><k>v</k></node>
```

## Интеграция в метод

```bash
system::network::interface() {
    local -r iface="${1:?interface required}"
    local ip family
    # ... получение ...
    { format::record iface "${iface}"
      format::record ip "${ip}"
      format::record family "${family}"
    } | format::emit "${BS_OUTPUT_FORMAT:-string}"
}
```

Позиционные сигнатуры не меняются; `--format` парсит CLI (через `core/args`) и
экспортирует `BS_OUTPUT_FORMAT`. Библиотечные вызовы могут задать
`BS_OUTPUT_FORMAT=json` (или `xml`) в окружении.

## Коды ошибок

| Код | Значение |
|---|---|
| `E_SUCCESS` | отрендерено |
| `LIB_ERROR_INVALID_ARGS` | пустой аргумент формата |
| `LIB_ERROR_INVALID_INPUT` | неизвестный формат |

## Почему так

Формат — это замена базиса данных: `json`/`xml` изоморфны (round-trip),
`string` — лоссовая проекция для человека. Один канон, из которого выводятся
все виды, держит слои ортогональными (`N геттеров + M форматов`, а не `N × M`).
Для вложенных структур `lib/data/dataprocessor` может конвертировать
`json → xml` при наличии `jq`/`xmllint`; здешний рендерер их не требует.
