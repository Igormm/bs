# system::hw — Информация об оборудовании

[↑ Модули](lib-modules-overview.md)

`lib/system/hw.sh` предоставляет «лингвистические» обёртки над классическими
инструментами инспекции железа. Подключение: `load "lib/system/hw"`.

Принципы:

- Два слоя: **геттеры** возвращают одно машиночитаемое значение в stdout
  (для скриптов), **отчёты** печатают человекочитаемые сводки, построенные
  на геттерах.
- Каждая функция проверяет наличие инструмента через `utils::has` и сообщает
  читаемую ошибку (с именем пакета для установки) вместо голого
  «command not found».
- DMI-значения читаются сначала из sysfs (root не нужен), с фолбэком на
  `dmidecode -s`.
- Единственная ресурсоёмкая операция, `system::hw::badblocks_scan`, работает
  в режиме только-чтение и учитывает `FRAMEWORK_DRY_RUN`.

## Геттеры (одно значение)

```bash
system::hw::cpu_model           # "Intel(R) Core(TM) i7-8650U CPU @ 1.90GHz"
system::hw::cpu_cores           # физические ядра
system::hw::cpu_threads         # логические потоки
system::hw::cpu_mhz             # текущая частота
system::hw::cpu_flags_count     # число CPU-флагов
system::hw::mem_total           # всего RAM, MiB
system::hw::mem_available       # доступно RAM, MiB
system::hw::product_name        # продукт (DMI)
system::hw::vendor              # производитель (DMI)
system::hw::bios_version        # версия BIOS
```

Пример:

```bash
echo "Cores: $(system::hw::cpu_threads), RAM: $(system::hw::mem_total) MiB"
```

## Отчёты (человекочитаемые)

```bash
system::hw::cpu                 # сводка о CPU (построена на геттерах)
system::hw::memory              # free -h, запасной вариант /proc/meminfo
system::hw::block               # дерево lsblk
system::hw::pci                 # lspci -tv
system::hw::usb                 # lsusb -tv
system::hw::gpu                 # VGA/3D-контроллеры из lspci
system::hw::dmi [TYPE]          # отчёт DMI (dmidecode)
system::hw::dmesg [N]           # последние N сообщений ядра (по умолчанию 20)
system::hw::lshw                # lshw -short
system::hw::disk_params /dev/sda    # hdparm -I (root)
system::hw::badblocks_scan /dev/sda # badblocks -sv — read-only, dry-run
```

## Полный отчёт

```bash
system::hw::summary     # все доступные секции; никогда не падает
system::hw::info        # список команд system::hw::
```

## Коды возврата

`E_SUCCESS` при успехе, `E_INVALID` при неверных аргументах (например, не
блочное устройство), `E_ERROR` когда нужный инструмент отсутствует или не
хватает привилегий.
