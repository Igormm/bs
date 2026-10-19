#!/usr/bin/env bash
#
# Bs bootstrap initializer / Инициализатор бутстрапа BS
# Purpose: detect project root, export BS_ROOT, and load core via loader.
# Назначение: определить корень проекта, экспортировать BS_ROOT и загрузить ядро через loader.
#

# @shell bash4 — the library (source) mode needs bash 4.2+; the gate below is
# @shell bash4 — POSIX, so other shells get a clear answer instead of a syntax error
# @shell bash4 — режим библиотеки (source) требует bash 4.2+; гейт ниже написан
# @shell bash4 — на POSIX, чтобы другие оболочки получали ответ, а не ошибку синтаксиса

# POSIX-гейт (валиден в sh/dash/ash/zsh/ksh/bash): подключать BS как библиотеку
# можно только из bash 4+. Из другой оболочки — объяснение и возврат, без
# «Bad substitution». Команда bs работает из любой оболочки.
# POSIX gate: BS can be sourced as a library only from bash 4+. From another
# shell: an explanation and a return, no "Bad substitution". The bs command
# works from any shell.
# shell-gate: до загрузки реестра; из не-bash оболочки путь к нему неизвестен / before the registry; its path is unknown from a non-bash shell
if [ -z "${BASH_VERSION:-}" ] || [ "${BASH_VERSINFO:-0}" -lt 4 ]; then
  printf '%s\n' "BS: bootstrap/init.sh подключается (source) только из bash 4.2+; эта оболочка — не он." \
    "BS: bootstrap/init.sh can be sourced only from bash 4.2+; this shell is not." \
    "Команда bs работает из любой оболочки и сама запускает BS в bash: bs help" \
    "The bs command works from any shell and starts BS in bash itself: bs help" >&2
  return 1 2>/dev/null || exit 1
fi

# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа,
# этот файл подключается через source и не должен менять настройки чужого shell
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points;
# this file is sourced and must not change the caller's shell settings

# @description Show usage help. This file must be sourced.
# @description Показать справку. Этот файл должен подключаться через source.
usage() {
  cat <<'HELP'
BS bootstrap init

Usage:
  source /path/to/bootstrap/init.sh
  или: source "$BS_ROOT/bootstrap/init.sh"

Notes:
  - Must be sourced, not executed, to affect current shell.
  - Должен вызываться через source, чтобы повлиять на текущую оболочку.
HELP
}

# Load pre-kernel helpers first: they are dependency-free and bash-3.2-compatible.
# shell-gate: единственное место, где init.sh узнаёт свой каталог (подключаемый файл, только bash)
# shell-gate: the one place init.sh learns its own directory (a sourced file, bash only)
BS_BOOTSTRAP_DIR="$(dirname -- "${BASH_SOURCE[0]}")"
if [[ -f "${BS_BOOTSTRAP_DIR}/bs.sh" ]]; then
  # shellcheck disable=SC1090
  source "${BS_BOOTSTRAP_DIR}/bs.sh"
fi

# If executed directly, warn and exit. Library mode is bash 4.2+ only.
# При прямом исполнении — предупредить и выйти. Режим библиотеки — только bash 4.2+.
if ! bs::shell::is_sourced; then
  printf 'ERROR: This script must be sourced, not executed.\n' >&2
  usage
  exit 1
fi

# Idempotency: skip if already initialized. The marker is exported, so a child
# process inherits it without the functions; trust it only where the kernel is
# really loaded (bs::guard exists).
# Идемпотентность: пропуск, если уже инициализировано. Маркер экспортируется, и
# дочерний процесс наследует его без функций; верим ему, только если ядро
# действительно загружено (есть bs::guard).
if [[ -n "${BS_INITIALIZED:-}" ]] && declare -F bs::guard >/dev/null 2>&1; then
  # Best-effort debug if logger is available
  [[ "${BS_DEBUG:-0}" == 1 ]] && printf 'DEBUG: BS already initialized, skipping\n' >&2
  return 0
fi

# Resolve BS_ROOT once
if [[ -n "${BS_ROOT:-}" && -d "${BS_ROOT}" ]]; then
  [[ "${BS_DEBUG:-0}" == 1 ]] && printf 'DEBUG: BS_ROOT already set: %s\n' "${BS_ROOT}" >&2
else
  # Без readonly и с явным статусом: транзиентный сбой cd с readonly-вариантом
  # навсегда блокировал бы retry в этом шелле (переменная осталась бы пустой и
  # неизменяемой) / no readonly, explicit status: a transient cd failure with
  # readonly would permanently block retry in this shell
  __BS_INIT_DIR__="$(cd -- "${BS_BOOTSTRAP_DIR}" >/dev/null 2>&1 && pwd -P)" || return 1
  __BS_ROOT_CANDIDATE__="$(cd -- "${__BS_INIT_DIR__}/.." >/dev/null 2>&1 && pwd -P)" || return 1
  if [[ -d "${__BS_ROOT_CANDIDATE__}" && -f "${__BS_ROOT_CANDIDATE__}/bs" ]]; then
    export BS_ROOT="${__BS_ROOT_CANDIDATE__}"
    unset __BS_INIT_DIR__ __BS_ROOT_CANDIDATE__
  else
    unset __BS_INIT_DIR__ __BS_ROOT_CANDIDATE__
    printf 'ERROR: Unable to determine BS_ROOT. Set BS_ROOT environment variable.\n' >&2
    return 1
  fi
fi

# Shell version gate before any kernel code runs: runtime detection via
# BASH_VERSION (NOT $SHELL: the login shell lies when sourcing).
# Гейт версии оболочки до любого кода ядра: рантайм-детект через
# BASH_VERSION, а не $SHELL (логин-оболочка врёт при source).
bs::shell::ensure_version 4 || return 1

# Add local bin to PATH
bs::append_local_bin_to_path

# @global BS_HOME — Env: BS_HOME, defaults to BS_ROOT (historical alias) (category: env)
# @global BS_HOME — Env: BS_HOME, по умолчанию BS_ROOT (исторический алиас) (категория: env)
: "${BS_HOME:=${BS_ROOT}}"
export BS_HOME

# Load loader
if [[ -f "${BS_ROOT}/bootstrap/loader.sh" ]]; then
  # shellcheck disable=SC1090
  source "${BS_ROOT}/bootstrap/loader.sh"
elif [[ -f "${BS_ROOT}/loader.sh" ]]; then
  # shellcheck disable=SC1090
  source "${BS_ROOT}/loader.sh"
else
  printf 'BS: error: loader.sh not found in %s/bootstrap/ or %s/\n' "${BS_ROOT}" "${BS_ROOT}" >&2
  return 1
fi

# Load core modules via loader
# core/prereq must come first: it provides bs::guard and bs::source_relative
load "core/prereq"
load "core/lang"
load "core/const"
load "core/logger"
load "core/quiet"
load "core/fmt"
load "core/data"
load "core/errorhandler"
load "core/version"
load "core/utils"
load "core/config"
load "core/deps"
# мост совместимости: deps::missing_tools с массивом bash (вне ядра) / compatibility bridge: deps::missing_tools with a bash array (outside the kernel)
load "lib/compat/deps"
# языковые примитивы bash: bs::func_name, str::*, arr::*, map::* (вне ядра) / bash language primitives (outside the kernel)
load "lib/compat/lang"

# Load configuration from files and env
config::load

# @global BS_INITIALIZED — Env: bootstrap initialized marker (category: env)
# @global BS_INITIALIZED — Env: маркер выполненной инициализации (категория: env)
export BS_INITIALIZED=1

# Optional info
if [[ "${BS_SILENT:-0}" != 1 ]]; then
  printf 'BS bootstrap initialized from: %s\n' "${BS_ROOT}"
fi
