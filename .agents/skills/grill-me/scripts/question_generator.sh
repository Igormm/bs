#!/usr/bin/env bash
# shellcheck shell=bash
#
# question_generator.sh — Generate forcing questions from extracted decision
# branches, per Matt Pocock's grill-me discipline.
# Генерация вынуждающих вопросов из ветвей решений (дисциплина grill-me).
#
# Rules / Правила:
#   - One question per decision branch / один вопрос на ветвь
#   - Each question carries a recommended answer / у каждого — рекомендация
#   - Dependency branches are asked last / зависимости — в конец
#
# Exit code / Код выхода: 0 on success, 1 on unreadable input.
#
# Sourceable like its Python ancestor (functions only when sourced).
# Можно подключать через source (только функции), как Python-модуль.
#
# Usage:
#   question_generator.sh [path/to/plan.md] [--output text|json]

set -euo pipefail

# BS bootstrap / бутстрап BS (repo root is 4 levels up from this script)
__script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
export BS_SILENT=1
# shellcheck disable=SC1091
source "${__script_dir}/../../../../bootstrap/init.sh"

# Branch extraction lives in the sibling module / извлечение ветвей — рядом
# shellcheck disable=SC1091
source "${__script_dir}/decision_tree_extractor.sh"

# Question templates per branch kind / шаблоны вопросов по видам ветвей
readonly -A QG_QUESTION_TEMPLATES=(
  ["intent"]="Why this approach and not the obvious alternative?"
  ["choice"]="Which side of the choice, and what's the deciding criterion?"
  ["open"]="What's blocking this decision? What would unblock it today?"
  ["tradeoff"]="Which side of the trade-off are you optimizing for, and what's the kill criterion?"
  ["dependency"]="Is the dependency locked in? If not, that decision comes first."
  ["question"]="What's your current best answer, even if uncertain?"
)

# Recommendation templates per branch kind / шаблоны рекомендаций
readonly -A QG_RECOMMENDED_TEMPLATES=(
  ["intent"]="State the alternative explicitly + 1 sentence why you rejected it."
  ["choice"]="Pick the option that aligns with the constraint you can't change (budget, deadline, team)."
  ["open"]="Name the missing input. Estimate when it arrives. Decide now under uncertainty if it won't arrive in time."
  ["tradeoff"]="Choose the side that's reversible later. Trade-offs are usually one-way; pick the one with the escape hatch."
  ["dependency"]="Resolve the upstream decision first. Then re-evaluate this one."
  ["question"]="Even a 60%-confidence answer is better than 'we'll figure it out later'."
)

# Generated questions: parallel arrays / вопросы: параллельные массивы
declare -a QG_Q_LINE=()
declare -a QG_Q_KIND=()
declare -a QG_Q_CONTEXT=()
declare -a QG_Q_QUESTION=()
declare -a QG_Q_RECOMMENDED=()

# Sorted unique branch kinds / отсортированные уникальные виды ветвей
declare -a QG_BRANCH_KINDS=()

# =============================================================================
# Generation / Генерация
# =============================================================================

# @description Generate questions from plan text on stdin into QG_Q_*
# @description Сгенерировать вопросы из текста плана (stdin) в QG_Q_*
qg_analyze() {
  dte_extract_branches

  QG_Q_LINE=()
  QG_Q_KIND=()
  QG_Q_CONTEXT=()
  QG_Q_QUESTION=()
  QG_Q_RECOMMENDED=()

  # Ordering: non-dependency first (stable), dependency last
  # Порядок: сначала независимые (стабильно), зависимости — в конец
  local -a ordered=()
  local i kind
  for i in "${!DTE_BRANCH_KINDS[@]}"; do
    [[ ${DTE_BRANCH_KINDS[${i}]} == dependency ]] || ordered+=("${i}")
  done
  for i in "${!DTE_BRANCH_KINDS[@]}"; do
    [[ ${DTE_BRANCH_KINDS[${i}]} == dependency ]] && ordered+=("${i}")
  done

  local q_tmpl r_tmpl
  for i in ${ordered[@]+"${ordered[@]}"}; do
    kind=${DTE_BRANCH_KINDS[${i}]}
    q_tmpl=${QG_QUESTION_TEMPLATES[${kind}]:-"What's the current state?"}
    r_tmpl=${QG_RECOMMENDED_TEMPLATES[${kind}]:-"State your best answer."}
    QG_Q_LINE+=("${DTE_BRANCH_LINES[${i}]}")
    QG_Q_KIND+=("${kind}")
    QG_Q_CONTEXT+=("${DTE_BRANCH_CONTEXTS[${i}]}")
    QG_Q_QUESTION+=("L${DTE_BRANCH_LINES[${i}]}: ${DTE_BRANCH_CONTEXTS[${i}]} -> ${q_tmpl}")
    QG_Q_RECOMMENDED+=("${r_tmpl}")
  done

  # Sorted unique kinds / отсортированные уникальные виды
  QG_BRANCH_KINDS=()
  if ((${#DTE_BY_KIND_ORDER[@]} > 0)); then
    while IFS= read -r kind; do
      [[ -n ${kind} ]] && QG_BRANCH_KINDS+=("${kind}")
    done < <(printf '%s\n' "${DTE_BY_KIND_ORDER[@]}" | sort)
  fi
}

# =============================================================================
# Rendering / Вывод
# =============================================================================

# @description Python list repr of branch kinds / repr списка видов
_qg_kinds_repr() {
  local out="[" first=1 k
  for k in ${QG_BRANCH_KINDS[@]+"${QG_BRANCH_KINDS[@]}"}; do
    ((first)) || out+=", "
    out+="'${k}'"
    first=0
  done
  printf '%s]' "${out}"
}

# @description JSON-escape a string / Экранировать строку для JSON
_qg_json_escape() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\t'/\\t}
  s=${s//$'\r'/\\r}
  s=${s//$'\n'/\\n}
  printf '%s' "${s}"
}

# @description Text report / Текстовый отчёт
qg_render_text() {
  local i
  printf '%.0s=' {1..72}
  printf "\nFORCING QUESTION GENERATOR (one at a time, per Matt's grill-me)\n"
  printf '%.0s=' {1..72}
  printf '\n\nTotal questions: %s\n' "${#QG_Q_LINE[@]}"
  printf 'Branch kinds: %s\n\n' "$(_qg_kinds_repr)"
  printf '%.0s-' {1..72}
  printf '\n'
  for i in "${!QG_Q_LINE[@]}"; do
    printf '  Q%2d: %s\n' "$((i + 1))" "${QG_Q_QUESTION[${i}]}"
    printf '        Recommended: %s\n\n' "${QG_Q_RECOMMENDED[${i}]}"
  done
}

# @description JSON report / JSON-отчёт
qg_render_json() {
  local i
  printf '{\n'
  printf '  "total_questions": %s,\n' "${#QG_Q_LINE[@]}"
  printf '  "branch_kinds": ['
  for i in "${!QG_BRANCH_KINDS[@]}"; do
    ((i > 0)) && printf ', '
    printf '"%s"' "$(_qg_json_escape "${QG_BRANCH_KINDS[${i}]}")"
  done
  printf '],\n'
  printf '  "questions": ['
  for i in "${!QG_Q_LINE[@]}"; do
    ((i > 0)) && printf ','
    printf '\n    {\n'
    printf '      "n": %s,\n' "$((i + 1))"
    printf '      "line": %s,\n' "${QG_Q_LINE[${i}]}"
    printf '      "branch_kind": "%s",\n' "$(_qg_json_escape "${QG_Q_KIND[${i}]}")"
    printf '      "context": "%s",\n' "$(_qg_json_escape "${QG_Q_CONTEXT[${i}]}")"
    printf '      "question": "%s",\n' "$(_qg_json_escape "${QG_Q_QUESTION[${i}]}")"
    printf '      "recommended": "%s"\n' \
      "$(_qg_json_escape "${QG_Q_RECOMMENDED[${i}]}")"
    printf '    }'
  done
  ((${#QG_Q_LINE[@]} > 0)) && printf '\n  '
  printf ']\n}\n'
}

# =============================================================================
# CLI
# =============================================================================

_qg_usage() {
  cat <<'HELP'
Usage: question_generator.sh [path/to/plan.md] [--output text|json]

Generate forcing questions from a plan/design document.
Exit code: 0 on success (even with 0 questions), 1 on unreadable input.
With no path, uses an embedded sample plan.
HELP
}

qg_main() {
  local path=""
  local output="text"

  while (($# > 0)); do
    case $1 in
      --output) output=${2:?--output requires a value}; shift 2 ;;
      --output=*) output=${1#*=}; shift ;;
      -h | --help) _qg_usage; return 0 ;;
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
    qg_analyze < "${path}"
  else
    qg_analyze < <(dte_sample_plan)
  fi

  if [[ ${output} == json ]]; then
    qg_render_json
  else
    qg_render_text
  fi
  return 0
}

# Run CLI only when executed, not when sourced / CLI только при исполнении
if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
  qg_main "$@"
fi
