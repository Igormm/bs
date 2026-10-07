#!/usr/bin/env bash
# shellcheck shell=bash
#
# skill_description_validator.sh — Validate a SKILL.md description against
# Matt Pocock's write-a-skill rules.
# Проверка description из SKILL.md по правилам Matt Pocock.
#
# Checks / Проверки:
#   1. Description present / description присутствует
#   2. Length <= 1024 chars / длина <= 1024 символов
#   3. Third person (no I/we/you pronouns) / третье лицо
#   4. Explicit trigger phrase ("Use when ...") / явный триггер
#   5. First sentence has an action verb / глагол действия в первом предложении
#
# Exit code / Код выхода: 0 on PASS, 1 on WARN/FAIL or bad input.
#
# Usage:
#   skill_description_validator.sh [path/to/SKILL.md] [--output text|json]

set -euo pipefail

# BS bootstrap / бутстрап BS (repo root is 4 levels up from this script)
__script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
export BS_SILENT=1
# shellcheck disable=SC1091
source "${__script_dir}/../../../../bootstrap/init.sh"

# @global SDV_MAX_CHARS — Constant: description length limit (category: constant)
# @global SDV_MAX_CHARS — Константа: лимит длины description (категория: constant)
readonly SDV_MAX_CHARS=1024

# @global SDV_TRIGGERS — Constant: trigger phrase patterns (category: constant)
# @global SDV_TRIGGERS — Константа: паттерны триггер-фраз (категория: constant)
readonly -a SDV_TRIGGERS=(
  '\buse[[:space:]]+when\b'
  '\buse[[:space:]]+for\b'
  '\buse[[:space:]]+before\b'
  '\buse[[:space:]]+during\b'
  '\buse[[:space:]]+after\b'
  '\buse[[:space:]]+while\b'
  '\binvoke[[:space:]]+when\b'
  '\binvoke[[:space:]]+before\b'
  '\binvoke[[:space:]]+after\b'
  '\btrigger[[:space:]]+when\b'
  '\bapply[[:space:]]+when\b'
  '\brun[[:space:]]+when\b'
  '\brun[[:space:]]+before\b'
)

# Action verb vocabulary / словарь глаголов действия
readonly -a SDV_ACTION_VERBS=(
  extract fill merge create build generate analyze analyse
  validate check run format parse render review audit scan
  compute score track report transform convert deploy test
  monitor log search find fetch store send read write
  refresh remove process manage apply implement interrogate
  orchestrate classify
)

# Embedded sample: a passing SKILL.md / встроенный образец: проходящий SKILL.md
_sdv_sample_skill_md() {
  cat <<'SAMPLE'
---
name: pdf-tools
description: Extract text and tables from PDF files, fill forms, merge documents. Use when working with PDF files or when user mentions PDFs, forms, or document extraction.
---

# PDF Tools

## Quick start
...
SAMPLE
}

# Check results: parallel arrays / результаты проверок: параллельные массивы
declare -a SDV_CHECK_RULES=()
declare -a SDV_CHECK_PASS=()
declare -a SDV_CHECK_DETAILS=()

# =============================================================================
# Helpers / Вспомогательные функции
# =============================================================================

# @description JSON-escape a string / Экранировать строку для JSON
_sdv_json_escape() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\t'/\\t}
  s=${s//$'\r'/\\r}
  s=${s//$'\n'/\\n}
  printf '%s' "${s}"
}

# @description Python-style list repr: ['a', 'b'] / список в стиле Python
_sdv_py_list() {
  local out="[" first=1 item
  for item in "$@"; do
    ((first)) || out+=", "
    out+="'${item}'"
    first=0
  done
  printf '%s]' "${out}"
}

# @description Append a check result / Добавить результат проверки
# @param $1 Rule name / имя правила
# @param $2 Pass flag: 1 = pass, 0 = fail / признак: 1 = прошло, 0 = упало
# @param $3 Detail text / текст детали
_sdv_add_check() {
  SDV_CHECK_RULES+=("$1")
  SDV_CHECK_PASS+=("$2")
  SDV_CHECK_DETAILS+=("$3")
}

# @description Extract the description value from YAML frontmatter (stdin)
# @description Извлечь значение description из YAML-фронтматтера (stdin)
# Minimal flat parser: key: value pairs, indented lines are continuations.
# Минимальный плоский парсер: пары key: value, отступы — продолжение значения.
_sdv_extract_description() {
  awk '
    NR == 1 {
      if (index($0, "---") != 1) exit 0   # no frontmatter / нет фронтматтера
      infm = 1
      next
    }
    infm && index($0, "---") == 1 { exit 0 }  # closing --- / конец блока
    infm { print }
  ' | awk '
    function flush() {
      if (key == "description") {
        val = ""
        for (i = 1; i <= nbuf; i++) val = (i == 1 ? buf[i] : val " " buf[i])
        desc = val
      }
      key = ""; nbuf = 0
    }
    {
      line = $0
      if (line ~ /:/ && line !~ /^[ \t]/) {
        flush()
        p = index(line, ":")
        key = substr(line, 1, p - 1)
        v = substr(line, p + 1)
        gsub(/^[ \t]+|[ \t]+$/, "", key)
        gsub(/^[ \t]+|[ \t]+$/, "", v)
        if (v != "" && v != ">") { nbuf = 1; buf[1] = v }
      } else if (key != "" && line ~ /[^ \t]/) {
        gsub(/^[ \t]+|[ \t]+$/, "", line)
        nbuf++; buf[nbuf] = line
      }
    }
    END { flush(); printf "%s", desc }
  '
}

# =============================================================================
# Analysis / Анализ
# =============================================================================

# @description Run all description checks / Выполнить все проверки description
# @param $1 Description text / текст description
sdv_analyze() {
  local -r desc=$1
  SDV_DESCRIPTION=${desc}

  # Check 1: present / проверка 1: наличие
  local trimmed=${desc}
  trimmed=${trimmed//[[:space:]]/}
  if [[ -n ${trimmed} ]]; then
    _sdv_add_check "description_present" 1 "Length: ${#desc} chars"
  elif [[ -n ${desc} ]]; then
    _sdv_add_check "description_present" 0 "Length: ${#desc} chars"
  else
    _sdv_add_check "description_present" 0 "Missing or empty description field"
  fi

  # Check 2: length / проверка 2: длина
  local len_pass=0
  ((${#desc} <= SDV_MAX_CHARS)) && len_pass=1
  _sdv_add_check "description_length" "${len_pass}" \
    "${#desc} chars (limit ${SDV_MAX_CHARS})"

  # Check 3: third person / проверка 3: третье лицо
  local -A flagged=()
  local word
  while IFS= read -r word; do
    [[ -z ${word} ]] && continue
    case " ${word} " in
      *" i "* | *" me "* | *" my "* | *" myself "* | *" we "* | *" us "* \
        | *" our "* | *" ours "* | *" ourselves "* | *" you "* \
        | *" your "* | *" yours "* | *" yourself "*)
        flagged["${word}"]=1
        ;;
    esac
  done < <(printf '%s' "${desc}" | grep -oE '[a-zA-Z]+' \
    | tr '[:upper:]' '[:lower:]' || true)
  if ((${#flagged[@]} > 0)); then
    local -a flagged_sorted=()
    mapfile -t flagged_sorted < <(printf '%s\n' "${!flagged[@]}" | sort)
    _sdv_add_check "third_person" 0 \
      "Found pronouns: $(_sdv_py_list "${flagged_sorted[@]}")"
  else
    _sdv_add_check "third_person" 1 "No 1st/2nd-person pronouns"
  fi

  # Check 4: explicit trigger / проверка 4: явный триггер
  local trigger_found="" pat
  for pat in "${SDV_TRIGGERS[@]}"; do
    if printf '%s' "${desc}" | grep -qiE -- "${pat}"; then
      trigger_found=${pat}
      break
    fi
  done
  if [[ -n ${trigger_found} ]]; then
    _sdv_add_check "explicit_trigger" 1 \
      "Found trigger phrase matching: ${trigger_found}"
  else
    _sdv_add_check "explicit_trigger" 0 \
      'No explicit trigger ("Use when..." or similar). Agent will struggle to know when to invoke.'
  fi

  # Check 5: action verb in first sentence
  # проверка 5: глагол действия в первом предложении
  local first_sentence
  first_sentence=$(printf '%s' "${desc}" | sed -E 's/\.[[:space:]].*$//')
  local verbs_re
  verbs_re="\b($(IFS='|'; printf '%s' "${SDV_ACTION_VERBS[*]}"))s?\b"
  local -a verbs=()
  while IFS= read -r word; do
    [[ -n ${word} ]] && verbs+=("${word}")
  done < <(printf '%s' "${first_sentence}" | grep -oiE -- "${verbs_re}" || true)
  if ((${#verbs[@]} > 0)); then
    _sdv_add_check "first_sentence_has_action_verb" 1 \
      "Verb(s) found in first sentence: $(_sdv_py_list "${verbs[@]}")"
  else
    _sdv_add_check "first_sentence_has_action_verb" 0 \
      "No action verb detected in first sentence"
  fi
}

# =============================================================================
# Rendering / Вывод
# =============================================================================

_sdv_summarize() {
  SDV_TOTAL=${#SDV_CHECK_RULES[@]}
  SDV_PASSED=0
  local p
  for p in ${SDV_CHECK_PASS[@]+"${SDV_CHECK_PASS[@]}"}; do
    ((p == 1)) && ((++SDV_PASSED))
  done
  if ((SDV_PASSED == SDV_TOTAL)); then
    SDV_OVERALL="PASS"
  elif ((SDV_PASSED >= 3)); then
    SDV_OVERALL="WARN"
  else
    SDV_OVERALL="FAIL"
  fi
}

# @description Text report / Текстовый отчёт
_sdv_render_text() {
  local i marker preview=${SDV_DESCRIPTION:0:200}
  ((${#SDV_DESCRIPTION} > 200)) && preview+="..."
  printf '%.0s=' {1..72}
  printf '\nSKILL DESCRIPTION VALIDATOR\n'
  printf 'Source: %s\n' "${SDV_SOURCE}"
  printf '%.0s=' {1..72}
  printf '\n\nDescription (%s chars):\n  %s\n\n' "${#SDV_DESCRIPTION}" "${preview}"
  printf '%.0s-' {1..72}
  printf '\nChecks: %s / %s passed\n\n' "${SDV_PASSED}" "${SDV_TOTAL}"
  for i in "${!SDV_CHECK_RULES[@]}"; do
    if ((${SDV_CHECK_PASS[${i}]} == 1)); then marker="PASS"; else marker="FAIL"; fi
    printf '  [%s] %-30s  %s\n' "${marker}" "${SDV_CHECK_RULES[${i}]}" \
      "${SDV_CHECK_DETAILS[${i}]}"
  done
  printf '\n'
  printf '%.0s-' {1..72}
  printf '\nVerdict: %s\n\n' "${SDV_OVERALL}"
  cat <<'RULES'
Rules (per Matt Pocock's write-a-skill):
  - Max 1024 chars
  - Third person (no I/we/you)
  - First sentence: what it does (action verb)
  - Second sentence: 'Use when [specific triggers]'
RULES
}

# @description JSON report / JSON-отчёт
_sdv_render_json() {
  local i bool
  printf '{\n'
  printf '  "source": "%s",\n' "$(_sdv_json_escape "${SDV_SOURCE}")"
  printf '  "description": "%s",\n' "$(_sdv_json_escape "${SDV_DESCRIPTION}")"
  printf '  "checks": ['
  for i in "${!SDV_CHECK_RULES[@]}"; do
    ((i > 0)) && printf ','
    bool="false"
    ((${SDV_CHECK_PASS[${i}]} == 1)) && bool="true"
    printf '\n    {\n'
    printf '      "rule": "%s",\n' "$(_sdv_json_escape "${SDV_CHECK_RULES[${i}]}")"
    printf '      "pass": %s,\n' "${bool}"
    printf '      "detail": "%s"\n' \
      "$(_sdv_json_escape "${SDV_CHECK_DETAILS[${i}]}")"
    printf '    }'
  done
  ((${#SDV_CHECK_RULES[@]} > 0)) && printf '\n  '
  printf '],\n'
  printf '  "passed": %s,\n' "${SDV_PASSED}"
  printf '  "total": %s,\n' "${SDV_TOTAL}"
  printf '  "overall": "%s"\n' "${SDV_OVERALL}"
  printf '}\n'
}

# =============================================================================
# CLI
# =============================================================================

_sdv_usage() {
  cat <<'HELP'
Usage: skill_description_validator.sh [path/to/SKILL.md] [--output text|json]

Validate a SKILL.md description per Matt Pocock's rules.
Exit code: 0 on PASS, 1 on WARN/FAIL or bad input.
With no path, validates an embedded passing sample.
HELP
}

sdv_main() {
  local path=""
  local output="text"

  while (($# > 0)); do
    case $1 in
      --output) output=${2:?--output requires a value}; shift 2 ;;
      --output=*) output=${1#*=}; shift ;;
      -h | --help) _sdv_usage; return 0 ;;
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

  local desc
  if [[ -n ${path} ]]; then
    if [[ ! -f ${path} ]]; then
      log::error "could not read ${path}: No such file or directory"
      return 1
    fi
    SDV_SOURCE=${path}
    if ! desc=$(_sdv_extract_description < "${path}"); then
      log::error "could not read ${path}"
      return 1
    fi
  else
    SDV_SOURCE="<embedded sample: pdf-tools description (PASS expected)>"
    desc=$(_sdv_sample_skill_md | _sdv_extract_description)
  fi

  sdv_analyze "${desc}"
  _sdv_summarize

  if [[ ${output} == json ]]; then
    _sdv_render_json
  else
    _sdv_render_text
  fi

  [[ ${SDV_OVERALL} == "PASS" ]]
}

sdv_main "$@"
