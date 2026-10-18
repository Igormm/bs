#!/usr/bin/env bs
# shellcheck shell=bash
# @shell bash4 — nameref и массивы bash: параметр-результат — настоящий массив вызывающего / bash nameref and arrays: the result parameter is the caller's real array
#
# lib/compat/deps.sh — мост совместимости: deps::missing_tools с массивом bash
# lib/compat/deps.sh — compatibility bridge: deps::missing_tools with a bash array
#
# Ядро (core/deps.sh, @shell posix) отдаёт результат в массив слоя данных (bs_deps_missing_tools).
# Восемь модулей lib/ и два примера передают в deps::missing_tools НАСТОЯЩИЙ массив bash и читают
# его после вызова, поэтому прежняя функция живёт здесь, вне ядра; init.sh подключает этот файл
# в bash.
# The kernel (core/deps.sh, @shell posix) returns the result in a data-layer array
# (bs_deps_missing_tools). Eight lib/ modules and two examples pass a REAL bash array to
# deps::missing_tools and read it afterwards, so the old function lives here, outside the kernel;
# init.sh loads this file in bash.

bs::guard "COMPAT_DEPS" || return 0

# @description Collect missing tools into an array (package names).
# @description Собрать отсутствующие инструменты в массив (имена пакетов).
#   Linguistic replacement for the repeated `if ! bs_utils_has X; then
#   missing+=("pkg"); fi` blocks in module check_dependencies functions.
#   Each spec is "cmd", "cmd:package" or "cmdA|cmdB:package" (alternatives:
#   any one is enough). Package defaults to the command name; several
#   packages can be space-separated.
# @param $1 Name of the output array (filled with missing package names)
# @param $@ Tool specs / Спецификации инструментов
# @return Always 0 — the result is in the array / Всегда 0
# @example
#   local -a missing=()
#   deps::missing_tools missing wg:wireguard-tools "netstat|ss:net-tools iproute2"
deps::missing_tools() {
  local -n __deps_out="${1:?output array name required}"
  shift

  local spec cmd pkg alt
  local -a alts=()
  for spec in "$@"; do
    cmd="${spec%%:*}"
    pkg="${spec#*:}"

    local found=1
    IFS='|' read -r -a alts <<< "${cmd}"
    for alt in "${alts[@]}"; do
      if bs_utils_has "${alt}"; then
        found=0
        break
      fi
    done

    if [[ "${found}" -ne 0 ]]; then
      local p
      local -a pkgs=()
      # pkg may hold several space-separated package names; split on spaces
      # explicitly: under bs strict mode IFS is newline/tab and a bare
      # `for p in ${pkg}` would keep "net-tools iproute2" as ONE name
      # pkg может содержать несколько имён через пробел; делим по пробелам явно
      IFS=' ' read -r -a pkgs <<< "${pkg}"
      for p in "${pkgs[@]}"; do
        __deps_out+=("${p}")
      done
    fi
  done

  return 0
}

