[↑ Указатель документации](../README.md)

# Модуль `devicectl` + `devprofile` + `pointers`

Движок конфигурации устройств и его первый драйвер. `devicectl` регистрирует
драйверы за единым контрактом и диспетчеризует списки устройств, параметры и
живые get/set. `devprofile` сохраняет набор устройств как переиспользуемый
BS-профиль (INI с управляемыми маркерами) и применяет его заново. `pointers`
— эталонный драйвер: тачпады, трекболы и трекпоинт Lenovo («красная пипка»)
с чувствительностью, скоростью, прокруткой и tap-to-click.

Ярус: **Linux, X11 и Wayland с честной деградацией**
(`DEVICECTL_BACKEND` = `x11`/`wayland`/`none`). Чтение и установка без
бэкенда возвращают определённые коды (`LIB_ERROR_DEPENDENCY_MISSING`,
`LIB_ERROR_PLATFORM_UNSUPPORTED`) — никогда не молчаливый успех.
Полноэкранный [`devices_tui.sh`](../../../examples/devices_tui.sh) показывает
каждое устройство с текущими параметрами, применяет изменения вживую и
сохраняет/загружает профили.

Источники: [lib/system/devicectl.sh](../../../lib/system/devicectl.sh),
[lib/system/devprofile.sh](../../../lib/system/devprofile.sh),
[lib/system/pointers.sh](../../../lib/system/pointers.sh)

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
