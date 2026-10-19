#!/usr/bin/env bash
#
# tier_scan.sh — which shell tier does a file need? (read-only, advisory)
# tier_scan.sh — какой shell-tier нужен файлу? (только чтение, рекомендательный)
#
# For every file it lists the constructs that exist only in bash (or only in a
# few shells), computes the minimal tier and compares it with the declared
# "# @shell <tier>" annotation of the file header:
#   posix  - valid POSIX sh: dash, ash/busybox, bash, zsh, ksh can source it
#   bash4  - needs bash 4.2+ as the host (the default of an unannotated file)
#   synonyms: sh, shell = posix; bash = bash4 (others: bs_shell_tier_word)
# За каждым файлом перечисляются конструкции, существующие только в bash (или
# в немногих оболочках), считается минимальный tier и сравнивается с
# аннотацией "# @shell <tier>" в заголовке файла.
#
# Usage / Использование:
#   bash tier_scan.sh [--check] [--list] [FILE|DIR ...]
#   (default: bootstrap core lib install bs install.sh boot.sh of the repo)
#   --check  exit 1 when a file declared "posix" uses a bashism or does not
#            parse in dash / код 1, если файл с "posix" использует bash-изм
#   --list   one TSV line per file: file, declared, computed, constructs
#
# The scan is a heuristic over non-comment lines (a construct inside a string
# can be a false positive). The objective check for "posix" files is `dash -n`.
# Сканирование — эвристика по строкам без комментариев (конструкция внутри
# строки может дать ложное срабатывание). Объективная проверка для "posix" —
# `dash -n`.

set -euo pipefail

check=0 list=0
declare -a targets=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) check=1; shift ;;
    --list)  list=1; shift ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d'; exit 0 ;;
    *) targets+=("$1"); shift ;;
  esac
done

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../.." && pwd -P)"
if (( ${#targets[@]} == 0 )); then
  for t in bootstrap core lib install bs install.sh boot.sh; do
    [[ -e "${root}/${t}" ]] && targets+=("${root}/${t}")
  done
fi

# name|ERE — every pattern is applied to non-comment lines
readonly -a PATTERNS=(
  'double-bracket [[ ]]|(^|[;&|({[:space:]])\[\[[[:space:]]'
  'arithmetic command (( ))|(^|[;&|{[:space:]]|then|do|else)\(\([^)]'
  'array|(^|[[:space:]])[A-Za-z_][A-Za-z_0-9]*\+?=\(|\$\{[A-Za-z_][A-Za-z_0-9]*\[|\$\{![A-Za-z_]+\[|declare[[:space:]]+-[a-zA-Z]*[aA]|local[[:space:]]+-[a-zA-Z]*[aA]'
  'nameref|(local|declare|typeset)[[:space:]]+-[a-zA-Z]*n[[:space:]]'
  'local/declare flags|(local|declare|typeset)[[:space:]]+-[a-zA-Z]+'
  'mapfile/readarray|(^|[[:space:];|(])(mapfile|readarray)[[:space:]]'
  'process substitution|[<>]\([^)]'
  'case/replace expansion|\$\{[A-Za-z_][A-Za-z_0-9]*(,,|\^\^|//|/#|/%|@[QEPAa])'
  'indirect expansion ${!x}|\$\{![A-Za-z_]'
  'BASH_* / FUNCNAME / PIPESTATUS|BASH_(SOURCE|REMATCH|ARGV|LINENO|COMMAND)|FUNCNAME|PIPESTATUS|EPOCHREALTIME'
  'regex =~|=~'
  'source keyword|(^|[;&|({[:space:]])source[[:space:]]'
  'function keyword|(^|[;&|{[:space:]])function[[:space:]]+[A-Za-z_]'
  'printf -v|printf[[:space:]]+-v[[:space:]]'
  'read -a/-d/-n|read[[:space:]]+-[a-zA-Z]*[adnN]'
  'ANSI-C quoting $'"'"'..'"'"'|\$'"'"'[^'"'"']*'"'"
  'pipefail/shopt/ERR trap|set[[:space:]]+-[a-zA-Z]*o[[:space:]]+pipefail|(^|[;&[:space:]])shopt[[:space:]]|trap[^#]*[[:space:]]ERR'
  '&> / |& redirect|&>|\|&'
  'coproc|(^|[;&[:space:]])coproc[[:space:]]'
  '"::" in a function name|^[[:space:]]*[A-Za-z_][A-Za-z_0-9]*::[A-Za-z_:0-9]*[[:space:]]*\(\)'
)

declared_of() {  # first "# @shell <tier>" in the header
  awk 'NR<=60 && /^# @shell [a-z0-9]+/ {print $3; exit}' "$1"
}

# Какие шаблоны находятся в тексте / which patterns the text contains
match_patterns() {
  local -r text="$1"
  local entry name re found=""
  for entry in "${PATTERNS[@]}"; do
    name="${entry%%|*}"
    re="${entry#*|}"
    if grep -qE -- "${re}" <<< "${text}"; then found+="${found:+, }${name}"; fi
  done
  printf '%s' "${found}"
}

scan_file() {
  local -r f="$1"
  local declared computed="posix" found raw stripped found_code
  declared="$(declared_of "${f}")"
  case "${declared}" in sh|shell) declared="posix" ;; bash) declared="bash4" ;; esac
  # Текст без комментариев; и он же без строковых литералов (конструкция в
  # сообщении или в строке для `bash -c` — не конструкция этого файла)
  # Text without comments; and the same without string literals (a construct
  # inside a message or a `bash -c` string is not a construct of this file)
  # Тела here-document — текст (справка, шаблон), а не конструкции файла; их выбрасываем вместе с комментариями
  # The bodies of here-documents are text (help, a template), not constructs of the file; dropped with the comments
  raw="$(grep -vE '^[[:space:]]*#' "${f}" 2>/dev/null | awk '
    inh { t = $0; sub(/^[ \t]+/, "", t); if ($0 == word || t == word) inh = 0; next }
    { if (match($0, /(^|[^<])<<-?[ \t]*["\x27]?[A-Za-z_][A-Za-z_0-9]*["\x27]?/)) {
        h = substr($0, RSTART, RLENGTH); sub(/^[^<]?<<-?[ \t]*["\x27]?/, "", h); sub(/["\x27]$/, "", h); word = h; inh = 1 }
      print }' || true)"
  # и операнд-слова ${x:?слова}, ${x:-слова}, ${x:+слова}, ${x:=слова}: это текст, а не конструкции
  # and the operand words of ${x:?words}, ${x:-words}, ${x:+words}, ${x:=words}: text, not constructs
  stripped="$(sed -E "s/\"[^\"]*\"//g; s/'[^']*'//g; s/(\\$\\{[A-Za-z_0-9]+:?[?+=-])[^}]*\\}/\\1}/g" <<< "${raw}")"
  found="$(match_patterns "${raw}")"
  found_code="$(match_patterns "${stripped}")"
  [[ -z "${found}" ]] || computed="bash4"
  # Объективная проверка: разбирается ли файл в dash
  local parses="n/a"
  if command -v dash >/dev/null 2>&1; then
    if dash -n "${f}" 2>/dev/null; then parses="yes"; else parses="no"; fi
  fi
  local first verdict="ok"
  first="$(head -n 1 "${f}" 2>/dev/null || true)"
  if [[ "${declared}" == "posix" ]]; then
    if [[ -n "${found_code}" || "${parses}" == "no" ]]; then
      verdict="VIOLATION"; found="${found_code:-does not parse in dash}"
    else
      found=""   # шаблоны были только внутри строк / patterns were inside strings only
    fi
  elif [[ -z "${declared}" ]]; then
    verdict="unannotated"
  elif [[ "${declared}" == "bash4" && "${computed}" == "posix" && "${parses}" == "yes" && "${first}" != "#!/usr/bin/env bs"* ]]; then
    verdict="could-be-posix"
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "${f#"${root}"/}" "${declared:--}" "${computed}" "${parses}" "${verdict}" "${found:--}"
  [[ "${verdict}" != "VIOLATION" ]]
}

mapfile -t files < <(
  for t in "${targets[@]}"; do
    if [[ -d "${t}" ]]; then find "${t}" -type f \( -name '*.sh' -o -name bs \) -not -path '*/.git/*'
    else printf '%s\n' "${t}"; fi
  done | sort -u
)

bad=0
declare -i n_posix=0 n_bash4=0 n_unann=0 n_viol=0
if (( list == 0 )); then
  printf '%-44s %-8s %-8s %-6s %s\n' "file" "declared" "computed" "dash-n" "verdict"
fi
for f in "${files[@]}"; do
  [[ -f "${f}" ]] || continue
  line="$(scan_file "${f}")" || bad=1
  IFS=$'\t' read -r p d c ps v found <<< "${line}"
  [[ "${d}" == "posix" ]] && n_posix+=1
  [[ "${d}" == "bash4" ]] && n_bash4+=1
  [[ "${d}" == "-" ]] && n_unann+=1
  [[ "${v}" == "VIOLATION" ]] && n_viol+=1
  if (( list == 1 )); then
    printf '%s\n' "${line}"
  elif [[ "${v}" == "VIOLATION" || "${v}" == "could-be-posix" || "${d}" == "posix" ]]; then
    printf '%-44s %-8s %-8s %-6s %s%s\n' "${p}" "${d}" "${c}" "${ps}" "${v}" "$([[ "${v}" == VIOLATION ]] && printf ' — %s' "${found}")"
  fi
done
if (( list == 0 )); then
  printf '\n%d files: %d posix, %d bash4, %d unannotated (= bash4), %d violations\n' \
    "${#files[@]}" "${n_posix}" "${n_bash4}" "${n_unann}" "${n_viol}"
fi
if (( check == 1 && bad == 1 )); then exit 1; fi
exit 0
