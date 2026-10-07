#!/usr/bin/env bash
# shellcheck shell=bash
#
# grill_session_tracker.sh — Track grill-me session state across turns.
# Трекер состояния grill-сессий между ходами.
#
# JSON-backed session storage in ~/.grill_sessions/<session_name>.json
# JSON-хранилище сессий в ~/.grill_sessions/<имя>.json
#
# Actions / Действия:
#   start  <session> [--plan path]   initialize from a plan doc / создать
#   record <session> --question-id N --answer "text" / записать ответ
#   status <session>                 show progress / прогресс
#   list                             list all sessions / все сессии
#   close  <session>                 mark complete / завершить
#
# Exit code / Код выхода: 0 on success; 1 on missing args/session/input;
# 2 on invalid option values. A status query for a missing session prints
# "ERROR: Session not found" but exits 0 (same contract as the Python tool).
#
# Usage:
#   grill_session_tracker.sh --action list
#   grill_session_tracker.sh --action start --session my-plan --plan plan.md
#   grill_session_tracker.sh --action record --session my-plan --question-id 1 \
#     --answer "we chose X"
#   grill_session_tracker.sh --action status --session my-plan
#   grill_session_tracker.sh --action close --session my-plan

set -euo pipefail

# BS bootstrap / бутстрап BS (repo root is 4 levels up from this script)
__script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
export BS_SILENT=1
# shellcheck disable=SC1091
source "${__script_dir}/../../../../bootstrap/init.sh"

# Question generation lives in the sibling module / генерация вопросов — рядом
# shellcheck disable=SC1091
source "${__script_dir}/question_generator.sh"

# @global GST_SESSIONS_DIR — Constant: session storage dir (category: constant)
# @global GST_SESSIONS_DIR — Константа: каталог хранения сессий (constant)
readonly GST_SESSIONS_DIR="${HOME}/.grill_sessions"

# Session state in memory / состояние сессии в памяти
GST_NAME=""
GST_STARTED_AT=""
GST_PLAN_SOURCE=""
GST_TOTAL=0
GST_STATUS="active"
GST_CLOSED_AT=""
declare -a GST_Q_N=()
declare -a GST_Q_LINE=()
declare -a GST_Q_KIND=()
declare -a GST_Q_CONTEXT=()
declare -a GST_Q_QUESTION=()
declare -a GST_Q_RECOMMENDED=()
declare -a GST_ANS_IDS=()
declare -A GST_ANS_TEXT=()
declare -A GST_ANS_AT=()

# =============================================================================
# Helpers / Вспомогательные функции
# =============================================================================

# @description Current timestamp, ISO seconds / текущее время, ISO до секунд
_gst_now() {
  date '+%Y-%m-%dT%H:%M:%S'
}

# @description JSON-escape a string / Экранировать строку для JSON
_gst_json_escape() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\t'/\\t}
  s=${s//$'\r'/\\r}
  s=${s//$'\n'/\\n}
  printf '%s' "${s}"
}

# @description Undo _gst_json_escape / обратное экранирование JSON-строки
_gst_json_unescape() {
  local s=$1
  s=${s//\\\\/$'\x01'}
  s=${s//\\\"/\"}
  s=${s//\\n/$'\n'}
  s=${s//\\t/$'\t'}
  s=${s//\\r/$'\r'}
  s=${s//$'\x01'/\\}
  printf '%s' "${s}"
}

# @description Path of a session file / путь к файлу сессии
_gst_session_path() {
  printf '%s/%s.json' "${GST_SESSIONS_DIR}" "$1"
}

# =============================================================================
# Persistence / Хранение
# =============================================================================

# @description Serialize in-memory session to its JSON file
# @description Сериализовать сессию из памяти в JSON-файл
gst_save() {
  mkdir -p -- "${GST_SESSIONS_DIR}"
  local path
  path=$(_gst_session_path "${GST_NAME}")
  local i id
  {
    printf '{\n'
    printf '  "name": "%s",\n' "$(_gst_json_escape "${GST_NAME}")"
    printf '  "started_at": "%s",\n' "$(_gst_json_escape "${GST_STARTED_AT}")"
    printf '  "plan_source": "%s",\n' "$(_gst_json_escape "${GST_PLAN_SOURCE}")"
    printf '  "total_questions": %s,\n' "${GST_TOTAL}"
    printf '  "questions": ['
    for i in "${!GST_Q_N[@]}"; do
      ((i > 0)) && printf ','
      printf '\n    {"n": %s, "line": %s, "branch_kind": "%s", "context": "%s", "question": "%s", "recommended": "%s"}' \
        "${GST_Q_N[${i}]}" "${GST_Q_LINE[${i}]}" \
        "$(_gst_json_escape "${GST_Q_KIND[${i}]}")" \
        "$(_gst_json_escape "${GST_Q_CONTEXT[${i}]}")" \
        "$(_gst_json_escape "${GST_Q_QUESTION[${i}]}")" \
        "$(_gst_json_escape "${GST_Q_RECOMMENDED[${i}]}")"
    done
    ((${#GST_Q_N[@]} > 0)) && printf '\n  '
    printf '],\n'
    printf '  "answers": {'
    for i in "${!GST_ANS_IDS[@]}"; do
      ((i > 0)) && printf ','
      id=${GST_ANS_IDS[${i}]}
      printf '\n    "%s": {"answer": "%s", "recorded_at": "%s"}' \
        "${id}" \
        "$(_gst_json_escape "${GST_ANS_TEXT[${id}]}")" \
        "$(_gst_json_escape "${GST_ANS_AT[${id}]}")"
    done
    ((${#GST_ANS_IDS[@]} > 0)) && printf '\n  '
    printf '},\n'
    printf '  "status": "%s"' "${GST_STATUS}"
    if [[ -n ${GST_CLOSED_AT} ]]; then
      printf ',\n  "closed_at": "%s"\n' "$(_gst_json_escape "${GST_CLOSED_AT}")"
    else
      printf '\n'
    fi
    printf '}\n'
  } > "${path}"
}

# @description Load a session file into memory; 1 if missing
# @description Загрузить файл сессии в память; 1 если файла нет
# @param $1 Session name / имя сессии
gst_load() {
  local -r name=$1
  local path
  path=$(_gst_session_path "${name}")
  [[ -f ${path} ]] || return 1

  GST_NAME=${name}
  GST_STARTED_AT=$(sed -n 's/^  "started_at": "\(.*\)",$/\1/p' -- "${path}")
  GST_PLAN_SOURCE=$(sed -n 's/^  "plan_source": "\(.*\)",$/\1/p' -- "${path}")
  GST_TOTAL=$(sed -n 's/^  "total_questions": \([0-9][0-9]*\),$/\1/p' -- "${path}")
  GST_STATUS=$(sed -n 's/^  "status": "\(.*\)"[},]*$/\1/p' -- "${path}")
  GST_CLOSED_AT=$(sed -n 's/^  "closed_at": "\(.*\)"$/\1/p' -- "${path}")
  : "${GST_TOTAL:=0}"

  # Question lines: one object per line (our writer guarantees this)
  # Строки вопросов: один объект на строку (гарантирует наш сериализатор)
  GST_Q_N=(); GST_Q_LINE=(); GST_Q_KIND=()
  GST_Q_CONTEXT=(); GST_Q_QUESTION=(); GST_Q_RECOMMENDED=()
  local qline
  while IFS= read -r qline; do
    GST_Q_N+=("$(printf '%s' "${qline}" \
      | sed 's/^    {"n": \([0-9]*\), "line": .*/\1/')")
    GST_Q_LINE+=("$(printf '%s' "${qline}" \
      | sed 's/^    {"n": [0-9]*, "line": \([0-9]*\), "branch_kind": .*/\1/')")
    GST_Q_KIND+=("$(printf '%s' "${qline}" \
      | sed 's/^    {"n": [0-9]*, "line": [0-9]*, "branch_kind": "\([^"]*\)", .*/\1/')")
    GST_Q_CONTEXT+=("$(_gst_json_unescape "$(printf '%s' "${qline}" \
      | sed 's/^    {"n": [0-9]*, "line": [0-9]*, "branch_kind": "[^"]*", "context": "\(.*\)", "question": ".*$/\1/')")")
    GST_Q_QUESTION+=("$(_gst_json_unescape "$(printf '%s' "${qline}" \
      | sed 's/^.*", "question": "\(.*\)", "recommended": ".*$/\1/')")")
    GST_Q_RECOMMENDED+=("$(_gst_json_unescape "$(printf '%s' "${qline}" \
      | sed 's/^.*", "recommended": "\(.*\)"},\?$/\1/')")")
  done < <(sed -n '/^    {"n": [0-9]/p' -- "${path}")

  # Answer lines: "N": {"answer": "...", "recorded_at": "..."}
  # Строки ответов: "N": {"answer": "...", "recorded_at": "..."}
  GST_ANS_IDS=()
  GST_ANS_TEXT=()
  GST_ANS_AT=()
  local aline id
  while IFS= read -r aline; do
    id=$(printf '%s' "${aline}" | sed 's/^    "\([0-9]*\)": .*/\1/')
    GST_ANS_IDS+=("${id}")
    GST_ANS_TEXT["${id}"]=$(_gst_json_unescape "$(printf '%s' "${aline}" \
      | sed 's/^    "[0-9]*": {"answer": "\(.*\)", "recorded_at": ".*$/\1/')")
    GST_ANS_AT["${id}"]=$(printf '%s' "${aline}" \
      | sed 's/^    "[0-9]*": {"answer": ".*", "recorded_at": "\(.*\)"},\?$/\1/')
  done < <(sed -n '/^    "[0-9][0-9]*": {"answer": "/p' -- "${path}")

  return 0
}

# =============================================================================
# Actions / Действия
# =============================================================================

# @description start: build a session from a plan doc
# @description start: создать сессию из плана
gst_start() {
  local -r name=$1 plan_path=$2
  if [[ -n ${plan_path} ]]; then
    if [[ ! -f ${plan_path} ]]; then
      log::error "could not read ${plan_path}: No such file or directory"
      return 1
    fi
    qg_analyze < "${plan_path}"
    GST_PLAN_SOURCE=${plan_path}
  else
    qg_analyze < <(dte_sample_plan)
    GST_PLAN_SOURCE="<embedded sample>"
  fi

  GST_NAME=${name}
  GST_STARTED_AT=$(_gst_now)
  GST_TOTAL=${#QG_Q_LINE[@]}
  GST_STATUS="active"
  GST_CLOSED_AT=""
  GST_Q_N=(); GST_Q_LINE=(); GST_Q_KIND=()
  GST_Q_CONTEXT=(); GST_Q_QUESTION=(); GST_Q_RECOMMENDED=()
  local i
  for i in "${!QG_Q_LINE[@]}"; do
    GST_Q_N+=("$((i + 1))")
    GST_Q_LINE+=("${QG_Q_LINE[${i}]}")
    GST_Q_KIND+=("${QG_Q_KIND[${i}]}")
    GST_Q_CONTEXT+=("${QG_Q_CONTEXT[${i}]}")
    GST_Q_QUESTION+=("${QG_Q_QUESTION[${i}]}")
    GST_Q_RECOMMENDED+=("${QG_Q_RECOMMENDED[${i}]}")
  done
  GST_ANS_IDS=()
  GST_ANS_TEXT=()
  GST_ANS_AT=()
  gst_save
}

# @description record: store an answer; 1 if session missing
# @description record: записать ответ; 1 если сессии нет
gst_record() {
  local -r name=$1 qid=$2 answer=$3
  if ! gst_load "${name}"; then
    log::error "Session not found: ${name}"
    return 1
  fi
  if [[ ! " ${GST_ANS_IDS[*]-} " == *" ${qid} "* ]]; then
    GST_ANS_IDS+=("${qid}")
  fi
  GST_ANS_TEXT["${qid}"]=${answer}
  GST_ANS_AT["${qid}"]=$(_gst_now)
  gst_save
}

# @description close: mark a session closed; 1 if session missing
# @description close: завершить сессию; 1 если сессии нет
gst_close() {
  local -r name=$1
  if ! gst_load "${name}"; then
    log::error "Session not found: ${name}"
    return 1
  fi
  GST_STATUS="closed"
  GST_CLOSED_AT=$(_gst_now)
  gst_save
}

# @description list: print stored session names / список сессий
gst_list() {
  mkdir -p -- "${GST_SESSIONS_DIR}"
  GST_LIST_NAMES=()
  local f
  for f in "${GST_SESSIONS_DIR}/"*.json; do
    [[ -e ${f} ]] || continue
    f=${f##*/}
    GST_LIST_NAMES+=("${f%.json}")
  done
  if ((${#GST_LIST_NAMES[@]} > 0)); then
    local -a sorted=()
    mapfile -t sorted < <(printf '%s\n' "${GST_LIST_NAMES[@]}" | sort)
    GST_LIST_NAMES=("${sorted[@]}")
  fi
}

# =============================================================================
# Status computation + rendering / Статус и вывод
# =============================================================================

# @description Compute status fields into GST_ST_* (needs loaded session)
# @description Вычислить поля статуса в GST_ST_* (по загруженной сессии)
_gst_status_compute() {
  GST_ST_ANSWERED=${#GST_ANS_IDS[@]}
  GST_ST_NEXT_N=""
  local i n
  for i in "${!GST_Q_N[@]}"; do
    n=${GST_Q_N[${i}]}
    if [[ -z ${GST_ANS_TEXT[${n}]:-} ]]; then
      GST_ST_NEXT_N=${n}
      break
    fi
  done
  local denom=${GST_TOTAL}
  ((denom < 1)) && denom=1
  GST_ST_PCT=$(awk -v a="${GST_ST_ANSWERED}" -v t="${denom}" \
    'BEGIN { printf "%.1f", 100.0 * a / t }')
}

# @description Text status report / текстовый отчёт о статусе
_gst_render_status_text() {
  local i n
  printf '%.0s=' {1..72}
  printf '\nGRILL SESSION: %s\n' "${GST_NAME}"
  printf '%.0s=' {1..72}
  printf '\nStatus: %s  (%s / %s answered, %s%%)\n\n' "${GST_STATUS}" \
    "${GST_ST_ANSWERED}" "${GST_TOTAL}" "${GST_ST_PCT}"
  if [[ -n ${GST_ST_NEXT_N} ]]; then
    for i in "${!GST_Q_N[@]}"; do
      [[ ${GST_Q_N[${i}]} == "${GST_ST_NEXT_N}" ]] || continue
      printf 'Next question (Q%s):\n' "${GST_Q_N[${i}]}"
      printf '  %s\n' "${GST_Q_QUESTION[${i}]}"
      printf '  Recommended: %s\n' "${GST_Q_RECOMMENDED[${i}]}"
    done
  else
    printf 'All questions answered. Run --action close to mark session complete.\n'
  fi
  printf '\n'
  if ((${#GST_ANS_IDS[@]} > 0)); then
    printf 'Answered:\n'
    while IFS= read -r n; do
      [[ -z ${n} ]] && continue
      printf '  Q%s: %s\n' "${n}" "${GST_ANS_TEXT[${n}]:0:100}"
    done < <(printf '%s\n' "${GST_ANS_IDS[@]}" | sort -n)
  fi
}

# @description JSON status report / JSON-отчёт о статусе
_gst_render_status_json() {
  local i n first=1
  printf '{\n'
  printf '  "name": "%s",\n' "$(_gst_json_escape "${GST_NAME}")"
  printf '  "status": "%s",\n' "${GST_STATUS}"
  printf '  "answered": %s,\n' "${GST_ST_ANSWERED}"
  printf '  "total": %s,\n' "${GST_TOTAL}"
  printf '  "percent_complete": %s,\n' "${GST_ST_PCT}"
  if [[ -n ${GST_ST_NEXT_N} ]]; then
    for i in "${!GST_Q_N[@]}"; do
      [[ ${GST_Q_N[${i}]} == "${GST_ST_NEXT_N}" ]] || continue
      printf '  "next_question": {\n'
      printf '    "n": %s,\n' "${GST_Q_N[${i}]}"
      printf '    "line": %s,\n' "${GST_Q_LINE[${i}]}"
      printf '    "branch_kind": "%s",\n' \
        "$(_gst_json_escape "${GST_Q_KIND[${i}]}")"
      printf '    "context": "%s",\n' \
        "$(_gst_json_escape "${GST_Q_CONTEXT[${i}]}")"
      printf '    "question": "%s",\n' \
        "$(_gst_json_escape "${GST_Q_QUESTION[${i}]}")"
      printf '    "recommended": "%s"\n' \
        "$(_gst_json_escape "${GST_Q_RECOMMENDED[${i}]}")"
      printf '  },\n'
    done
  else
    printf '  "next_question": null,\n'
  fi
  printf '  "all_answers": {'
  for i in "${!GST_ANS_IDS[@]}"; do
    n=${GST_ANS_IDS[${i}]}
    ((first)) || printf ','
    first=0
    printf '\n    "%s": {\n      "answer": "%s",\n      "recorded_at": "%s"\n    }' \
      "${n}" \
      "$(_gst_json_escape "${GST_ANS_TEXT[${n}]}")" \
      "$(_gst_json_escape "${GST_ANS_AT[${n}]}")"
  done
  ((first)) || printf '\n  '
  printf '}\n}\n'
}

# @description Full session JSON (for start/close) / полный JSON сессии
_gst_render_session_json() {
  local i first=1 n
  printf '{\n'
  printf '  "name": "%s",\n' "$(_gst_json_escape "${GST_NAME}")"
  printf '  "started_at": "%s",\n' "$(_gst_json_escape "${GST_STARTED_AT}")"
  printf '  "plan_source": "%s",\n' "$(_gst_json_escape "${GST_PLAN_SOURCE}")"
  printf '  "total_questions": %s,\n' "${GST_TOTAL}"
  printf '  "questions": ['
  for i in "${!GST_Q_N[@]}"; do
    ((i > 0)) && printf ','
    printf '\n    {\n'
    printf '      "n": %s,\n' "${GST_Q_N[${i}]}"
    printf '      "line": %s,\n' "${GST_Q_LINE[${i}]}"
    printf '      "branch_kind": "%s",\n' \
      "$(_gst_json_escape "${GST_Q_KIND[${i}]}")"
    printf '      "context": "%s",\n' \
      "$(_gst_json_escape "${GST_Q_CONTEXT[${i}]}")"
    printf '      "question": "%s",\n' \
      "$(_gst_json_escape "${GST_Q_QUESTION[${i}]}")"
    printf '      "recommended": "%s"\n' \
      "$(_gst_json_escape "${GST_Q_RECOMMENDED[${i}]}")"
    printf '    }'
  done
  ((${#GST_Q_N[@]} > 0)) && printf '\n  '
  printf '],\n'
  printf '  "answers": {'
  for i in "${!GST_ANS_IDS[@]}"; do
    n=${GST_ANS_IDS[${i}]}
    ((first)) || printf ','
    first=0
    printf '\n    "%s": {\n      "answer": "%s",\n      "recorded_at": "%s"\n    }' \
      "${n}" \
      "$(_gst_json_escape "${GST_ANS_TEXT[${n}]}")" \
      "$(_gst_json_escape "${GST_ANS_AT[${n}]}")"
  done
  ((first)) || printf '\n  '
  printf '},\n'
  printf '  "status": "%s"' "${GST_STATUS}"
  if [[ -n ${GST_CLOSED_AT} ]]; then
    printf ',\n  "closed_at": "%s"\n' "$(_gst_json_escape "${GST_CLOSED_AT}")"
  else
    printf '\n'
  fi
  printf '}\n'
}

# =============================================================================
# CLI
# =============================================================================

_gst_usage() {
  cat <<'HELP'
Usage: grill_session_tracker.sh --action ACTION [options]

Actions: start | record | status | list | close
Options:
  --session NAME     Session name (start/status default: sample-session)
  --plan PATH        Plan markdown for start
  --question-id N    Question number for record
  --answer TEXT      Answer text for record
  --output text|json Output format (default: text)
HELP
}

gst_main() {
  local action="status"
  local session=""
  local plan=""
  local question_id=""
  local answer=""
  local output="text"

  while (($# > 0)); do
    case $1 in
      --action) action=${2:?--action requires a value}; shift 2 ;;
      --action=*) action=${1#*=}; shift ;;
      --session) session=${2:?--session requires a value}; shift 2 ;;
      --session=*) session=${1#*=}; shift ;;
      --plan) plan=${2:?--plan requires a value}; shift 2 ;;
      --plan=*) plan=${1#*=}; shift ;;
      --question-id) question_id=${2:?--question-id requires a value}; shift 2 ;;
      --question-id=*) question_id=${1#*=}; shift ;;
      --answer) answer=${2:?--answer requires a value}; shift 2 ;;
      --answer=*) answer=${1#*=}; shift ;;
      --output) output=${2:?--output requires a value}; shift 2 ;;
      --output=*) output=${1#*=}; shift ;;
      -h | --help) _gst_usage; return 0 ;;
      --) shift; break ;;
      -*) log::error "unknown option: $1"; return 2 ;;
      *) log::error "unexpected argument: $1"; return 2 ;;
    esac
  done

  if [[ ${output} != text && ${output} != json ]]; then
    log::error "invalid --output: ${output} (expected text|json)"
    return 2
  fi

  case ${action} in
    list)
      gst_list
      if [[ ${output} == json ]]; then
        local i
        printf '{\n  "sessions": ['
        for i in "${!GST_LIST_NAMES[@]}"; do
          ((i > 0)) && printf ', '
          printf '"%s"' "$(_gst_json_escape "${GST_LIST_NAMES[${i}]}")"
        done
        printf ']\n}\n'
      else
        printf 'Sessions:\n'
        if ((${#GST_LIST_NAMES[@]} > 0)); then
          printf '  - %s\n' "${GST_LIST_NAMES[@]}"
        else
          printf '  - (none)\n'
        fi
      fi
      ;;
    start)
      gst_start "${session:-sample-session}" "${plan}" || return 1
      if [[ ${output} == json ]]; then
        _gst_render_session_json
      else
        printf 'Started session: %s\n' "${GST_NAME}"
        printf '  Plan: %s\n' "${GST_PLAN_SOURCE}"
        printf '  Total questions: %s\n' "${GST_TOTAL}"
        if ((${#GST_Q_N[@]} > 0)); then
          printf '  First question: %s\n' "${GST_Q_QUESTION[0]}"
        else
          printf '  First question: (none)\n'
        fi
      fi
      ;;
    record)
      if [[ -z ${session} || -z ${question_id} || -z ${answer} ]]; then
        log::error "record requires --session, --question-id, --answer"
        return 1
      fi
      if [[ ! ${question_id} =~ ^[0-9]+$ ]]; then
        log::error "invalid --question-id: ${question_id} (expected integer)"
        return 2
      fi
      gst_record "${session}" "${question_id}" "${answer}" || return 1
      _gst_status_compute
      if [[ ${output} == json ]]; then
        _gst_render_status_json
      else
        _gst_render_status_text
      fi
      ;;
    status)
      if ! gst_load "${session:-sample-session}"; then
        if [[ ${output} == json ]]; then
          printf '{\n  "error": "Session not found: %s"\n}\n' \
            "$(_gst_json_escape "${session:-sample-session}")"
        else
          printf 'ERROR: Session not found: %s\n' "${session:-sample-session}"
        fi
        return 0
      fi
      _gst_status_compute
      if [[ ${output} == json ]]; then
        _gst_render_status_json
      else
        _gst_render_status_text
      fi
      ;;
    close)
      if [[ -z ${session} ]]; then
        log::error "close requires --session"
        return 1
      fi
      gst_close "${session}" || return 1
      if [[ ${output} == json ]]; then
        _gst_render_session_json
      else
        printf 'Closed session: %s\n' "${session}"
      fi
      ;;
    *)
      log::error "invalid --action: ${action} (expected start|record|status|list|close)"
      return 2
      ;;
  esac
  return 0
}

gst_main "$@"
