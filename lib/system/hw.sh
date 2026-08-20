#!/usr/bin/env bs
# shellcheck shell=bash
# lib/system/hw.sh — Hardware information module / Модуль информации об оборудовании
#
# Unified, linguistic wrappers over hardware inspection tools:
# /proc/cpuinfo, /proc/meminfo, sysfs DMI, dmidecode, free, lsblk, lshw,
# lspci, lsusb, hdparm, badblocks, dmesg.
# / Единые «лингвистические» обёртки над инструментами инспекции железа.
#
# Two layers / Два слоя:
#   getters  — return a single machine-readable value (cpu_model, mem_total, ...)
#   printers — human-readable reports built on the getters (cpu, memory, summary)
#
# Usage / Использование:
#   load "lib/system/hw"
#   system::hw::summary
#   model="$(system::hw::cpu_model)"
#
# @depends core/const, core/logger, core/utils

# Source Guard / Защита от повторной загрузки
bs::guard "SYSTEM_HW" || return 0

# Зависимости / Dependencies
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh"

# Метаданные модуля / Module metadata
# shellcheck disable=SC2034
declare -g SYSTEM_HW_VERSION="1.0.0"

# ==========================================
# Private helpers / Приватные помощники
# ==========================================

# @private
# @description Require an external tool or report a readable error.
# @param $1 Tool name / Имя инструмента
# @param $2 Package providing it / Пакет с инструментом
# @return 0 if present, E_ERROR otherwise
system::hw::__require_tool() {
  local -r tool="${1:?tool name required}"
  local -r package="${2:-${1}}"

  if ! utils::has "${tool}"; then
    log::error "Tool '${tool}' not found (install package: ${package})"
    return "${E_ERROR}"
  fi
  return "${E_SUCCESS}"
}

# @private
# @description Read a DMI value: sysfs first (no root), dmidecode fallback.
# @param $1 sysfs field name (e.g. product_name) / Поле sysfs
# @param $2 dmidecode -s keyword / Ключевое слово dmidecode
# @stdout the DMI value / Значение DMI
# @return 0 on success, E_ERROR if unavailable
system::hw::__dmi_value() {
  local -r field="${1:?sysfs field required}"
  local -r keyword="${2:?dmidecode keyword required}"
  local value=""

  if is::readable "/sys/class/dmi/id/${field}"; then
    value="$(cat "/sys/class/dmi/id/${field}")"
  elif utils::has dmidecode; then
    value="$(utils::quiet_err dmidecode -s "${keyword}")"
  fi

  if is::empty "${value}"; then
    log::error "DMI value '${field}' unavailable (needs root?)"
    return "${E_ERROR}"
  fi
  printf '%s\n' "${value}"
}

# ==========================================
# Getters: single machine-readable values
# Геттеры: одно машиночитаемое значение
# ==========================================

# @description CPU model name (data) / Модель CPU (данные).
# @stdout e.g. "Intel(R) Core(TM) i7-8650U CPU @ 1.90GHz"
system::hw::cpu_model() {
  awk -F': ' '/^model name/ {print $2; exit}' /proc/cpuinfo
}

# @description Number of physical CPU cores (data) / Физические ядра (данные).
# @stdout core count
system::hw::cpu_cores() {
  awk -F': ' '/^cpu cores/ {print $2; exit}' /proc/cpuinfo
}

# @description Number of logical CPU threads (data) / Логические потоки (данные).
# @stdout thread count
system::hw::cpu_threads() {
  if utils::has nproc; then
    nproc
  else
    grep -c '^processor' /proc/cpuinfo
  fi
}

# @description Current CPU frequency in MHz (data) / Текущая частота CPU (данные).
# @stdout integer MHz
system::hw::cpu_mhz() {
  awk -F': ' '/^cpu MHz/ {printf "%.0f", $2; exit}' /proc/cpuinfo
}

# @description Number of CPU feature flags (data) / Число CPU-флагов (данные).
# @stdout flag count
system::hw::cpu_flags_count() {
  awk -F': ' '/^flags/ {print split($2, f, " "); exit}' /proc/cpuinfo
}

# @description Total RAM in MiB (data) / Всего RAM в MiB (данные).
# @stdout total memory in MiB
system::hw::mem_total() {
  awk '/^MemTotal/ {printf "%d", $2 / 1024; exit}' /proc/meminfo
}

# @description Available RAM in MiB (data) / Доступно RAM в MiB (данные).
# @stdout available memory in MiB
system::hw::mem_available() {
  awk '/^MemAvailable/ {printf "%d", $2 / 1024; exit}' /proc/meminfo
}

# @description Product name from DMI (data) / Имя продукта из DMI (данные).
# @stdout e.g. "20HQS02F00 ThinkPad T480"
system::hw::product_name() {
  system::hw::__dmi_value product_name system-product-name
}

# @description Hardware vendor from DMI (data) / Производитель из DMI (данные).
# @stdout e.g. "LENOVO"
system::hw::vendor() {
  system::hw::__dmi_value sys_vendor system-manufacturer
}

# @description BIOS version from DMI (data) / Версия BIOS из DMI (данные).
# @stdout e.g. "N24ET67W (1.42 )"
system::hw::bios_version() {
  system::hw::__dmi_value bios_version bios-version
}

# ==========================================
# Printers: human-readable reports
# Принтеры: человекочитаемые отчёты
# ==========================================

# @description Show CPU summary (built on the getters).
# @description Сводка о CPU (построена на геттерах).
# @example
#   system::hw::cpu
system::hw::cpu() {
  if ! is::readable /proc/cpuinfo; then
    log::error "Cannot read /proc/cpuinfo"
    return "${E_ERROR}"
  fi

  printf 'Model:   %s\n' "$(system::hw::cpu_model)"
  printf 'Cores:   %s physical, %s logical\n' \
    "$(system::hw::cpu_cores)" "$(system::hw::cpu_threads)"
  printf 'MHz:     %s\n' "$(system::hw::cpu_mhz)"
  printf 'Flags:   %s features\n' "$(system::hw::cpu_flags_count)"
}

# @description Show memory usage (free -h, with /proc/meminfo fallback).
# @description Использование памяти (free -h, запасной вариант /proc/meminfo).
# @example
#   system::hw::memory
system::hw::memory() {
  if utils::has free; then
    free -h
    return "${E_SUCCESS}"
  fi

  if is::readable /proc/meminfo; then
    awk '/^MemTotal|^MemAvailable|^MemFree|^SwapTotal|^SwapFree/ \
      {printf "%-14s %8.1f GiB\n", $1, $2 / 1048576}' /proc/meminfo
    return "${E_SUCCESS}"
  fi

  log::error "Neither free nor /proc/meminfo available"
  return "${E_ERROR}"
}

# @description List block devices as a tree (lsblk).
# @description Дерево блочных устройств (lsblk).
system::hw::block() {
  system::hw::__require_tool lsblk util-linux || return "${E_ERROR}"
  lsblk
}

# @description Show low-level disk parameters (hdparm -I). Needs root.
# @description Низкоуровневые параметры диска (hdparm -I). Требует root.
# @param $1 Block device (e.g. /dev/sda) / Блочное устройство
# @return E_INVALID on bad argument, E_ERROR if tool missing
system::hw::disk_params() {
  local -r dev="${1:-}"

  if is::empty "${dev}" || [[ ! -b "${dev}" ]]; then
    log::error "Block device required (got: '${dev}')"
    return "${E_INVALID}"
  fi

  system::hw::__require_tool hdparm hdparm || return "${E_ERROR}"
  hdparm -I "${dev}"
}

# @description Read-only bad-block surface scan (badblocks -sv).
# @description Сканирование поверхности в режиме только-чтение (badblocks -sv).
#   Non-destructive, but slow and I/O heavy — honors FRAMEWORK_DRY_RUN.
#   Недеструктивно, но долго и нагружает диск — учитывает FRAMEWORK_DRY_RUN.
# @param $1 Block device / Блочное устройство
system::hw::badblocks_scan() {
  local -r dev="${1:-}"

  if is::empty "${dev}" || [[ ! -b "${dev}" ]]; then
    log::error "Block device required (got: '${dev}')"
    return "${E_INVALID}"
  fi

  if [[ "${FRAMEWORK_DRY_RUN:-false}" == "true" ]]; then
    log::warn "[DRY-RUN] badblocks -sv ${dev}"
    return "${E_SUCCESS}"
  fi

  system::hw::__require_tool badblocks e2fsprogs || return "${E_ERROR}"
  log::warn "Read-only scan of ${dev} — this can take a long time"
  badblocks -sv "${dev}"
}

# @description Show PCI device tree (lspci -tv).
# @description Дерево PCI-устройств (lspci -tv).
system::hw::pci() {
  system::hw::__require_tool lspci pciutils || return "${E_ERROR}"
  lspci -tv
}

# @description Show USB device tree (lsusb -tv).
# @description Дерево USB-устройств (lsusb -tv).
system::hw::usb() {
  system::hw::__require_tool lsusb usbutils || return "${E_ERROR}"
  lsusb -tv
}

# @description Show GPU summary (VGA/3D controllers from lspci).
# @description Сводка о GPU (VGA/3D-контроллеры из lspci).
system::hw::gpu() {
  system::hw::__require_tool lspci pciutils || return "${E_ERROR}"
  lspci | grep -Ei 'vga|3d|display' || log::info "No GPU found"
}

# @description Show DMI/SMBIOS report (dmidecode).
# @description Отчёт DMI/SMBIOS (dmidecode). Обычно требует root.
# @param $1 [optional] DMI type: bios, system, baseboard, memory... (default:
#   short summary) / Тип DMI (по умолчанию — краткая сводка)
system::hw::dmi() {
  local -r dtype="${1:-}"

  system::hw::__require_tool dmidecode dmidecode || return "${E_ERROR}"

  if is::not_empty "${dtype}"; then
    dmidecode -t "${dtype}"
  else
    printf 'Vendor:  %s\n' "$(system::hw::vendor)"
    printf 'Product: %s\n' "$(system::hw::product_name)"
    printf 'BIOS:    %s\n' "$(system::hw::bios_version)"
  fi
}

# @description Show the last N kernel ring buffer messages (dmesg).
# @description Последние N сообщений ядра (dmesg).
# @param $1 [optional] Line count (default 20) / Число строк (по умолчанию 20)
system::hw::dmesg() {
  local -r lines="${1:-20}"

  system::hw::__require_tool dmesg util-linux || return "${E_ERROR}"
  dmesg 2>/dev/null | tail -n "${lines}" || {
    log::warn "dmesg is restricted (kernel.dmesg_restrict) — needs root"
    return "${E_ERROR}"
  }
}

# @description Full hardware listing, short form (lshw -short).
# @description Полный список оборудования, краткая форма (lshw -short).
system::hw::lshw() {
  system::hw::__require_tool lshw lshw || return "${E_ERROR}"
  lshw -short 2>/dev/null || {
    log::warn "lshw works best with root privileges"
    return "${E_ERROR}"
  }
}

# @description Full hardware report: every section that is available.
# @description Полный отчёт об оборудовании: все доступные секции.
#   Missing tools are skipped with a note, the report never fails.
#   Отсутствующие инструменты пропускаются с пометкой, отчёт не падает.
system::hw::summary() {
  log::header "CPU"
  utils::attempt system::hw::cpu

  log::header "Memory"
  utils::attempt system::hw::memory

  log::header "Block devices"
  utils::attempt system::hw::block

  log::header "GPU"
  utils::attempt system::hw::gpu

  log::header "PCI tree"
  utils::attempt system::hw::pci

  log::header "USB tree"
  utils::attempt system::hw::usb

  log::header "DMI / BIOS"
  utils::attempt system::hw::dmi

  log::header "Kernel log (last 10)"
  utils::attempt system::hw::dmesg 10
}

# @description Show available system::hw:: commands / Список команд system::hw::
system::hw::info() {
  cat <<'EOF'
system::hw:: — Hardware information / Информация об оборудовании

  Getters (single value / одно значение):
    system::hw::cpu_model        CPU model / Модель CPU
    system::hw::cpu_cores        Physical cores / Физические ядра
    system::hw::cpu_threads      Logical threads / Логические потоки
    system::hw::cpu_mhz          Current MHz / Текущая частота
    system::hw::cpu_flags_count  Feature flags / Число флагов
    system::hw::mem_total        Total RAM, MiB / Всего RAM, MiB
    system::hw::mem_available    Available RAM, MiB / Доступно RAM, MiB
    system::hw::product_name     DMI product / Продукт (DMI)
    system::hw::vendor           DMI vendor / Производитель (DMI)
    system::hw::bios_version     BIOS version / Версия BIOS

  Reports (human-readable / отчёты):
    system::hw::summary          Full report / Полный отчёт
    system::hw::cpu              CPU summary / Сводка о CPU
    system::hw::memory           Memory usage / Использование памяти
    system::hw::block            Block devices / Блочные устройства
    system::hw::pci              PCI tree / Дерево PCI
    system::hw::usb              USB tree / Дерево USB
    system::hw::gpu              GPU summary / Сводка о GPU
    system::hw::dmi [TYPE]       DMI report / Отчёт DMI
    system::hw::dmesg [N]        Last N kernel messages / Сообщения ядра
    system::hw::lshw             Full listing (lshw) / Полный список
    system::hw::disk_params DEV  Disk parameters (hdparm) / Параметры диска
    system::hw::badblocks_scan DEV  Read-only scan / Сканирование (read-only)
EOF
}

# Метка загрузки / Load marker
# shellcheck disable=SC2034
declare -g SYSTEM_HW_LOADED="1"
