#!/bin/sh
# shellcheck shell=sh
# @shell posix — валидный POSIX sh: case, test, source через «.»; в bash грузит ядро целиком, в остальных оболочках — его POSIX-часть / valid POSIX sh: case, test, "." for sourcing; in bash it loads the whole kernel, in other shells its POSIX part
# @tier core — builtins only; works everywhere
#
# Bs bootstrap initializer / Инициализатор бутстрапа BS
# Purpose: detect project root, export BS_ROOT, and load core via loader.
# Назначение: определить корень проекта, экспортировать BS_ROOT и загрузить ядро через loader.
#
# Режимы ядра / Kernel modes (BS_KERNEL_MODE)
#   full  — bash 4.2+: 16 модулей core/ (prereq, lang, const, var, str, num, msg, logger, quiet, fmt,
#           data, errorhandler, version, utils, config, deps) и мосты lib/compat/deps, lib/compat/lang,
#           lib/compat/args; args и calc подключаются по запросу;
#   posix — dash, ash, ksh, mksh, zsh: те же 16 модулей core/, без мостов; args и calc (оба POSIX)
#           подключаются по запросу, всё lib/ — только в режиме full (bash ниже 4.2 отклоняется).
#   full  — bash 4.2+: 16 core/ modules (prereq, lang, const, var, str, num, msg, logger, quiet, fmt,
#           data, errorhandler, version, utils, config, deps) and the bridges lib/compat/deps,
#           lib/compat/lang, lib/compat/args; args and calc are loaded on demand;
#   posix — dash, ash, ksh, mksh and zsh: the same 16 core/ modules, no bridges; args and calc (both
#           POSIX) are loaded on demand, all of lib/ is in the full mode only (a bash older than 4.2
#           is refused).
#
# Каталог bootstrap/ / The bootstrap/ directory
#   bash берёт его из пути этого файла; остальные оболочки — из BS_BOOTSTRAP_DIR, BS_ENTRY_DIR
#   (его ставит пролог точек входа) или BS_ROOT.
#   bash takes it from the path of this file; other shells from BS_BOOTSTRAP_DIR, BS_ENTRY_DIR
#   (the prologue of the entry points sets it) or BS_ROOT.
#
# ИМЕНА / NAMES
#   Real function: bs_init_usage; in bash and zsh also usage (the old name).
#   Настоящая функция: bs_init_usage; в bash и zsh — ещё и usage (прежнее имя).

# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа,
# этот файл подключается через source и не должен менять настройки чужого shell
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points;
# this file is sourced and must not change the caller's shell settings

# @description Show usage help. This file must be sourced.
# @description Показать справку. Этот файл должен подключаться через source.
bs_init_usage() {
  cat <<'HELP'
BS bootstrap init

Usage:
  . /path/to/bootstrap/init.sh
  или: . "$BS_ROOT/bootstrap/init.sh"   (bash: source)

Notes:
  - Must be sourced, not executed, to affect current shell.
  - Должен вызываться через source, чтобы повлиять на текущую оболочку.
  - bash 4.2+: whole kernel; dash, ash, ksh, mksh, zsh: its POSIX part (BS_KERNEL_MODE=posix).
HELP
}

# Каталог bootstrap/: ДО подключения реестра путь к нему известен только по пути этого файла.
# The bootstrap/ directory: BEFORE the registry is sourced it is known only from the path of this file.
if [ -n "${BASH_SOURCE:-}" ]; then # shell-gate: единственное место, где init.sh узнаёт свой каталог (подключаемый файл) / the one place init.sh learns its own directory (a sourced file)
  BS_BOOTSTRAP_DIR=$(dirname -- "${BASH_SOURCE}") # shell-gate
elif [ -n "${ZSH_VERSION:-}" ]; then # shell-gate: zsh знает путь подключаемого файла через %x / zsh knows the path of a sourced file through %x
  eval 'BS_BOOTSTRAP_DIR=${${(%):-%x}:h}' # shell-gate
elif [ -n "${BS_ENTRY_DIR:-}" ]; then
  BS_BOOTSTRAP_DIR=${BS_ENTRY_DIR}/bootstrap
elif [ -n "${BS_ROOT:-}" ]; then
  BS_BOOTSTRAP_DIR=${BS_ROOT}/bootstrap
elif [ -z "${BS_BOOTSTRAP_DIR:-}" ]; then
  printf '%s\n' "BS: init.sh: set BS_BOOTSTRAP_DIR, BS_ENTRY_DIR or BS_ROOT / задайте BS_BOOTSTRAP_DIR, BS_ENTRY_DIR или BS_ROOT" >&2
  return 1
fi

# Pre-kernel: POSIX-часть (base.sh с реестром shell.sh) везде; в bash ещё bs.sh (стек вызовов,
# BASH_REMATCH, команды bs::cli::*). Они не имеют зависимостей.
# Pre-kernel: the POSIX part (base.sh with the registry shell.sh) everywhere; in bash also bs.sh
# (call stack, BASH_REMATCH, the bs::cli::* commands). They have no dependencies.
if [ ! -f "${BS_BOOTSTRAP_DIR}/base.sh" ]; then
  printf '%s\n' "BS: error: base.sh not found in ${BS_BOOTSTRAP_DIR}" >&2
  return 1
fi
# shellcheck disable=SC1090,SC1091
. "${BS_BOOTSTRAP_DIR}/base.sh"
case "$(bs_shell_family)" in
  bash)
    if [ -f "${BS_BOOTSTRAP_DIR}/bs.sh" ]; then
      # shellcheck disable=SC1090,SC1091
      . "${BS_BOOTSTRAP_DIR}/bs.sh"
    fi
    # При прямом исполнении — предупредить и выйти (отличить source от исполнения умеет только bash)
    # If executed directly, warn and exit (only bash can tell source from execution)
    if ! bs::shell::is_sourced; then
      printf 'ERROR: This script must be sourced, not executed.\n' >&2
      bs_init_usage
      exit 1
    fi ;;
esac

# Idempotency: skip if already initialized. The marker is exported, so a child
# process inherits it without the functions; trust it only where the kernel is
# really loaded (bs_guard exists).
# Идемпотентность: пропуск, если уже инициализировано. Маркер экспортируется, и
# дочерний процесс наследует его без функций; верим ему, только если ядро
# действительно загружено (есть bs_guard).
if [ -n "${BS_INITIALIZED:-}" ] && command -v bs_guard >/dev/null 2>&1; then
  # Best-effort debug if logger is available
  if [ "${BS_DEBUG:-0}" = 1 ]; then printf 'DEBUG: BS already initialized, skipping\n' >&2; fi
  return 0
fi

# Resolve BS_ROOT once
if [ -n "${BS_ROOT:-}" ] && [ -d "${BS_ROOT}" ]; then
  if [ "${BS_DEBUG:-0}" = 1 ]; then printf 'DEBUG: BS_ROOT already set: %s\n' "${BS_ROOT}" >&2; fi
else
  # Без readonly и с явным статусом: транзиентный сбой cd с readonly-вариантом
  # навсегда блокировал бы retry в этом шелле (переменная осталась бы пустой и
  # неизменяемой) / no readonly, explicit status: a transient cd failure with
  # readonly would permanently block retry in this shell
  __BS_INIT_DIR__=$(cd -- "${BS_BOOTSTRAP_DIR}" >/dev/null 2>&1 && pwd -P) || return 1
  __BS_ROOT_CANDIDATE__=$(cd -- "${__BS_INIT_DIR__}/.." >/dev/null 2>&1 && pwd -P) || return 1
  if [ -d "${__BS_ROOT_CANDIDATE__}" ] && [ -f "${__BS_ROOT_CANDIDATE__}/bs" ]; then
    BS_ROOT=${__BS_ROOT_CANDIDATE__}
    export BS_ROOT
    unset __BS_INIT_DIR__ __BS_ROOT_CANDIDATE__
  else
    unset __BS_INIT_DIR__ __BS_ROOT_CANDIDATE__
    printf 'ERROR: Unable to determine BS_ROOT. Set BS_ROOT environment variable.\n' >&2
    return 1
  fi
fi

# Режим ядра: полное — только в bash 4.2+; bash старше — отказ; остальным оболочкам — POSIX-часть.
# The kernel mode: the whole kernel only in bash 4.2+; an older bash is refused; other shells get
# the POSIX part.
if bs_shell_host_ok; then
  BS_KERNEL_MODE=full
elif [ "$(bs_shell_family)" = bash ]; then
  bs_shell_ensure_version 4 || return 1
  BS_KERNEL_MODE=full
else
  BS_KERNEL_MODE=posix
fi
export BS_KERNEL_MODE

# Add local bin to PATH
bs_append_local_bin_to_path

# @global BS_HOME — Env: BS_HOME, defaults to BS_ROOT (historical alias) (category: env)
# @global BS_HOME — Env: BS_HOME, по умолчанию BS_ROOT (исторический алиас) (категория: env)
: "${BS_HOME:=${BS_ROOT}}"
export BS_HOME

# Load loader
if [ -f "${BS_ROOT}/bootstrap/loader.sh" ]; then
  # shellcheck disable=SC1090,SC1091
  . "${BS_ROOT}/bootstrap/loader.sh"
elif [ -f "${BS_ROOT}/loader.sh" ]; then
  # shellcheck disable=SC1090,SC1091
  . "${BS_ROOT}/loader.sh"
else
  printf 'BS: error: loader.sh not found in %s/bootstrap/ or %s/\n' "${BS_ROOT}" "${BS_ROOT}" >&2
  return 1
fi

# Load core modules via loader
# core/prereq must come first: it provides bs_guard and bs_source_relative
bs_load "core/prereq"
bs_load "core/lang"
bs_load "core/const"
bs_load "core/var"
bs_load "core/str"
bs_load "core/num"
bs_load "core/msg"
bs_load "core/logger"
bs_load "core/quiet"
bs_load "core/fmt"
bs_load "core/data"
bs_load "core/errorhandler"
bs_load "core/version"
bs_load "core/utils"
bs_load "core/config"
bs_load "core/deps"
if [ "$BS_KERNEL_MODE" = full ]; then
  # мосты совместимости (вне ядра): deps::missing_tools с массивом bash; языковые примитивы bash: bs::func_name, str::*, arr::*, map::*; массивы bash ARGS_PARAMS/ARGS_FLAGS/ARGS_REST для args::parse / compatibility bridges (outside the kernel): deps::missing_tools with a bash array; bash language primitives: bs::func_name, str::*, arr::*, map::*; bash arrays ARGS_PARAMS/ARGS_FLAGS/ARGS_REST for args::parse
  bs_load "lib/compat/deps"
  bs_load "lib/compat/lang"
  bs_load "lib/compat/args"
fi
# Load configuration from files and env / Загрузить конфигурацию из файлов и окружения
bs_config_load

# @global BS_INITIALIZED — Env: bootstrap initialized marker (category: env)
# @global BS_INITIALIZED — Env: маркер выполненной инициализации (категория: env)
BS_INITIALIZED=1
export BS_INITIALIZED

# Optional info
if [ "${BS_SILENT:-0}" != 1 ]; then
  printf 'BS bootstrap initialized from: %s\n' "${BS_ROOT}"
fi

bs_shell_alias bs_init_usage usage
