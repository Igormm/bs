#!/usr/bin/env bash
# shellcheck shell=bash
# find_leaks.sh — find shell-specific checks that leaked outside the abstraction layer
# find_leaks.sh — найти оболочечные проверки, «протёкшие» за пределы слоя абстракции
#
# Usage / Использование: find_leaks.sh [--list|--count] [paths...]   (default: core lib examples bootstrap install)
# Exit 1 when there are leaks (so it can gate a commit) / код 1, если протечки есть.
#
# A "leak" is a direct use of BASH_SOURCE, BASH_VERSION/BASH_VERSINFO, ZSH_*,
# BASH_EXECUTION_STRING, $SHELL, $0-as-script-path outside the allowed files:
# the abstraction layer itself (bs.sh, shell.sh, trampoline.sh) and lines tagged
# `shell-gate` (unavoidable places that run before the layer can be loaded).
# «Протечка» — прямое использование перечисленного вне разрешённых файлов:
# самого слоя абстракции и неизбежных строк до загрузчика.

set -euo pipefail

mode="list"
case "${1:-}" in --list) shift ;; --count) mode="count"; shift ;; esac
paths=("$@")
(( ${#paths[@]} > 0 )) || paths=(core lib examples bootstrap install tests bs install.sh boot.sh)

# Разрешено / allowed: слой абстракции и точки до загрузчика
allowed='^(bootstrap/(bs|shell|trampoline)\.sh'
# тесты самого слоя абстракции проверяют эти конструкции намеренно / tests of the layer itself check them on purpose
allowed+='|tests/unit/test(bsismain|shell|trampoline|shelltier|shellstrict)unit\.sh|tests/validatedocscode\.sh)$'
# Что ищем / what we look for
pat='BASH_SOURCE|BASH_VERSION|BASH_VERSINFO|BASH_EXECUTION_STRING|ZSH_[A-Z]+|\$\{?SHELL\}?'

n=0
while IFS= read -r hit; do
  file="${hit%%:*}"
  [[ "${file}" =~ ${allowed} ]] && continue
  line="${hit#*:}"; line="${line#*:}"
  [[ "${line}" =~ ^[[:space:]]*# ]] && continue          # comments / комментарии
  # Явно помеченное неизбежное место: тег shell-gate в этой или одной из 3 предыдущих строк
  # An explicitly tagged unavoidable site: the shell-gate tag on this or one of the 3 previous lines
  ln="${hit#*:}"; ln="${ln%%:*}"
  if sed -n "$(( ln > 3 ? ln - 3 : 1 )),${ln}p" "${file}" | grep -q 'shell-gate'; then continue; fi
  n=$(( n + 1 ))
  [[ "${mode}" == "list" ]] && printf '%s\n' "${hit}"
done < <(grep -rnE "${pat}" "${paths[@]}" --include='*.sh' 2>/dev/null || true)

[[ "${mode}" == "count" ]] && printf '%d\n' "${n}"
if (( n > 0 )); then
  printf '\n%d leak(s): use bs::is_main, bs::script_dir, bs::shell::* (see SKILL.md) / %d протечек\n' "${n}" "${n}" >&2
  exit 1
fi
printf 'no leaks / протечек нет\n'
