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
allowed+='|tests/unit/test(bsismain|shell|trampoline|shelltier|shellstrict|[a-z]+portable)unit\.sh|tests/validatedocscode\.sh)$'
# Что ищем / what we look for
pat='(^|[^A-Za-z0-9_])BASH_[A-Z_]+|FUNCNAME|ZSH_[A-Z]+|\$\{?SHELL\}?|\$\{?BASH\}?[^_A-Za-z]|/proc/\$\$|ps -p +\$\$|(dirname|readlink -f)[^|]*"\$0"'

n=0
cli_start="$(grep -n 'CLI-команды bs / bs CLI commands' bootstrap/bs.sh 2>/dev/null | head -n 1 | cut -d: -f1 || true)"
: "${cli_start:=999999}"
# Расширенные признаки (bash как программа, его опции и дополнение) — только вне tests/
# Extended signs (bash as a program, its options and completion) — outside tests/ only
pat_extra='\bshopt\b|\bsetopt\b|exec bash\b|(^|[^A-Za-z_./$-])(bash|zsh) +(-[a-zA-Z]+|"|\$|\./)|/bin/bash|\bcompgen\b|complete -[FCW]'

scan() { # pattern, paths...
  local pattern="$1"; shift
  grep -rnE "${pattern}" "$@" --include='*.sh' 2>/dev/null || true
}
check_hit() {
  local hit="$1" file line ln
  file="${hit%%:*}"
  ln="${hit#*:}"; ln="${ln%%:*}"
  # bootstrap/bs.sh: слой — только до секции CLI-команд (bs::cli::*), там проверок оболочки быть не должно
  # bootstrap/bs.sh: the layer is only the part before the CLI commands section (bs::cli::*)
  if [[ "${file}" == */bs.sh || "${file}" == "bootstrap/bs.sh" ]] && (( ln > cli_start )); then
    :
  elif [[ "${file}" =~ ${allowed} ]]; then
    return 0
  fi
  line="${hit#*:}"; line="${line#*:}"
  [[ "${line}" =~ ^[[:space:]]*# ]] && return 0
  if sed -n "$(( ln > 3 ? ln - 3 : 1 )),${ln}p" "${file}" | grep -q 'shell-gate'; then return 0; fi
  # Тег над определением функции охватывает всё её тело (например, генератор текста для bash)
  # A tag above a function definition covers its whole body (e.g. a generator of bash text)
  local fn_line
  fn_line="$(head -n "${ln}" "${file}" | grep -nE '^[A-Za-z_][A-Za-z0-9_:]*\(\) *\{' | tail -n 1 | cut -d: -f1 || true)"
  if [[ -n "${fn_line}" ]] && sed -n "$(( fn_line > 3 ? fn_line - 3 : 1 )),${fn_line}p" "${file}" | grep -q 'shell-gate'; then return 0; fi
  n=$(( n + 1 ))
  [[ "${mode}" == "list" ]] && printf '%s\n' "${hit}"
  return 0
}
while IFS= read -r hit; do check_hit "${hit}"; done < <(scan "${pat}" "${paths[@]}")
non_tests=()
for pth in "${paths[@]}"; do [[ "${pth}" == tests* ]] || non_tests+=("${pth}"); done
if (( ${#non_tests[@]} > 0 )); then
  while IFS= read -r hit; do check_hit "${hit}"; done < <(scan "${pat_extra}" "${non_tests[@]}")
fi

[[ "${mode}" == "count" ]] && printf '%d\n' "${n}"
if (( n > 0 )); then
  printf '\n%d leak(s): use bs::is_main, bs::script_dir, bs::shell::* (see SKILL.md) / %d протечек\n' "${n}" "${n}" >&2
  exit 1
fi
printf 'no leaks / протечек нет\n'
