#!/usr/bin/env bash
# shellcheck shell=bash
#
# decision_tree_extractor.sh — Extract decision branches from a plan/design doc.
# Извлечение ветвей решений из плана/дизайн-документа.
#
# Detects / Детектирует:
#   1. Modal verbs of intent: we'll / we will / we plan to / we should / ...
#   2. Choices: "X or Y", "either ... or", "vs" / выборы
#   3. TBDs: "TBD", "to be decided", "open question" / открытые вопросы
#   4. Trade-off markers / маркеры trade-off
#   5. Dependencies ("depends on") and literal questions (line ends in "?")
#
# Exit code / Код выхода: 0 on success, 1 on unreadable input.
#
# This file mirrors Python's import/module split: it can be sourced (functions
# only) or executed (CLI). / Файл можно подключать через source (только функции)
# или исполнять (CLI) — аналог "if __name__ == __main__".
#
# Usage:
#   decision_tree_extractor.sh [path/to/plan.md] [--output text|json]

set -euo pipefail

# BS bootstrap / бутстрап BS (repo root is 4 levels up from this script)
__script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
export BS_SILENT=1
# shellcheck disable=SC1091
source "${__script_dir}/../../../../bootstrap/init.sh"

# Decision patterns + kinds, in priority order (first match per line wins)
# Паттерны решений + виды, в порядке приоритета (первое совпадение в строке)
readonly -a DTE_PATTERNS=(
  '\bwe[[:space:]]*('"'"'ll|will|plan[[:space:]]+to|should|could|might|may)\b'
  '\b(either|or)\b.{0,80}\b(or|alternatively)\b'
  '\bversus\b|\bvs\.?\b'
  '\bTBD\b|\bto[[:space:]]+be[[:space:]]+(decided|determined)\b'
  '\bopen[[:space:]]+question\b'
  '\btrade-?offs?\b'
  '\bdepends?[[:space:]]+on\b'
  '\?[[:space:]]*$'
)
readonly -a DTE_KINDS=(
  intent choice choice open open tradeoff dependency question
)

# Branch results: parallel arrays / ветви: параллельные массивы
declare -a DTE_BRANCH_LINES=()
declare -a DTE_BRANCH_KINDS=()
declare -a DTE_BRANCH_TRIGGERS=()
declare -a DTE_BRANCH_CONTEXTS=()

# Per-kind counters (ordered) / счётчики по видам (упорядоченные)
declare -a DTE_BY_KIND_ORDER=()
declare -A DTE_BY_KIND_COUNT=()

# =============================================================================
# Embedded sample / Встроенный образец
# =============================================================================

dte_sample_plan() {
  cat <<'SAMPLE'
# Plan: Multi-tenant SaaS Migration

## Architecture
We'll move to a single-tenant database per customer. Or maybe we should
do schema-per-tenant for cost. This is a trade-off between isolation and ops cost.

## Auth
TBD: SSO provider — Okta or Auth0?

## Migration sequence
We plan to migrate the largest tenant first. Depends on whether their data fits in 24h.
Open question: rollback strategy?

## Data layer
We could use Postgres logical replication, but we might prefer dual-writes.
Trade-off: complexity vs zero-downtime guarantee.

## Cut-over
Final decision TBD on whether to flip DNS at midnight or use feature flags.
SAMPLE
}

# =============================================================================
# Analysis / Анализ
# =============================================================================

# @description Classify one line; prints "<kind>\t<trigger>" or nothing
# @description Классифицировать строку; печатает "<kind>\t<trigger>" или ничего
_dte_classify() {
  local -r line=$1
  local i m
  for i in "${!DTE_PATTERNS[@]}"; do
    if printf '%s\n' "${line}" | grep -qiE -- "${DTE_PATTERNS[${i}]}"; then
      m=$(printf '%s\n' "${line}" | grep -oiE -- "${DTE_PATTERNS[${i}]}" \
        | head -n 1) || true
      printf '%s\t%s' "${DTE_KINDS[${i}]}" "${m}"
      return 0
    fi
  done
  return 1
}

# @description Extract branches from plan text on stdin into DTE_BRANCH_*
# @description Извлечь ветви из текста плана (stdin) в DTE_BRANCH_*
dte_extract_branches() {
  DTE_BRANCH_LINES=()
  DTE_BRANCH_KINDS=()
  DTE_BRANCH_TRIGGERS=()
  DTE_BRANCH_CONTEXTS=()
  DTE_BY_KIND_ORDER=()
  DTE_BY_KIND_COUNT=()

  local line line_no=0 classified kind trigger context
  while IFS= read -r line || [[ -n ${line} ]]; do
    ((++line_no))
    classified=$(_dte_classify "${line}") || true
    [[ -z ${classified} ]] && continue
    kind=${classified%%$'\t'*}
    trigger=${classified#*$'\t'}
    context=$(printf '%s' "${line}" \
      | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    context=${context:0:160}
    DTE_BRANCH_LINES+=("${line_no}")
    DTE_BRANCH_KINDS+=("${kind}")
    DTE_BRANCH_TRIGGERS+=("${trigger}")
    DTE_BRANCH_CONTEXTS+=("${context}")
    if [[ -z ${DTE_BY_KIND_COUNT[${kind}]:-} ]]; then
      DTE_BY_KIND_ORDER+=("${kind}")
      DTE_BY_KIND_COUNT["${kind}"]=1
    else
      DTE_BY_KIND_COUNT["${kind}"]=$((DTE_BY_KIND_COUNT[${kind}] + 1))
    fi
  done
}

# =============================================================================
# Rendering / Вывод
# =============================================================================

# @description Python dict repr of by-kind counts / repr словаря Python
_dte_by_kind_repr() {
  local out="{" first=1 k
  for k in ${DTE_BY_KIND_ORDER[@]+"${DTE_BY_KIND_ORDER[@]}"}; do
    ((first)) || out+=", "
    out+="'${k}': ${DTE_BY_KIND_COUNT[${k}]}"
    first=0
  done
  printf '%s}' "${out}"
}

# @description JSON-escape a string / Экранировать строку для JSON
_dte_json_escape() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\t'/\\t}
  s=${s//$'\r'/\\r}
  s=${s//$'\n'/\\n}
  printf '%s' "${s}"
}

# @description Text report / Текстовый отчёт
dte_render_text() {
  local i
  printf '%.0s=' {1..72}
  printf '\nDECISION TREE EXTRACTOR\n'
  printf '%.0s=' {1..72}
  printf '\n\nTotal decision branches found: %s\n' "${#DTE_BRANCH_LINES[@]}"
  printf 'By kind: %s\n\n' "$(_dte_by_kind_repr)"
  printf '%.0s-' {1..72}
  printf '\n'
  for i in "${!DTE_BRANCH_LINES[@]}"; do
    printf '  [%2d] L%4d (%-11s) %s\n' "$((i + 1))" "${DTE_BRANCH_LINES[${i}]}" \
      "${DTE_BRANCH_KINDS[${i}]}" "${DTE_BRANCH_CONTEXTS[${i}]}"
  done
}

# @description JSON report / JSON-отчёт
dte_render_json() {
  local i k first
  printf '{\n'
  printf '  "total_branches": %s,\n' "${#DTE_BRANCH_LINES[@]}"
  printf '  "by_kind": {'
  first=1
  for k in ${DTE_BY_KIND_ORDER[@]+"${DTE_BY_KIND_ORDER[@]}"}; do
    ((first)) || printf ', '
    printf '"%s": %s' "$(_dte_json_escape "${k}")" "${DTE_BY_KIND_COUNT[${k}]}"
    first=0
  done
  printf '},\n'
  printf '  "branches": ['
  for i in "${!DTE_BRANCH_LINES[@]}"; do
    ((i > 0)) && printf ','
    printf '\n    {\n'
    printf '      "line": %s,\n' "${DTE_BRANCH_LINES[${i}]}"
    printf '      "kind": "%s",\n' "$(_dte_json_escape "${DTE_BRANCH_KINDS[${i}]}")"
    printf '      "trigger": "%s",\n' \
      "$(_dte_json_escape "${DTE_BRANCH_TRIGGERS[${i}]}")"
    printf '      "context": "%s"\n' \
      "$(_dte_json_escape "${DTE_BRANCH_CONTEXTS[${i}]}")"
    printf '    }'
  done
  ((${#DTE_BRANCH_LINES[@]} > 0)) && printf '\n  '
  printf ']\n}\n'
}

# =============================================================================
# CLI
# =============================================================================

_dte_usage() {
  cat <<'HELP'
Usage: decision_tree_extractor.sh [path/to/plan.md] [--output text|json]

Extract decision branches from a plan/design document.
Exit code: 0 on success (even with 0 branches), 1 on unreadable input.
With no path, uses an embedded sample plan.
HELP
}

dte_main() {
  local path=""
  local output="text"

  while (($# > 0)); do
    case $1 in
      --output) output=${2:?--output requires a value}; shift 2 ;;
      --output=*) output=${1#*=}; shift ;;
      -h | --help) _dte_usage; return 0 ;;
      --) shift; break ;;
      -*) log::error "unknown option: $1"; return 2 ;;
      *)
        if [[ -z ${path} ]]; then
          path=$1
        else
          log::error "unexpected argument: $1"
          return 2
        fi
        shift
        ;;
    esac
  done

  if [[ ${output} != text && ${output} != json ]]; then
    log::error "invalid --output: ${output} (expected text|json)"
    return 2
  fi

  if [[ -n ${path} ]]; then
    if [[ ! -f ${path} ]]; then
      log::error "could not read ${path}: No such file or directory"
      return 1
    fi
    dte_extract_branches < "${path}"
  else
    dte_extract_branches < <(dte_sample_plan)
  fi

  if [[ ${output} == json ]]; then
    dte_render_json
  else
    dte_render_text
  fi
  return 0
}

# Run CLI only when executed, not when sourced / CLI только при исполнении
if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
  dte_main "$@"
fi
