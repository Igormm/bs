[↑ Указатель документации](../README.md)

# Модуль `devicectl` + `devprofile` + `pointers` + `keyboard` + `locale`

Движок конфигурации устройств и его драйверы. `devicectl` регистрирует
драйверы за единым контрактом и диспетчеризует списки устройств, параметры и
живые get/set. `devprofile` сохраняет набор устройств как переиспользуемый
BS-профиль (INI с управляемыми маркерами) и применяет его заново. Эталонные
драйверы: `pointers` (тачпады, трекболы и трекпоинт Lenovo), `keyboard`
(раскладка: layout/model/variant/options) и `locale` (системная локаль).

Ярус: **Linux, X11 и Wayland с честной деградацией**
(`DEVICECTL_BACKEND` = `x11`/`wayland`/`none`). Чтение и установка без
бэкенда возвращают определённые коды (`LIB_ERROR_DEPENDENCY_MISSING`,
`LIB_ERROR_PLATFORM_UNSUPPORTED`) — никогда не молчаливый успех.
Полноэкранный [`devices_tui.sh`](../../../examples/devices_tui.sh) показывает
каждое устройство с текущими параметрами, применяет изменения вживую и
сохраняет/загружает профили.

Источники: [lib/system/devicectl.sh](../../../lib/system/devicectl.sh),
[lib/system/devdriver.sh](../../../lib/system/devdriver.sh),
[lib/system/devprofile.sh](../../../lib/system/devprofile.sh),
[lib/system/pointers.sh](../../../lib/system/pointers.sh),
[lib/system/keyboard.sh](../../../lib/system/keyboard.sh),
[lib/system/locale.sh](../../../lib/system/locale.sh)

## Контракт драйвера

Каждый драйвер — модуль `lib/system/<name>.sh` в пространстве имён
`driver::<name>::`, реализующий:

| Функция | Возвращает |
|---|---|
| `driver::<name>::detect` | устройства: `handle<TAB>label<TAB>kind` |
| `driver::<name>::params <handle>` | `param<TAB>type<TAB>current<TAB>default<TAB>choices<TAB>tip` |
| `driver::<name>::get <handle> <param>` | текущее значение |
| `driver::<name>::set <handle> <param> <value>` | живое применение; `0` или код ошибки |
| `driver::<name>::snapshot <handle>` | все `param<TAB>value` |

Типы параметров: `bool`, `enum:a,b,c`, `int`, `range:min:max:step`,
`string`, `keys`. Добавить драйвер — значит зарегистрировать его; TUI менять
не нужно.

Драйверу с фиксированным каталогом параметров не нужно писать `params` и
`snapshot` вручную. Достаточно `driver::<name>::__catalog [args…]` (строки
`param<TAB>type<TAB>default<TAB>choices<TAB>tip`) и `get`, а остальное
делегировать в [lib/system/devdriver.sh](../../../lib/system/devdriver.sh):

```bash
driver::<name>::params()   { devdriver::params   <name> "$1" "" ; }
driver::<name>::snapshot() { devdriver::snapshot <name> "$1" "" ; }
```

Третий аргумент — значение на случай, если `get` упал (`pointers` передаёт
`unknown`); остальные аргументы уходят в `__catalog` (`pointers` передаёт тип
устройства). Помощники сохраняют пустые поля каталога, поэтому пустые
`choices` или `default` не сдвигают колонки. Все три встроенных драйвера
используют их.

Реестр по умолчанию: `DEVICECTL_DRIVERS=(pointers keyboard locale)`.

| Драйвер | Устройство | Параметры |
|---|---|---|
| `pointers` | тачпад / трекбол / трекпоинт | `speed`, `tap_to_click`, `natural_scroll`, `profile`, `sens` |
| `keyboard` | `Keyboard layout` | `layout`, `model`, `variant`, `options` (X11-раскладка через `localectl`) |
| `locale` | `System locale` | `lang` (`localectl set-locale` или `/etc/locale.gen`) |

## Подключение

```bash
#!/usr/bin/env bs

load "lib/system/devicectl"
load "lib/system/devprofile"
```

## Тестовые хуки

| Переменная | По умолчанию | Назначение |
|---|---|---|
| `DEVICECTL_BACKEND` | *(определяется)* | принудительно `x11` / `wayland` / `none` |
| `DEVICECTL_DRIVER_EXT` | `sh` | расширение файла драйвера |
| `BS_PROFILE_DIR` | `~/.config/bs/profiles/devices` | корень хранения профилей |
| `DRIVER_POINTERS_XINPUT` | `xinput` | бинарь xinput или шим для тестов |
| `DRIVER_POINTERS_SENS_PATH` | *(glob i8042)* | sysfs-файл чувствительности трекпоинта |

## API движка

```bash
device::backend                      # x11 | wayland | none (кэшируется)
device::registry foopad              # зарегистрировать драйвер
device::list                         # driver<TAB>handle<TAB>label<TAB>kind
device::params pointers "my device"  # каталог параметров с текущими значениями
device::get pointers "my device" speed
device::set pointers "my device" speed 0.4
device::snapshot pointers "my device"
```

## Профили

```bash
printf 'pointers\tTPPS/2 IBM TrackPoint\tsens\t160\n' | devprofile::save default
devprofile::list                     # имена профилей
devprofile::load default             # driver<TAB>handle<TAB>param<TAB>value
devprofile::apply default            # реплей через device::set
devprofile::active                   # последний использованный профиль
devprofile::remove default
```

Профили — INI-секции `[driver:handle]` с маркерами `# BEGIN bs-devices` /
`# END bs-devices`, пишутся атомарно; пустые значения пропускаются,
неуправляемое содержимое при загрузке игнорируется.
