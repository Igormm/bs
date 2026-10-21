#!/bin/sh
# shellcheck shell=sh
# @shell posix — валидный POSIX sh: загрузчик, порядок модулей ядра, `.` / valid POSIX sh: the loader, the kernel module order, `.`
# @tier core — builtins only; works everywhere
# @tier core — только builtin'ы; работает везде
#
# bootstrap/kernel.sh — подключает ядро (core/*) в любой оболочке реестра
# bootstrap/kernel.sh — loads the kernel (core/*) in any shell of the registry
#
# BS_KERNEL_MINIMAL=1 — только подмножество для help/version/env/list/init-shell/shebang
# (транзитивные зависимости bootstrap/cli.sh); иначе — все модули и конфигурация.
# BS_KERNEL_MINIMAL=1 — only the subset for help/version/env/list/init-shell/shebang
# (the transitive dependencies of bootstrap/cli.sh); otherwise all modules and the config.
#
# Использование / Usage (dash, ash, ksh, mksh, zsh, bash):
#   BS_ROOT=/path/to/bs . /path/to/bs/bootstrap/kernel.sh
#
# BS_ROOT нужно задать: оболочка без BASH_SOURCE не знает, откуда её подключили (bash и zsh
# через bootstrap/init.sh находят корень сами). После подключения доступны все bs_* функции
# ядра: bs_log_*, bs_args_*, bs_config_get, bs_arr_*, bs_map_*, bs_utils_*, …; в bash и zsh —
# ещё и прежние имена с `::`. Мосты для массивов bash (lib/compat/*) подключает bootstrap/init.sh.
# BS_ROOT must be set: a shell without BASH_SOURCE cannot tell where it was sourced from
# (bash and zsh find the root themselves through bootstrap/init.sh). Afterwards every bs_*
# function of the kernel is available: bs_log_*, bs_args_*, bs_config_get, bs_arr_*, bs_map_*,
# bs_utils_*, …; in bash and zsh also the old names with `::`. The bridges for bash arrays
# (lib/compat/*) are loaded by bootstrap/init.sh.
#
# Порядок: слой оболочек, загрузчик, затем модули ядра (prereq первым: он даёт bs_guard и
# bs_source_relative), затем конфигурация.
# Order: the shell layer, the loader, then the kernel modules (prereq first: it provides
# bs_guard and bs_source_relative), then the configuration.
#
# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points

# shellcheck disable=SC2034  # BS_CURRENT_FILE читают подключаемые файлы / BS_CURRENT_FILE is read by the sourced files
if [ -z "${BS_ROOT:-}" ] || [ ! -f "${BS_ROOT}/bootstrap/loader.sh" ]; then
  printf '%s\n' "BS: bootstrap/kernel.sh: задайте BS_ROOT — каталог с bootstrap/loader.sh" \
    "BS: bootstrap/kernel.sh: set BS_ROOT to the directory that holds bootstrap/loader.sh" >&2
  # shellcheck disable=SC2317  # exit — запасной путь, если файл запустили, а не подключили / exit is the fallback when the file is run, not sourced
  return 1 2>/dev/null || exit 1
fi

# @global BS_HOME — Env: BS_HOME, defaults to BS_ROOT (historical alias) (category: env)
# @global BS_HOME — Env: BS_HOME, по умолчанию BS_ROOT (исторический алиас) (категория: env)
: "${BS_HOME:=${BS_ROOT}}"
export BS_HOME

# Слой оболочек и загрузчик; BS_CURRENT_FILE нужен POSIX-файлам, чтобы найти свой каталог
# The shell layer and the loader; POSIX files take their directory from BS_CURRENT_FILE
if ! command -v bs_shell_alias >/dev/null 2>&1; then
  BS_CURRENT_FILE="${BS_ROOT}/bootstrap/shell.sh"
  # shellcheck disable=SC1091
  . "${BS_ROOT}/bootstrap/shell.sh" || return 1
fi
if ! command -v bs_load >/dev/null 2>&1; then
  BS_CURRENT_FILE="${BS_ROOT}/bootstrap/loader.sh"
  # shellcheck disable=SC1091
  . "${BS_ROOT}/bootstrap/loader.sh" || return 1
fi

# @private
# @description Загрузить перечисленные модули ядра по порядку; core/prereq первым.
# @description Load the listed kernel modules in order; core/prereq first.
# @param $@ module names without core/ and .sh / имена модулей без core/ и .sh
bs_kernel_load_modules() {
  for __bs_k_mod in "$@"; do
    bs_load "core/${__bs_k_mod}" || return 1
  done
  unset __bs_k_mod
}

# Минимальный режим (BS_KERNEL_MINIMAL=1) — для help/version/env/list/init-shell/
# shebang: только транзитивные зависимости bootstrap/cli.sh, без args/config/deps.
# The minimal mode (BS_KERNEL_MINIMAL=1) is for help/version/env/list/init-shell/
# shebang: only the transitive dependencies of bootstrap/cli.sh, no args/config/deps.
if [ "${BS_KERNEL_MINIMAL:-0}" = 1 ]; then
  bs_kernel_load_modules \
    prereq const version str var num logger quiet data errorhandler utils
else
  bs_kernel_load_modules \
    prereq lang const var str num msg logger quiet fmt data errorhandler version utils config deps args
  # Конфигурация из файлов и окружения / Configuration from files and environment
  bs_config_load
fi
