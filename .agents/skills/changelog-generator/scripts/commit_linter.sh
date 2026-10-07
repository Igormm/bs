#!/usr/bin/env bash
#
# commit_linter.sh — lint commit subjects against Conventional Commits
# commit_linter.sh — проверка тем коммитов по правилам Conventional Commits
#
# Input sources (priority order):
# Источники входных данных (по приоритету):
#   1) --input file (one commit subject per line) / файл (одна тема на строку)
#   2) stdin lines / строки stdin
#   3) git range via --from-ref/--to-ref / git-диапазон через --from-ref/--to-ref
#
# Use --strict for non-zero exit on violations.
# --strict: ненулевой код возврата при наличии нарушений.
#

set -euo pipefail
IFS=$'\n\t'

# Framework bootstrap (logger for diagnostics) / Бутстрап фреймворка (логгер)
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_DIR
export BS_SILENT=1
: "${BS_LOG_TIMESTAMP:=false}"
# shellcheck source=../../../../bootstrap/init.sh
source "${SCRIPT_DIR}/../../../../bootstrap/init.sh"

# @global CONVENTIONAL_RE — Conventional Commits subject regex (category: constant)
# @global CONVENTIONAL_RE — регекс темы Conventional Commits (категория: constant)
readonly CONVENTIONAL_RE='^(feat|fix|perf|refactor|docs|test|build|ci|chore|security|deprecated|remove)(\([a-z0-9./_-]+\))?(!)?:[[:space:]]+.{1,120}$'

# CLI options (mutable state) / Опции командной строки (изменяемое состояние)
opt_input=""
opt_from_ref=""
opt_to_ref=""
opt_strict=0
opt_format="text"

# Show usage help / Показать справку
usage() {
  cat <<'HELP'
Usage: commit_linter.sh [OPTIONS]

Validate conventional commit subjects.

Options:
  --input FILE     File with commit subjects (one per line)
  --from-ref REF   Git ref start (exclusive)
  --to-ref REF     Git ref end (inclusive)
  --strict         Exit non-zero when violations exist
  --format FORMAT  Output format: text (default) or json
  -h, --help       Show this help

Input priority: --input file, then stdin, then git range (--to-ref).
Приоритет входа: файл --input, затем stdin, затем git-диапазон (--to-ref).
HELP
}

# Expected CLI error: message to stderr, exit 2 (like the Python CLIError)
# Ожидаемая ошибка CLI: сообщение в stderr, выход 2 (как Python CLIError)
cli_error() {
  log::error "$1"
  exit 2
}

# Strip leading/trailing whitespace like Python str.strip()
# Обрезка пробельных символов по краям, как Python str.strip()
trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "${s}"
}

# Escape a string for embedding into JSON / Экранировать строку для вставки в JSON
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "${s}"
}

# Parse command-line arguments (mirrors the Python argparse interface)
# Разбор аргументов командной строки (повторяет argparse-интерфейс Python-версии)
parse_args() {
  while (( $# > 0 )); do
    case "$1" in
      --input)
        (( $# >= 2 )) || cli_error "option --input requires an argument"
        opt_input="$2"; shift 2 ;;
      --input=*)   opt_input="${1#*=}"; shift ;;
      --from-ref)
        (( $# >= 2 )) || cli_error "option --from-ref requires an argument"
        opt_from_ref="$2"; shift 2 ;;
      --from-ref=*) opt_from_ref="${1#*=}"; shift ;;
      --to-ref)
        (( $# >= 2 )) || cli_error "option --to-ref requires an argument"
        opt_to_ref="$2"; shift 2 ;;
      --to-ref=*)  opt_to_ref="${1#*=}"; shift ;;
      --strict)    opt_strict=1; shift ;;
      --format)
        (( $# >= 2 )) || cli_error "option --format requires an argument"
        opt_format="$2"; shift 2 ;;
      --format=*)  opt_format="${1#*=}"; shift ;;
      -h|--help)   usage; exit 0 ;;
      --)          shift; break ;;
      -*)          cli_error "unrecognized option: $1" ;;
      *)           cli_error "unexpected argument: $1" ;;
    esac
  done
  if [[ "${opt_format}" != "text" && "${opt_format}" != "json" ]]; then
    cli_error "invalid --format choice: '${opt_format}' (choose from: text, json)"
  fi
}

# Load commit subjects from the first available source into the output array.
# Загрузить темы коммитов из первого доступного источника в выходной массив.
# Args:
#   $1: nameref of the output array / nameref выходного массива
load_lines() {
  local -n __arr_load_out="$1"
  __arr_load_out=()
  local line

  # 1) --input file / файл --input
  if [[ -n "${opt_input}" ]]; then
    if [[ ! -f "${opt_input}" ]]; then
      cli_error "Failed reading --input file: ${opt_input}: no such file"
    fi
    while IFS= read -r line || [[ -n "${line}" ]]; do
      line="$(trim "${line}")"
      if [[ -n "${line}" ]]; then __arr_load_out+=("${line}"); fi
    done < "${opt_input}"
    return 0
  fi

  # 2) stdin (only when it is not a terminal) / stdin (только когда это не tty)
  if [[ ! -t 0 ]]; then
    while IFS= read -r line || [[ -n "${line}" ]]; do
      line="$(trim "${line}")"
      if [[ -n "${line}" ]]; then __arr_load_out+=("${line}"); fi
    done
    if (( ${#__arr_load_out[@]} > 0 )); then return 0; fi
  fi

  # 3) git range (requires --to-ref) / git-диапазон (требуется --to-ref)
  if [[ -n "${opt_to_ref}" ]]; then
    local range_spec="${opt_to_ref}"
    if [[ -n "${opt_from_ref}" ]]; then range_spec="${opt_from_ref}..${opt_to_ref}"; fi
    local git_out
    if ! git_out="$(git log "${range_spec}" --pretty=format:%s --no-merges 2>&1)"; then
      cli_error "git log failed for range '${range_spec}': ${git_out}"
    fi
    while IFS= read -r line; do
      line="$(trim "${line}")"
      if [[ -n "${line}" ]]; then __arr_load_out+=("${line}"); fi
    done <<< "${git_out}"
    if (( ${#__arr_load_out[@]} > 0 )); then return 0; fi
  fi

  cli_error "No commit input found. Use --input, stdin, or --to-ref."
}

# Lint subjects; violations are collected as "line N: <subject>".
# Проверить темы; нарушения собираются в формате "line N: <тема>".
# Args:
#   $1: nameref of the subjects array / nameref массива тем
#   $2: nameref of the violations output array / nameref выходного массива нарушений
lint_lines() {
  local -n __arr_lint_in="$1"
  local -n __arr_lint_bad="$2"
  __arr_lint_bad=()
  local -i idx=0
  local line
  for line in ${__arr_lint_in[@]+"${__arr_lint_in[@]}"}; do
    idx+=1
    if [[ ! "${line}" =~ ${CONVENTIONAL_RE} ]]; then
      __arr_lint_bad+=("line ${idx}: ${line}")
    fi
  done
}

# Text report (same layout as the Python version)
# Текстовый отчёт (тот же вид, что у Python-версии)
print_report_text() {
  local -ir total="$1" valid="$2" invalid="$3"
  local -n __arr_rep_txt="$4"
  printf 'Conventional commit lint report\n'
  printf -- '- total: %d\n' "${total}"
  printf -- '- valid: %d\n' "${valid}"
  printf -- '- invalid: %d\n' "${invalid}"
  if (( ${#__arr_rep_txt[@]} > 0 )); then
    printf 'Violations:\n'
    local v
    for v in "${__arr_rep_txt[@]}"; do
      printf -- '- %s\n' "${v}"
    done
  fi
}

# JSON report (same shape as Python json.dumps(asdict(report), indent=2),
# but non-ASCII is emitted as raw UTF-8, not XXXX escapes)
# JSON-отчёт (форма как у Python json.dumps(..., indent=2),
# но не-ASCII выводится как UTF-8, а не как XXXX)
print_report_json() {
  local -ir total="$1" valid="$2" invalid="$3"
  local -n __arr_rep_json="$4"
  printf '{\n'
  printf '  "total": %d,\n' "${total}"
  printf '  "valid": %d,\n' "${valid}"
  printf '  "invalid": %d,\n' "${invalid}"
  if (( ${#__arr_rep_json[@]} == 0 )); then
    printf '  "violations": []\n'
  else
    printf '  "violations": [\n'
    local -i i last=$(( ${#__arr_rep_json[@]} - 1 ))
    for (( i = 0; i <= last; i++ )); do
      local comma=','
      if (( i == last )); then comma=''; fi
      printf '    "%s"%s\n' "$(json_escape "${__arr_rep_json[$i]}")" "${comma}"
    done
    printf '  ]\n'
  fi
  printf '}\n'
}

main() {
  parse_args "$@"
  local -a lines=() violations=()
  load_lines lines
  lint_lines lines violations
  local -i total=${#lines[@]} invalid=${#violations[@]} valid
  valid=$(( total - invalid ))

  if [[ "${opt_format}" == "json" ]]; then
    print_report_json "${total}" "${valid}" "${invalid}" violations
  else
    print_report_text "${total}" "${valid}" "${invalid}" violations
  fi

  if (( opt_strict == 1 && invalid > 0 )); then
    exit 1
  fi
  exit 0
}

main "$@"
