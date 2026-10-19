#!/usr/bin/env bash
#
# check_posix_tier.sh — bash does not take part in the `@shell posix` tier (read-only)
# check_posix_tier.sh — в ярусе `@shell posix` bash не участвует (только чтение)
#
# Three checks for every file labelled "# @shell posix" in bootstrap/, core/, install/, install.sh, boot.sh and bs:
#   1. parse   — every installed NON-bash shell parses it (dash, busybox ash, ksh, mksh, zsh);
#   2. syntax  — no bash-only construct on a non-comment line: [[ ]], (( )), arrays,
#                local -x, declare, ${!x}, <( ), =~, mapfile, shopt, source, function keyword,
#                $'..', ${x,,} ${x^^}; no BASH_*/ZSH_* variables outside the layer files;
#   2b. names  — every function is in the one namespace bs_* (real name = bs_ + the "::" name with "::" -> "_"), none is defined with "::";
#   3. run     — the whole tier is sourced and used by dash in a sandbox whose PATH has
#                NO bash at all (proof that bash does not take part, not only that it parses).
# Для каждого файла с «# @shell posix» в bootstrap/, core/, install/, install.sh, boot.sh и bs: (1) разбор в каждой
# установленной оболочке, кроме bash; (2) нет bash-конструкций в строках без комментариев;
# нет BASH_*/ZSH_* вне файлов слоя; (3) весь ярус подключается и работает в dash в песочнице,
# где в PATH вообще нет bash.
#
# Usage / Использование:
#   bash check_posix_tier.sh [--list] [FILE ...]     (default: every posix file of the repo)
# Exit: 0 — clean, 1 — findings, 2 — bad usage. A shell that is not installed is skipped and
# named in the report ("not verified"), never counted as passed.

set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)" # shell-gate: the checker is a bash tool of its own
cd "${root}" || exit 2

list_only=0
declare -a files=()
for a in "$@"; do
  case "${a}" in
    --list) list_only=1 ;;
    -h|--help) sed -n '2,/^set -uo/p' "$0" | sed '$d'; exit 0 ;;
    -*) echo "unknown option: ${a}" >&2; exit 2 ;;
    *) files+=("${a}") ;;
  esac
done
declare -a tier=()
while IFS= read -r f; do
  head -n 14 "${f}" | grep -q '^# @shell posix' && tier+=("${f}")
done < <(git ls-files --cached --others --exclude-standard 'bootstrap/*.sh' 'core/*.sh' 'install/*.sh' 'install.sh' 'boot.sh' 'bs')
(( ${#files[@]} > 0 )) || files=("${tier[@]}")
if (( list_only == 1 )); then printf '%s\n' "${files[@]}"; exit 0; fi

# Файлы слоя абстракции: им разрешено НАЗЫВАТЬ переменные оболочек (искать, какая это оболочка)
# Layer files: allowed to NAME shell variables (to find out which shell this is)
is_layer() { case "$1" in bootstrap/shell.sh|bootstrap/trampoline.sh) return 0 ;; *) return 1 ;; esac; }

declare -a shells=() missing=()
for s in dash "busybox ash" ksh mksh zsh; do
  if command -v "${s%% *}" >/dev/null 2>&1; then shells+=("${s}"); else missing+=("${s}"); fi
done

fail=0
note() { printf '%s\n' "$*"; }
bad() { fail=1; printf 'FAIL  %s\n' "$*"; }

# --- 1. parse ---
for f in "${files[@]}"; do
  for s in "${shells[@]}"; do
    read -ra w <<< "${s}"
    "${w[@]}" -n "${f}" >/dev/null 2>&1 || bad "parse   ${f} does not parse in ${s}"
  done
done

# --- 2. syntax ---
# Конструкции, которых нет в POSIX sh / constructs that are not POSIX sh
syntax='\[\[[^:]|\(\( |\$\(\(.*\)\)\)|=~|<\(|>\(|\$\{![A-Za-z_]|\$\{[A-Za-z_0-9]+(\^\^|,,)|\$\{[A-Za-z_0-9]+\[|^[[:space:]]*(declare|typeset|mapfile|readarray|shopt|local -[a-zA-Z]|source )|^[[:space:]]*function [A-Za-z_]|\$'"'"'|\bcoproc\b|\bselect [a-z]'
for f in "${files[@]}"; do
  # Тела heredoc — текст, который файл выдаёт (например, скрипт автодополнения для bash), а не его код
  # Heredoc bodies are text the file prints (e.g. a bash completion script), not its code
  body="$(grep -vE '^[[:space:]]*#' "${f}" | awk '
    hd != "" { if ($0 == hd) hd = ""; next }
    match($0, /<<-?[ ]*\\?["\x27]?[A-Za-z_]+["\x27]?/) {
      t = substr($0, RSTART, RLENGTH); gsub(/<<-?[ ]*|\\|["\x27]/, "", t); hd = t
    }
    { print }')"
  hits="$(printf '%s\n' "${body}" | grep -nE -- "${syntax}" | grep -v 'shell-gate' || true)"
  # $(( )) арифметика — POSIX; отфильтровываем только её / $(( )) is POSIX; only it is filtered out
  hits="$(printf '%s\n' "${hits}" | grep -vE '\$\(\([^)]*\)\)' || true)"
  # Файлы слоя: строка, которую они отдают ДОЧЕРНЕЙ оболочке (`"$1" -c '...'`) — текст для другого
  # интерпретатора, не синтаксис самого файла (так реестр проверяет версию найденного bash)
  # Layer files: a string handed to a CHILD shell (`"$1" -c '...'`) is text for another interpreter,
  # not the file's own syntax (this is how the registry probes the version of a candidate bash)
  if is_layer "${f}"; then hits="$(printf '%s\n' "${hits}" | grep -vE " -c '" || true)"; fi
  [[ -z "${hits}" ]] || bad "syntax  ${f}: bash-only constructs: $(printf '%s' "${hits}" | head -n 3 | tr '\n' ' ' | cut -c1-160)"
  if ! is_layer "${f}"; then
    vars="$(printf '%s\n' "${body}" | grep -nE '\b(BASH|BASH_[A-Z]+|ZSH_[A-Z]+|FUNCNAME)\b' | grep -v 'shell-gate' || true)"
    [[ -z "${vars}" ]] || bad "vars    ${f}: shell variables outside the layer: $(printf '%s' "${vars}" | head -n 2 | tr '\n' ' ' | cut -c1-160)"
  fi
done

# --- 2b. namespace: every function of the tier is bs_* (one namespace), none has "::" ---
# Одно пространство имён: настоящее имя = bs_ + имя через «::», где «::» заменено на «_»;
# псевдонимы с «::» создаёт bs_shell_alias в конце файла, определять их в самом файле нельзя.
# One namespace: the real name = bs_ + the "::" name with "::" turned into "_"; the "::" aliases are
# made by bs_shell_alias at the end of the file and must not be defined in the file itself.
for f in "${files[@]}"; do
  badnames="$(grep -vE '^[[:space:]]*#' "${f}" | grep -oE '^[A-Za-z_][A-Za-z0-9_:]*\(\)' | tr -d '()' | grep -vE '^(bs_|__bs_)' || true)"
  [[ -z "${badnames}" ]] || bad "names   ${f}: functions outside the bs_ namespace: $(printf '%s' "${badnames}" | head -n 4 | tr '\n' ' ')"
  colons="$(grep -vE '^[[:space:]]*#' "${f}" | grep -oE '^[A-Za-z_][A-Za-z0-9_:]*::[A-Za-z0-9_:]*\(\)' | head -n 2 | tr '\n' ' ' || true)"
  [[ -z "${colons}" ]] || bad "names   ${f}: a function defined with '::': ${colons}"
done

# --- 3. run in a sandbox with NO bash ---
sandbox="$(mktemp -d)"; trap 'rm -rf "${sandbox:?}"' EXIT
mkdir "${sandbox}/bin" "${sandbox}/home"
for t in dash ls cat head tail tr sed grep readlink mktemp cp mv rm chmod mkdir dirname basename wc cut od env true false sh; do
  p="$(command -v "${t}" 2>/dev/null || true)"
  [[ -n "${p}" && "${p}" == /* ]] && ln -sf "${p}" "${sandbox}/bin/${t}"
done
ln -sf "$(command -v dash)" "${sandbox}/bin/sh"
if env -i PATH="${sandbox}/bin" "${sandbox}/bin/dash" -c 'command -v bash >/dev/null 2>&1'; then
  bad "run     sandbox is not clean: bash is reachable"
elif command -v dash >/dev/null 2>&1; then
  # порядок зависимостей: реестр, prereq, guard, затем остальные / dependency order
  src=""
  # trampoline.sh — исполняемый файл, не библиотека: его подключать нельзя / an executable, not a library
  # весь настоящий ярус + проверяемые файлы (probe зовёт функции ярса) / the whole real tier + the files under check
  for f in bootstrap/shell.sh core/prereq.sh core/guard.sh "${tier[@]}" "${files[@]}"; do
    [[ "${f}" == bootstrap/trampoline.sh ]] && continue
    # install/*.sh и install.sh — сценарии установки: им нужны INSTALLER_DIR, SOURCE_ROOT и т.д., их разбор и синтаксис
    # проверены выше, а запуск — в unit/testinstallnobashunit.sh / the install scripts need INSTALLER_DIR, SOURCE_ROOT, …:
    # parse and syntax are checked above, the run is in unit/testinstallnobashunit.sh
    case "${f}" in install/*|install.sh|boot.sh|bs|*/install/*|*/install.sh|*/boot.sh|*/bs) continue ;; esac
    # BS_CURRENT_FILE ставит загрузчик на время подключения; в dash другого источника каталога нет
    # BS_CURRENT_FILE is set by the loader while a module is sourced; dash has no other source of the directory
    full="${root}/${f}"; [[ "${f}" == /* ]] && full="${f}"
    src+="BS_CURRENT_FILE=\"${full}\"; . \"${full}\""$'\n'
  done
  probe="${src}
bs_shell_family >/dev/null || exit 11
case \$(bs_version_get) in [0-9]*) : ;; *) exit 12 ;; esac
bs_utils_has ls || exit 13
bs_utils_has no-such-command-xyz && exit 14
bs_utils_ignore false || exit 15
exit 0"
  out="$(env -i HOME="${sandbox}/home" PATH="${sandbox}/bin" BS_ROOT="${root}" BS_BOOTSTRAP_DIR="${root}/bootstrap" "${sandbox}/bin/dash" -c "${probe}" 2>&1)"; rc=$?
  (( rc == 0 )) || bad "run     dash without bash: the tier does not work (exit ${rc}): $(printf '%s' "${out}" | head -n 2 | tr '\n' ' ' | cut -c1-160)"
else
  note "skip: dash is not installed — the no-bash run was NOT done / не установлен dash — запуск без bash НЕ выполнялся"
fi

echo
note "checked ${#files[@]} posix file(s); shells used: ${shells[*]:-none}"
(( ${#missing[@]} == 0 )) || note "not verified (not installed / не установлены): ${missing[*]}"
if (( fail == 0 )); then note "OK: bash does not take part in the posix tier / bash в ярусе posix не участвует"; exit 0; fi
note "FAIL: see the lines above / см. строки выше"; exit 1
