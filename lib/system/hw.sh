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

# @private
# @description Print "Label: value" with a fixed-width label column.
# @description Вывести «Label: value» с колонкой меток фиксированной ширины.
# @param $1 Label / Метка (пустая — строка без двоеточия / empty — no colon)
# @param $2 Value / Значение
# @stdout aligned line / выровненная строка
hw::__print_label_value() {
  local -r label="${1:-}"
  if is::empty "${label}"; then
    printf '%-14s %s\n' "" "${2:-}"
  else
    printf '%-14s %s\n' "${label}:" "${2:-}"
  fi
}

# ==========================================
# Getters: single machine-readable values
# Геттеры: одно машиночитаемое значение
# ==========================================

# @description CPU model name (data) / Модель CPU (данные).
# @stdout e.g. "Intel(R) Core(TM) i7-8650U CPU @ 1.90GHz"
system::hw::cpu_model() {
  # /proc доступен только на Linux / /proc exists on Linux only
  [[ -d /proc ]] || return 0
  awk -F': ' '/^model name/ {print $2; exit}' /proc/cpuinfo
}

# @description Number of physical CPU cores (data) / Физические ядра (данные).
# @stdout core count
system::hw::cpu_cores() {
  [[ -d /proc ]] || return 0
  awk -F': ' '/^cpu cores/ {print $2; exit}' /proc/cpuinfo
}

# @description Number of logical CPU threads (data) / Логические потоки (данные).
# @stdout thread count
system::hw::cpu_threads() {
  if utils::has nproc; then
    nproc
  elif [[ -d /proc ]] && is::readable /proc/cpuinfo; then
    grep -c '^processor' /proc/cpuinfo
  fi
}

# @description Current CPU frequency in MHz (data) / Текущая частота CPU (данные).
# @stdout integer MHz
system::hw::cpu_mhz() {
  [[ -d /proc ]] || return 0
  awk -F': ' '/^cpu MHz/ {printf "%.0f", $2; exit}' /proc/cpuinfo
}

# @description Number of CPU feature flags (data) / Число CPU-флагов (данные).
# @stdout flag count
system::hw::cpu_flags_count() {
  [[ -d /proc ]] || return 0
  awk -F': ' '/^flags/ {print split($2, f, " "); exit}' /proc/cpuinfo
}

# @description Total RAM in MiB (data) / Всего RAM в MiB (данные).
# @stdout total memory in MiB
system::hw::mem_total() {
  [[ -d /proc ]] || return 0
  awk '/^MemTotal/ {printf "%d", $2 / 1024; exit}' /proc/meminfo
}

# @description Available RAM in MiB (data) / Доступно RAM в MiB (данные).
# @stdout available memory in MiB
system::hw::mem_available() {
  [[ -d /proc ]] || return 0
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
# WRAPPER-CANDIDATE: utils::human_size — hw::__human_size is module-local; promote to core (facts.sh, ps1status print sizes too) / кандидат-обёртка: utils::human_size — hw::__human_size локальна, нужна в facts.sh и ps1status
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

  hw::__print_label_value "Model" "$(system::hw::cpu_model)"
  hw::__print_label_value "Cores" "$(system::hw::cpu_cores) physical, $(system::hw::cpu_threads) logical"
  hw::__print_label_value "MHz" "$(system::hw::cpu_mhz)"
  hw::__print_label_value "Flags" "$(system::hw::cpu_flags_count) features"
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
    # Та же форма, что у free -h: колонки total/used/free/shared/buff-cache/
    # available; недоступные значения — "unknown"
    # Same shape as free -h: total/used/free/shared/buff-cache/available
    # columns; unavailable values fill with "unknown"
    local line
    local -a table=()
    while IFS= read -r line; do
      table+=("${line}")
    done < <(awk '
      function h(kb) {
        if (kb == "") return "unknown"
        if (kb >= 1048576) return sprintf("%.1fGi", kb / 1048576)
        if (kb >= 1024)    return sprintf("%.1fMi", kb / 1024)
        return sprintf("%.1fKi", kb)
      }
      /^MemTotal:/     { mt = $2 }
      /^MemAvailable:/ { ma = $2 }
      /^MemFree:/      { mf = $2 }
      /^Shmem:/        { ms = $2 }
      /^Buffers:/      { mb = $2 }
      /^Cached:/       { mc = $2 }
      /^SwapTotal:/    { st = $2 }
      /^SwapFree:/     { sf = $2 }
      END {
        used = (mt == "" || ma == "") ? "" : mt - ma
        bc   = (mb == "" && mc == "") ? "" : mb + mc
        su   = (st == "" || sf == "") ? "" : st - sf
        printf "%8s %8s %8s %8s %10s %10s\n", "total", "used", "free", "shared", "buff/cache", "available"
        printf "%8s %8s %8s %8s %10s %10s\n", h(mt), h(used), h(mf), h(ms), h(bc), h(ma)
        printf "%8s %8s %8s %8s %10s %10s\n", h(st), h(su), h(sf), "unknown", "unknown", "unknown"
      }' /proc/meminfo)
    hw::__print_label_value "" "${table[0]}"
    hw::__print_label_value "Mem" "${table[1]}"
    hw::__print_label_value "Swap" "${table[2]}"
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
    hw::__print_label_value "Vendor" "$(system::hw::vendor)"
    hw::__print_label_value "Product" "$(system::hw::product_name)"
    hw::__print_label_value "BIOS" "$(system::hw::bios_version)"
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

# @private
# @description Run one summary section: header + command, count the result.
# @description Выполнить одну секцию сводки: заголовок + команда, подсчёт.
# @param $1 Section title / Название секции
# @param $@ Command and args / Команда и аргументы
system::hw::__section() {
  local -r title="${1:?section title required}"
  shift
  log::header "${title}"
  local rc=0
  "$@" 2>/dev/null || rc=$?
  if (( rc == 0 )); then
    HW_SUMMARY_SHOWN=$(( HW_SUMMARY_SHOWN + 1 ))
  else
    HW_SUMMARY_SKIPPED=$(( HW_SUMMARY_SKIPPED + 1 ))
  fi
}

# @description Full hardware report: every section that is available.
# @description Полный отчёт об оборудовании: все доступные секции.
#   Missing tools are skipped with a note, the report never fails.
#   Отсутствующие инструменты пропускаются с пометкой, отчёт не падает.
system::hw::summary() {
  HW_SUMMARY_SHOWN=0
  HW_SUMMARY_SKIPPED=0

  system::hw::__section "CPU" system::hw::cpu
  system::hw::__section "Memory" system::hw::memory
  system::hw::__section "Block devices" system::hw::block
  system::hw::__section "GPU" system::hw::gpu
  system::hw::__section "PCI tree" system::hw::pci
  system::hw::__section "USB tree" system::hw::usb
  system::hw::__section "DMI / BIOS" system::hw::dmi
  system::hw::__section "Kernel log (last 10)" system::hw::dmesg 10

  log::info "Summary: ${HW_SUMMARY_SHOWN} sections shown, ${HW_SUMMARY_SKIPPED} skipped/unknown"
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

# ==========================================
# hw:: — hardware DB layer / слой-база данных
#
# The hardware is exposed as a dictionary navigated by semantic paths
# instead of the Linux /sys layout:
#   hw::get mb.bios.vendor      mb.memory.speed
#   hw::cd mb.memory; hw::get speed
#   hw::ls mb.storage           hw::find "temp"
# Аппаратура доступна как словарь с навигацией по смысловым путям
# вместо раскладки Linux /sys:
#   hw::get mb.bios.vendor      mb.memory.speed
#   hw::cd mb.memory; hw::get speed
#   hw::ls mb.storage           hw::find "temp"
#
# Path scheme / Схема путей:
#   mb.bios.{vendor,version,date,uefi}
#   mb.system.{vendor,product,serial,uuid}
#   mb.board.{vendor,name,serial,version}
#   mb.chassis.{vendor,type}
#   mb.cpu.{vendor,name,cores,threads,max_mhz,virtualization,flags.<flag>}
#   mb.cache.{l1d,l1i,l2,l3}
#   mb.memory.{total_bytes,total_mb,type,speed,modules}
#   mb.storage.<dev>.{model,size,type}
#   mb.net.<if>.{mac,speed,state}
#   mb.sensors.<name>.<sensor>_c / _rpm / _mv
#   mb.battery.{present,capacity_pct,energy_full_wh,status}
#   mb.power.ac_online
#   mb.usb.count  mb.pci.count  mb.tpm.present  mb.efi.{mode,secure_boot}
#   mb.os.{name,kernel,arch,hostname}
#
# Value encoding / Кодирование значений:
#   sizes — human-readable, one decimal (B/KiB/MiB/GiB/TiB), raw value kept
#     under <key>.raw (e.g. mb.cache.l3.raw="12288K")
#   размеры — человекочитаемые, один знак после запятой (B/KiB/MiB/GiB/TiB),
#     сырое значение сохраняется под <key>.raw (напр. mb.cache.l3.raw="12288K")
#   booleans — yes/no/unknown (facts.sh uses 1/0; hw keeps its own style)
#   булевы значения — yes/no/unknown (в facts.sh — 1/0; в hw свой стиль)
#   efi mode — uefi/bios;  virtualization — vmx/svm/no;  flag markers — "1"
#   режим EFI — uefi/bios;  виртуализация — vmx/svm/no;  маркеры флагов — "1"
#
# Test hooks (override paths) / Тестовые хуки (переопределение путей):
#   HW_DMI_PATH, HW_HWMON_PATH, HW_POWER_PATH, HW_NET_PATH, HW_BLOCK_PATH
# ==========================================

# Path overrides (test hooks) / Переопределение путей (тестовые хуки)
: "${HW_DMI_PATH:=/sys/class/dmi/id}"
: "${HW_HWMON_PATH:=/sys/class/hwmon}"
: "${HW_POWER_PATH:=/sys/class/power_supply}"
: "${HW_NET_PATH:=/sys/class/net}"
: "${HW_BLOCK_PATH:=/sys/block}"

# State / Состояние
declare -gA HW_DB=()
declare -g HW_CWD=""
declare -g HW_BUILT=0
# Счётчики последней сводки / Last summary counters
declare -g -i HW_SUMMARY_SHOWN=0
declare -g -i HW_SUMMARY_SKIPPED=0

# @private
# @description Read a file if readable (never empty $(hw::__read_file f) trap:
# an extra redirection disables the $(<file) special case and discards
# the content). / Прочитать файл, если он доступен (ловушка
# $(hw::__read_file f): лишний редирект отключает спец-режим $(<file)).
# @param $1 Path / Путь
# @stdout content or nothing / содержимое или ничего
hw::__read_file() {
  if [[ -r "${1}" ]]; then
    printf '%s' "$(<"${1}")"
  fi
}

# @private
# @description Read a DMI file if readable, store under a key.
# @description Прочитать DMI-файл, если он доступен, и сохранить по ключу.
# @param $1 DB key / Ключ БД
# @param $2 File name under HW_DMI_PATH / Имя файла в HW_DMI_PATH
hw::__read_dmi() {
  local f="${HW_DMI_PATH}/${2}"
  if [[ -r "${f}" ]]; then
    hw::__set "${1}" "$(<"${f}")"
  fi
}

# @private
# @description Convert a size to a human-readable form (bytes → B/KiB/MiB/GiB/TiB,
# one decimal). Accepts plain bytes or suffixed sysfs/cpuinfo values ("12288K",
# "8192 KB"). / Преобразовать размер в человекочитаемый вид (байты →
# B/KiB/MiB/GiB/TiB, один знак после запятой). Принимает байты или значения
# с суффиксом sysfs/cpuinfo ("12288K", "8192 KB").
# @param $1 Size / Размер
# @stdout e.g. "12.0 MiB" / напр. «12.0 MiB»
hw::__human_size() {
  local v="${1:-0}"
  local -i mult=1

  # Суффиксы sysfs/cpuinfo (порядок: сначала многосимвольные)
  # sysfs/cpuinfo suffixes (long ones first)
  case "${v}" in
    *TB) v="${v%TB}"; mult=$(( 1024 * 1024 * 1024 * 1024 )) ;;
    *GB) v="${v%GB}"; mult=$(( 1024 * 1024 * 1024 )) ;;
    *MB) v="${v%MB}"; mult=$(( 1024 * 1024 )) ;;
    *KB) v="${v%KB}"; mult=1024 ;;
    *T)  v="${v%T}";  mult=$(( 1024 * 1024 * 1024 * 1024 )) ;;
    *G)  v="${v%G}";  mult=$(( 1024 * 1024 * 1024 )) ;;
    *M)  v="${v%M}";  mult=$(( 1024 * 1024 )) ;;
    *K)  v="${v%K}";  mult=1024 ;;
    *B)  v="${v%B}" ;;
  esac
  v="${v// /}"

  if [[ ! "${v}" =~ ^[0-9]+$ ]]; then
    # Не разобралось — отдаём как есть / Unparseable — pass through
    printf '%s\n' "${1}"
    return 0
  fi

  # Один знак после запятой, единицы по 1024 / One decimal, 1024-based units
  printf '%s\n' "$(( v * mult ))" | awk '
    {
      split("B KiB MiB GiB TiB", u)
      n = $1
      i = 1
      while (n >= 1024 && i < 5) {
        n /= 1024
        i++
      }
      printf "%.1f %s\n", n, u[i]
    }'
}

# @private
# @description Set one DB entry / Записать одну запись БД.
# @param $1 key / ключ
# @param $2 value / значение
hw::__set() {
  HW_DB["${1}"]="${2}"
}

# @private
# @description Populate HW_DB from /proc and /sys.
# @description Заполнить HW_DB из /proc и /sys.
hw::__build() {
  local val=""

  # --- DMI / паспорт платы
  hw::__read_dmi mb.bios.vendor bios_vendor
  hw::__read_dmi mb.bios.version bios_version
  hw::__read_dmi mb.bios.date bios_date
  hw::__read_dmi mb.system.vendor sys_vendor
  hw::__read_dmi mb.system.vendor product_vendor
  hw::__read_dmi mb.system.product product_name
  hw::__read_dmi mb.system.serial product_serial
  hw::__read_dmi mb.system.uuid product_uuid
  hw::__read_dmi mb.board.vendor board_vendor
  hw::__read_dmi mb.board.name board_name
  hw::__read_dmi mb.board.serial board_serial
  hw::__read_dmi mb.board.version board_version
  hw::__read_dmi mb.chassis.vendor chassis_vendor
  hw::__read_dmi mb.chassis.type chassis_type

  # --- EFI / UEFI
  if [[ -d /sys/firmware/efi ]]; then
    hw::__set mb.efi.mode "uefi"
    hw::__set mb.efi.secure_boot "$(hw::__secure_boot)"
  else
    hw::__set mb.efi.mode "bios"
  fi

  # --- OS / ОС
  hw::__set mb.os.kernel "$(hw::__read_file /proc/sys/kernel/osrelease)"
  hw::__set mb.os.arch "$(hw::__read_file /proc/sys/kernel/arch)"
  hw::__set mb.os.hostname "$(hw::__read_file /proc/sys/kernel/hostname)"
  # os-release может отсутствовать (контейнеры): не умираем, val остаётся пустым
  # os-release may be absent (containers): do not die, val stays empty
  val="$(utils::attempt awk -F= '/^NAME=/{gsub(/"/,"",$2); print $2}' /etc/os-release)"
  is::not_empty "${val}" && hw::__set mb.os.name "${val}"

  # --- CPU / процессор
  hw::__build_cpu

  # --- Memory / память
  local mem_total_kb=""
  mem_total_kb="$(utils::attempt awk '/^MemTotal:/{print $2}' /proc/meminfo)"
  if is::number "${mem_total_kb}"; then
    # Человекочитаемый размер; сырые байты — под .raw
    # Human-readable size; raw bytes kept under .raw
    hw::__set mb.memory.total_bytes "$(hw::__human_size "$(( mem_total_kb * 1024 ))")"
    hw::__set mb.memory.total_bytes.raw "$(( mem_total_kb * 1024 ))"
    hw::__set mb.memory.total_mb "$(( mem_total_kb / 1024 ))"
  fi
  hw::__build_memory_spd

  # --- Sensors / датчики
  hw::__build_sensors

  # --- Power / питание
  hw::__build_power

  # --- Network / сеть
  hw::__build_net

  # --- Storage / накопители
  hw::__build_storage

  # --- Counters / счётчики
  # wc -l выводит с ведущими пробелами — приводим к чистому целому
  # wc -l pads with leading spaces — normalize to a plain integer
  local usb_count pci_count
  usb_count="$(ls -1 /sys/bus/usb/devices 2>/dev/null | wc -l)"
  pci_count="$(ls -1 /sys/bus/pci/devices 2>/dev/null | wc -l)"
  hw::__set mb.usb.count "$(printf '%d' "${usb_count}")"
  hw::__set mb.pci.count "$(printf '%d' "${pci_count}")"
  if [[ -d /sys/class/tpm/tpm0 ]]; then
    hw::__set mb.tpm.present "yes"
  else
    hw::__set mb.tpm.present "no"
  fi

  HW_BUILT=1
}

# @private
# @description Secure Boot state / Состояние Secure Boot.
# @stdout yes / no / unknown
hw::__secure_boot() {
  if is::command bootctl; then
    bootctl is-secure-boot 2>/dev/null || printf 'unknown\n'
    return 0
  fi
  local sb_file
  sb_file="$(ls /sys/firmware/efi/efivars/SecureBoot-* 2>/dev/null | head -n1)"
  if is::not_empty "${sb_file}"; then
    local size
    size="$(stat -c %s "${sb_file}" 2>/dev/null)"
    if is::number "${size}" && (( size > 4 )); then
      if [[ "$(od -An -tu1 -j $(( size - 1 )) -N1 "${sb_file}" 2>/dev/null | tr -d ' ')" == "1" ]]; then
        printf 'yes\n'
      else
        printf 'no\n'
      fi
      return 0
    fi
  fi
  printf 'unknown\n'
}

# @private
# @description CPU section of the DB / CPU-раздел БД.
hw::__build_cpu() {
  local name="" vendor="" flags="" cache_l3=""
  local physical="" core=""
  local -i threads=0
  declare -A seen_cores=() seen_sockets=()

  local line
  # /proc доступен только на Linux / /proc exists on Linux only
  if [[ -d /proc ]] && is::readable /proc/cpuinfo; then
    while IFS= read -r line; do
      case "${line}" in
        processor[[:space:]]*) threads=$(( threads + 1 )) ;;
        vendor_id[[:space:]]*) vendor="${line#*: }" ;;
        "model name"*) name="${line#*: }" ;;
        physical[[:space:]]id*) physical="${line#*: }"; seen_sockets["${physical}"]=1 ;;
        core[[:space:]]id*) core="${line#*: }"; seen_cores["${physical}.${core}"]=1 ;;
        flags[[:space:]]*) flags="${line#*: }" ;;
        cache[[:space:]]size*) cache_l3="${line#*: }" ;;
      esac
    done < /proc/cpuinfo
  fi

  is::not_empty "${name}" && hw::__set mb.cpu.name "${name}"
  is::not_empty "${vendor}" && hw::__set mb.cpu.vendor "${vendor}"
  hw::__set mb.cpu.threads "${threads}"
  hw::__set mb.cpu.cores "${#seen_cores[@]}"
  hw::__set mb.cpu.sockets "${#seen_sockets[@]}"
  is::not_empty "${cache_l3}" && {
    hw::__set mb.cache.l3 "$(hw::__human_size "${cache_l3}")"
    hw::__set mb.cache.l3.raw "${cache_l3}"
  }

  local freq
  freq="$(hw::__read_file /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq)"
  if is::number "${freq}"; then
    hw::__set mb.cpu.max_mhz "$(( freq / 1000 ))"
  fi

  # Флаги → под-ключи / Flags → sub-keys
  # Разбиение по пробелам не зависит от IFS вызывающего
  # Split on spaces regardless of the caller's IFS
  local flag
  local -a flag_arr=()
  IFS=' ' read -ra flag_arr <<< "${flags}"
  for flag in "${flag_arr[@]}"; do
    hw::__set "mb.cpu.flags.${flag}" "1"
  done
  case " ${flags} " in
    *" vmx "*) hw::__set mb.cpu.virtualization "vmx" ;;
    *" svm "*) hw::__set mb.cpu.virtualization "svm" ;;
    *) hw::__set mb.cpu.virtualization "no" ;;
  esac

  # Кэши L1/L2 из sysfs (сырой размер, напр. "12288K", хранится под .raw)
  # Caches from sysfs (raw size, e.g. "12288K", kept under .raw)
  local cache_dir type level size cache_key
  for cache_dir in /sys/devices/system/cpu/cpu0/cache/index*; do
    type="$(hw::__read_file "${cache_dir}/type")"
    level="$(hw::__read_file "${cache_dir}/level")"
    size="$(hw::__read_file "${cache_dir}/size")"
    cache_key=""
    case "${level}:${type}" in
      1:Data)      cache_key="mb.cache.l1d" ;;
      1:Instruction) cache_key="mb.cache.l1i" ;;
      2:*)         cache_key="mb.cache.l2" ;;
      3:*)         cache_key="mb.cache.l3" ;;
    esac
    if is::not_empty "${cache_key}"; then
      hw::__set "${cache_key}" "$(hw::__human_size "${size}")"
      hw::__set "${cache_key}.raw" "${size}"
    fi
  done
}

# @private
# @description SPD details from dmidecode (root only) / SPD из dmidecode.
hw::__build_memory_spd() {
  if (( EUID != 0 )) || ! is::command dmidecode; then
    return 0
  fi
  local out
  out="$(dmidecode -t memory 2>/dev/null)"
  local type speed
  type="$(printf '%s\n' "${out}" | awk '/^[[:space:]]*Type:/{print $2; exit}')"
  speed="$(printf '%s\n' "${out}" | awk '/^[[:space:]]*Speed:/{print $2; exit}')"
  local modules
  modules="$(printf '%s\n' "${out}" | grep -c 'Memory Device$' || true)"
  is::not_empty "${type}" && hw::__set mb.memory.type "${type}"
  is::not_empty "${speed}" && hw::__set mb.memory.speed "${speed}"
  (( modules > 0 )) && hw::__set mb.memory.modules "${modules}"
}

# @private
# @description Sensors from hwmon / Датчики из hwmon.
hw::__build_sensors() {
  local h name s basename val
  for h in "${HW_HWMON_PATH}"/hwmon*; do
    name="$(hw::__read_file "${h}/name")"
    is::empty "${name}" && continue
    for s in "${h}"/temp*_input; do
      [[ -e "${s}" ]] || continue
      basename="${s##*/}"; basename="${basename%_input}"
      val="$(< "${s}")"
      is::number "${val}" && hw::__set "mb.sensors.${name}.${basename}_c" "$(( val / 1000 ))"
    done
    for s in "${h}"/fan*_input; do
      [[ -e "${s}" ]] || continue
      basename="${s##*/}"; basename="${basename%_input}"
      val="$(< "${s}")"
      is::number "${val}" && hw::__set "mb.sensors.${name}.${basename}_rpm" "${val}"
    done
    for s in "${h}"/in*_input; do
      [[ -e "${s}" ]] || continue
      basename="${s##*/}"; basename="${basename%_input}"
      val="$(< "${s}")"
      is::number "${val}" && hw::__set "mb.sensors.${name}.${basename}_mv" "$(( val / 1000 ))"
    done
  done
}

# @private
# @description Battery and AC from power_supply / Батарея и питание.
hw::__build_power() {
  local p type
  for p in "${HW_POWER_PATH}"/*; do
    [[ -d "${p}" ]] || continue
    type="$(hw::__read_file "${p}/type")"
    case "${type}" in
      Battery)
        hw::__set mb.battery.present "yes"
        local cap energy_full status
        cap="$(hw::__read_file "${p}/capacity")"
        is::number "${cap}" && hw::__set mb.battery.capacity_pct "${cap}"
        energy_full="$(hw::__read_file "${p}/energy_full")"
        is::number "${energy_full}" && hw::__set mb.battery.energy_full_wh "$(( energy_full / 1000000 ))"
        status="$(hw::__read_file "${p}/status")"
        is::not_empty "${status}" && hw::__set mb.battery.status "${status}"
        ;;
      Mains)
        local online
        online="$(hw::__read_file "${p}/online")"
        # sysfs отдаёт 0/1 — приводим к единому стилю yes/no
        # sysfs gives 0/1 — normalize to the shared yes/no style
        case "${online}" in
          1) hw::__set mb.power.ac_online "yes" ;;
          0) hw::__set mb.power.ac_online "no" ;;
          *) is::not_empty "${online}" && hw::__set mb.power.ac_online "${online}" ;;
        esac
        ;;
    esac
  done
}

# @private
# @description Network interfaces / Сетевые интерфейсы.
hw::__build_net() {
  local n addr speed state count=0
  for n in "${HW_NET_PATH}"/*; do
    [[ -d "${n}" ]] || continue
    local ifname
    ifname="${n##*/}"
    addr="$(hw::__read_file "${n}/address")"
    speed="$(hw::__read_file "${n}/speed")"
    state="$(hw::__read_file "${n}/operstate")"
    is::not_empty "${addr}" && hw::__set "mb.net.${ifname}.mac" "${addr}"
    is::number "${speed}" && (( speed > 0 )) && hw::__set "mb.net.${ifname}.speed_mbps" "${speed}"
    is::not_empty "${state}" && hw::__set "mb.net.${ifname}.state" "${state}"
    count=$(( count + 1 ))
  done
  hw::__set mb.net.count "${count}"
}

# @private
# @description Block devices / Блочные устройства.
hw::__build_storage() {
  local b model size rotational type count=0
  for b in "${HW_BLOCK_PATH}"/*; do
    [[ -d "${b}" ]] || continue
    local dev
    dev="${b##*/}"
    case "${dev}" in
      loop*|ram*|dm-*|zram*) continue ;;
    esac
    model="$(hw::__read_file "${b}/device/model")"
    size="$(hw::__read_file "${b}/size")"
    rotational="$(hw::__read_file "${b}/queue/rotational")"
    case "${dev}" in
      nvme*) type="nvme" ;;
      sd*)   type="sata/scsi" ;;
      mmcblk*) type="mmc" ;;
      *)     type="block" ;;
    esac
    is::not_empty "${model}" && hw::__set "mb.storage.${dev}.model" "${model}"
    is::number "${size}" && hw::__set "mb.storage.${dev}.size" "${size}"
    hw::__set "mb.storage.${dev}.type" "${type}"
    if is::number "${rotational}"; then
      if (( rotational == 0 )); then
        hw::__set "mb.storage.${dev}.media" "ssd"
      else
        hw::__set "mb.storage.${dev}.media" "hdd"
      fi
    fi
    count=$(( count + 1 ))
  done
  hw::__set mb.storage.count "${count}"
}

# @private
# @description Ensure the DB is built / Убедиться, что БД собрана.
hw::__ensure() {
  (( HW_BUILT == 1 )) && return 0
  hw::__build
}

# @private
# @description Resolve a path against HW_CWD.
# @description Разрешить путь относительно HW_CWD.
# @param $1 path / путь
# @stdout absolute key / абсолютный ключ
hw::__resolve() {
  local p="${1:-}"
  if is::empty "${p}"; then
    # Пустой путь = текущий каталог (как ls без аргументов)
    # Empty path = current directory (like ls without arguments)
    if is::not_empty "${HW_CWD}"; then
      printf '%s\n' "${HW_CWD}"
    else
      printf 'mb\n'
    fi
  elif [[ "${p}" == "/" ]]; then
    printf 'mb\n'
  elif [[ "${p}" == mb.* ]] || [[ "${p}" == mb ]]; then
    printf '%s\n' "${p}"
  elif is::not_empty "${HW_CWD}"; then
    printf '%s.%s\n' "${HW_CWD}" "${p}"
  else
    printf 'mb.%s\n' "${p}"
  fi
}

# @description Get a value by path (dictionary / DB get).
# @description Получить значение по пути (словарь / БД get).
# @param $1 Path, e.g. mb.memory.speed / Путь, напр. mb.memory.speed
# @param $2 [optional] Default value / Значение по умолчанию
# @stdout the value / значение
# @return 0 found, 1 not found
# @example
#   hw::get mb.bios.vendor
#   hw::get mb.memory.speed "unknown"
hw::get() {
  hw::__ensure
  local key
  key="$(hw::__resolve "${1:?path required}")"
  if [[ -v HW_DB["${key}"] ]]; then
    printf '%s\n' "${HW_DB[${key}]}"
    return 0
  fi
  if (( $# >= 2 )); then
    printf '%s\n' "${2}"
    return 0
  fi
  return 1
}

# @description List child keys one level under a path (DB ls).
# @description Перечислить ключи следующего уровня (БД ls).
#   A leaf path prints its value / Ключ-значение печатает своё значение.
# @param $1 [optional] Path, default current dir / Путь, по умолчанию тек. каталог
# @stdout one child per line / по ключу на строку
# @return 0 ok, 1 not a node
# @example
#   hw::ls mb.memory
hw::ls() {
  hw::__ensure
  local prefix
  prefix="$(hw::__resolve "${1:-}")"

  # Лист: печатаем значение / Leaf: print the value
  if [[ -v HW_DB["${prefix}"] ]]; then
    printf '%s\n' "${HW_DB[${prefix}]}"
    return 0
  fi

  local k rest child
  local -a out=()
  for k in "${!HW_DB[@]}"; do
    if [[ "${k}" == "${prefix}."* ]]; then
      rest="${k#"${prefix}."}"
      if [[ "${rest}" == *.* ]]; then
        child="${rest%%.*}"
      else
        child="${rest}"
      fi
      local seen=0
      local e
      for e in "${out[@]}"; do
        [[ "${e}" == "${child}" ]] && seen=1
      done
      (( seen == 0 )) && out+=("${child}")
    fi
  done
  if (( ${#out[@]} == 0 )); then
    log::warn "hw: no such node: ${prefix}"
    return 1
  fi
  printf '%s\n' "${out[@]}" | sort
}

# @description Change the current navigation path (DB cd).
# @description Сменить текущий путь навигации (БД cd).
# @param $1 Path or / for root / Путь или / для корня
# @return 0 ok, 1 no such node
# @example
#   hw::cd mb.memory
#   hw::get speed
hw::cd() {
  hw::__ensure
  local target
  target="$(hw::__resolve "${1:-}")"
  if [[ "${target}" == "mb" ]] || [[ -v HW_DB["${target}"] ]] || utils::quiet hw::ls "${target}"; then
    HW_CWD="${target}"
    return 0
  fi
  log::warn "hw: cd: no such node: ${target}"
  return 1
}

# @description Print the current navigation path (DB pwd).
# @description Вывести текущий путь навигации (БД pwd).
# @stdout the path / путь
hw::pwd() {
  if is::empty "${HW_CWD}"; then
    printf 'mb\n'
  else
    printf '%s\n' "${HW_CWD}"
  fi
}

# @description Search keys by substring (DB query).
# @description Поиск ключей по подстроке (запрос к БД).
# @param $1 Substring / Подстрока
# @stdout matching "key = value" lines / строки «ключ = значение»
# @example
#   hw::find temp
hw::find() {
  hw::__ensure
  local sub="${1:?substring required}"
  local k
  local -a matches=()
  for k in "${!HW_DB[@]}"; do
    [[ "${k}" == *"${sub}"* ]] && matches+=("${k} = ${HW_DB[${k}]}")
  done
  if (( ${#matches[@]} == 0 )); then
    # Отчёт вместо тишины / Report instead of silence
    printf '0 matches for "%s"\n' "${sub}"
    return 0
  fi
  printf '%s\n' "${matches[@]}" | sort
  return 0
}

# @description Dump the whole DB or a subtree (DB select *).
# @description Вывести всю БД или поддерево (БД select *).
# @param $1 [optional] Path prefix / Префикс пути
# @stdout "key = value" lines / строки «ключ = значение»
# @example
#   hw::dump mb.memory
hw::dump() {
  hw::__ensure
  local prefix
  prefix="$(hw::__resolve "${1:-}")"
  local k
  for k in "${!HW_DB[@]}"; do
    [[ "${k}" == "${prefix}"* ]] && printf '%s = %s\n' "${k}" "${HW_DB[${k}]}"
  done | sort
  return 0
}

# @description Count keys under a path (DB count).
# @description Количество ключей под путём (БД count).
# @param $1 [optional] Path prefix / Префикс пути
# @stdout the count / количество
hw::count() {
  hw::__ensure
  local prefix
  prefix="$(hw::__resolve "${1:-}")"
  local k n=0
  for k in "${!HW_DB[@]}"; do
    [[ "${k}" == "${prefix}"* ]] && n=$(( n + 1 ))
  done
  printf '%d\n' "${n}"
}

# @description Rebuild the DB (e.g. after tests changed hooks).
# @description Пересобрать БД (напр. после смены хуков тестами).
hw::reset() {
  HW_DB=()
  HW_CWD=""
  HW_BUILT=0
}
