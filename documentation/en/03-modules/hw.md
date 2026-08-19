# system::hw — Hardware information

[↑ Modules](lib-modules-overview.md)

`lib/system/hw.sh` provides linguistic wrappers over the classic hardware
inspection tools. Load it with `load "lib/system/hw"`.

Design rules:

- Two layers: **getters** return a single machine-readable value on stdout
  (for scripting), **reports** print human-readable summaries built on the
  getters.
- Every function checks for its tool with `utils::has` and reports a readable
  error (with the package to install) instead of a bare "command not found".
- DMI values are read from sysfs first (no root needed), with `dmidecode -s`
  as fallback.
- The only I/O-heavy operation, `system::hw::badblocks_scan`, is read-only and
  honors `FRAMEWORK_DRY_RUN`.

## Getters (single value)

```bash
system::hw::cpu_model           # "Intel(R) Core(TM) i7-8650U CPU @ 1.90GHz"
system::hw::cpu_cores           # physical cores
system::hw::cpu_threads         # logical threads
system::hw::cpu_mhz             # current frequency
system::hw::cpu_flags_count     # number of CPU feature flags
system::hw::mem_total           # total RAM, MiB
system::hw::mem_available       # available RAM, MiB
system::hw::product_name        # DMI product name
system::hw::vendor              # DMI vendor
system::hw::bios_version        # BIOS version
```

Example:

```bash
echo "Cores: $(system::hw::cpu_threads), RAM: $(system::hw::mem_total) MiB"
```

## Reports (human-readable)

```bash
system::hw::cpu                 # CPU summary (built on the getters)
system::hw::memory              # free -h, with /proc/meminfo fallback
system::hw::block               # lsblk tree
system::hw::pci                 # lspci -tv
system::hw::usb                 # lsusb -tv
system::hw::gpu                 # VGA/3D controllers from lspci
system::hw::dmi [TYPE]          # DMI report (dmidecode)
system::hw::dmesg [N]           # last N kernel messages (default 20)
system::hw::lshw                # lshw -short
system::hw::disk_params /dev/sda    # hdparm -I (root)
system::hw::badblocks_scan /dev/sda # badblocks -sv — read-only, dry-run aware
```

## Full report

```bash
system::hw::summary     # every available section; never fails
system::hw::info        # list of system::hw:: commands
```

## Return codes

`E_SUCCESS` on success, `E_INVALID` for bad arguments (e.g. a non-block
device), `E_ERROR` when the required tool is missing or privileges are
insufficient.
