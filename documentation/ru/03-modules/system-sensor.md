[↑ Указатель документации](../README.md)

# Модуль `sensor`

Сенсорные устройства ввода в Linux: обнаружение через `/sys/class/input`,
декодирование событий evdev (`/dev/input/eventN`) чистым Bash (`dd` + `od`,
без внешних парсеров), декодирование возможностей, живая диагностика.

Ярус: **только Linux** (`/proc`/`/sys`/evdev). Без доступа — чистая
деградация с определёнными кодами `E_*` / `LIB_ERROR_*`.

Источник: [lib/system/sensor.sh](../../../lib/system/sensor.sh)

## Подключение

```bash
#!/usr/bin/env bs

load "lib/system/sensor"
```

## Тестовые хуки

| Переменная | По умолчанию | Назначение |
|---|---|---|
| `SENSOR_INPUT_DIR` | `/sys/class/input` | переопределение корня sysfs |
| `SENSOR_DEV_DIR` | `/dev/input` | переопределение каталога устройств |
| `SENSOR_EVENT_SIZE` | авто (`getconf LONG_BIT`: 24/16) | размер записи `input_event` |

## Обнаружение

```bash
sensor::devices          # "eventN<TAB>имя" для всех event-устройств
sensor::devices touch    # фильтр-подстрока, без учёта регистра
sensor::info event5      # name/phys/readable/capabilities в формате k=v
sensor::check event5     # 0 | LIB_ERROR_FILE_NOT_FOUND | LIB_ERROR_PERMISSION_DENIED
```

## События

```bash
sensor::events event5            # поток "sec usec type code value" без конца
sensor::events event5 10         # ...или ровно 10 записей
sensor::detect event5 2          # первая линия события за 2 с, иначе LIB_ERROR_TIMEOUT
sensor::record_size              # 24 на 64-бит, 16 на 32-бит
sensor::type_name 3              # EV_ABS
sensor::abs_name 53              # ABS_MT_POSITION_X
sensor::code_name 1 330          # BTN_TOUCH
```

## Возможности

```bash
sensor::capabilities event5 ev   # EV_SYN EV_KEY EV_ABS ... (по одному в строке)
sensor::capabilities event5 key  # BTN_TOUCH ...
sensor::abs_range event5 0       # "min max fuzz flat" (если sysfs отдаёт)
```

## Диагностика

```bash
sensor::diagnose event5 3
```

Отчёт строками `[PASS]/[WARN]/[FAIL]/[INFO]`: наличие устройства в sysfs,
права на чтение (подсказка: группа `input`), возможности `EV_ABS` +
`BTN_TOUCH`, диапазоны осей и живое окно 3 с: скорость потока событий,
наблюдённые размахи осей, «залипание» оси (одно значение в ≥3 отсчётах),
счёт нажатий. Код `E_SUCCESS`, если `[FAIL]` нет.

## Связанное

- `examples/sensor_diag.sh` — CLI-точка диагностики.
- `examples/sensor_tui.sh` — TUI-монитор реального времени (`bs run examples/sensor_tui.sh`).
- `lib/tui/tui.sh` — виджеты TUI, используемые монитором.
