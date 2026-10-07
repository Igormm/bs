#!/usr/bin/env bash
# shellcheck shell=bash
#
# skill_review_checklist_runner.sh — Run Matt Pocock's 6-item review checklist
# programmatically against a skill folder.
# Прогон 6-пунктного чек-листа Matt Pocock для каталога скилла.
#
# Checklist / Чек-лист:
#   1. Description includes triggers ("Use when...")
#   2. SKILL.md under 100 lines
#   3. No time-sensitive info / без устаревающих дат
#   4. Consistent terminology / согласованная терминология
#   5. Concrete examples included (>=1 code block) / примеры (блок кода)
#   6. References one level deep / справочники в один уровень
#
# Exit code / Код выхода: 0 on PASS, 1 on WARN/FAIL or bad input.
#
# Usage:
#   skill_review_checklist_runner.sh [path/to/skill-folder/] [--output text|json]

set -euo pipefail

# BS bootstrap / бутстрап BS (repo root is 4 levels up from this script)
__script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
export BS_SILENT=1
# shellcheck disable=SC1091
source "${__script_dir}/../../../../bootstrap/init.sh"

# @global SRCR_MAX_LINES — Constant: SKILL.md line ceiling (category: constant)
# @global SRCR_MAX_LINES — Константа: потолок строк SKILL.md (категория: constant)
readonly SRCR_MAX_LINES=100

# Trigger phrase patterns / паттерны триггер-фраз
readonly -a SRCR_TRIGGERS=(
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

# Time-sensitive content patterns / паттерны устаревающего контента
readonly -a SRCR_TIME_PATTERNS=(
  '\bas[[:space:]]+of[[:space:]]+[0-9]{4}\b'
  '\bin[[:space:]]+20[0-9]{2}\b'
  '\b(january|february|march|april|may|june|july|august|september|october|november|december)[[:space:]]+[0-9]{4}\b'
  '\b(released|launched|published|updated)[[:space:]]+(on|in)\b'
)

# Synonym pairs for the terminology check / пары синонимов для терминологии
readonly -a SRCR_SYNONYM_PAIRS=("agent bot" "skill tool" "user developer")

# Check results: parallel arrays / результаты проверок: параллельные массивы
declare -a SRCR_CHECK_RULES=()
declare -a SRCR_CHECK_PASS=()
declare -a SRCR_CHECK_DETAILS=()

# =============================================================================
# Helpers / Вспомогательные функции
# =============================================================================

# @description JSON-escape a string / Экранировать строку для JSON
_srcr_json_escape() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\t'/\\t}
  s=${s//$'\r'/\\r}
  s=${s//$'\n'/\\n}
  printf '%s' "${s}"
}

# @description Python-style list repr: ['a', 'b'] / список в стиле Python
_srcr_py_list() {
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
_srcr_add_check() {
  SRCR_CHECK_RULES+=("$1")
  SRCR_CHECK_PASS+=("$2")
  SRCR_CHECK_DETAILS+=("$3")
}

# @description Extract the description value from YAML frontmatter (stdin)
# @description Извлечь значение description из YAML-фронтматтера (stdin)
_srcr_extract_description() {
  awk '
    NR == 1 {
      if (index($0, "---") != 1) exit 0
      infm = 1
      next
    }
    infm && index($0, "---") == 1 { exit 0 }
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
        if (v != "" && v != ">" && v != "|") { nbuf = 1; buf[1] = v }
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

# @description Run the 6-item checklist on FOLDER
# @description Выполнить чек-лист из 6 пунктов для КАТАЛОГА
# @param $1 Skill folder / каталог скилла
srcr_analyze() {
  # Python keeps the folder string as passed for display / оригинал показывает
  # каталог как передан (с хвостовым слэшем), слэш срезается только для путей
  local folder=$1
  SRCR_FOLDER=${folder}
  while [[ ${folder} == */ && ${folder} != / ]]; do
    folder=${folder%/}
  done

  local -r skill_md="${folder}/SKILL.md"
  if [[ ! -f ${skill_md} ]]; then
    _srcr_add_check "skill_md_present" 0 "SKILL.md not found at ${folder}"
    SRCR_SKILL_MD=""
    # Python original hardcodes FAIL here / оригинал жёстко ставит FAIL
    SRCR_FORCE_FAIL=1
    return 0
  fi
  SRCR_SKILL_MD=${skill_md}

  # 1. Description includes triggers / description содержит триггер
  local desc pat has_trigger=0
  desc=$(_srcr_extract_description < "${skill_md}")
  for pat in "${SRCR_TRIGGERS[@]}"; do
    if printf '%s' "${desc}" | grep -qiE -- "${pat}"; then
      has_trigger=1
      break
    fi
  done
  if ((has_trigger)); then
    _srcr_add_check "1. Description includes triggers" 1 \
      "Found explicit trigger phrase"
  else
    _srcr_add_check "1. Description includes triggers" 0 \
      "Missing explicit trigger phrase (Use when/before/after/for ...)"
  fi

  # 2. SKILL.md under 100 lines / SKILL.md короче 100 строк
  local lines line_pass=0
  lines=$(awk 'END {print NR}' "${skill_md}")
  ((lines <= SRCR_MAX_LINES)) && line_pass=1
  _srcr_add_check "2. SKILL.md under ${SRCR_MAX_LINES} lines" "${line_pass}" \
    "${lines} lines"

  # 3. No time-sensitive info / без устаревающей информации
  local -a flagged=()
  local m
  for pat in "${SRCR_TIME_PATTERNS[@]}"; do
    while IFS= read -r m; do
      [[ -n ${m} ]] && flagged+=("${m}")
    done < <(grep -oiE -- "${pat}" "${skill_md}" || true)
  done
  if ((${#flagged[@]} > 0)); then
    # Unique, first 5 / уникальные, первые 5
    local -A seen=()
    local -a unique=()
    for m in "${flagged[@]}"; do
      [[ -n ${seen[${m}]:-} ]] && continue
      seen["${m}"]=1
      unique+=("${m}")
      ((${#unique[@]} >= 5)) && break
    done
    _srcr_add_check "3. No time-sensitive info" 0 \
      "Flagged phrases: $(_srcr_py_list "${unique[@]}")"
  else
    _srcr_add_check "3. No time-sensitive info" 1 \
      "No date/year/version-bound claims detected"
  fi

  # 4. Consistent terminology / согласованная терминология
  local -a findings=()
  local pair a b
  for pair in "${SRCR_SYNONYM_PAIRS[@]}"; do
    a=${pair%% *}
    b=${pair##* }
    if grep -qiw -e "${a}" -- "${skill_md}" \
      && grep -qiw -e "${b}" -- "${skill_md}"; then
      findings+=("Both '${a}' and '${b}' used")
    fi
  done
  if ((${#findings[@]} > 0)); then
    local joined=""
    for m in "${findings[@]}"; do
      [[ -n ${joined} ]] && joined+="; "
      joined+="${m}"
    done
    _srcr_add_check "4. Consistent terminology" 0 "${joined}"
  else
    _srcr_add_check "4. Consistent terminology" 1 \
      "No obvious synonym pairs detected"
  fi

  # 5. Concrete examples (>= 1 fenced code block)
  # 5. Примеры (>= 1 блок кода)
  local fences blocks=0 ex_pass=0
  fences=$({ grep -oF '```' -- "${skill_md}" || true; } | wc -l)
  blocks=$((fences / 2))
  ((fences >= 2)) && ex_pass=1
  _srcr_add_check "5. Concrete examples included" "${ex_pass}" \
    "${blocks} code block(s) found"

  # 6. References one level deep / справочники в один уровень
  local -a deeper=()
  if [[ -d ${folder}/references ]]; then
    local entry
    while IFS= read -r entry; do
      deeper+=("${entry}")
    done < <(find "${folder}/references" -mindepth 2 -type f -name '*.md' \
      | sort)
  fi
  if ((${#deeper[@]} > 0)); then
    _srcr_add_check "6. References one level deep" 0 \
      "Found nested ref files: $(_srcr_py_list "${deeper[@]}")"
  else
    _srcr_add_check "6. References one level deep" 1 "All references at one level"
  fi
}

# =============================================================================
# Rendering / Вывод
# =============================================================================

_srcr_summarize() {
  SRCR_TOTAL=${#SRCR_CHECK_RULES[@]}
  SRCR_PASSED=0
  local p
  for p in ${SRCR_CHECK_PASS[@]+"${SRCR_CHECK_PASS[@]}"}; do
    ((p == 1)) && ((++SRCR_PASSED))
  done
  if ((${SRCR_FORCE_FAIL:-0} == 1)); then
    SRCR_OVERALL="FAIL"
  elif ((SRCR_PASSED == SRCR_TOTAL)); then
    SRCR_OVERALL="PASS"
  elif ((SRCR_PASSED >= SRCR_TOTAL - 1)); then
    SRCR_OVERALL="WARN"
  else
    SRCR_OVERALL="FAIL"
  fi
}

# @description Text report / Текстовый отчёт
_srcr_render_text() {
  local i marker
  printf '%.0s=' {1..72}
  printf "\nSKILL REVIEW CHECKLIST RUNNER (per Matt Pocock's write-a-skill)\n"
  printf 'Folder: %s\n' "${SRCR_FOLDER}"
  printf '%.0s=' {1..72}
  printf '\n\nChecks: %s / %s passed\n\n' "${SRCR_PASSED}" "${SRCR_TOTAL}"
  for i in "${!SRCR_CHECK_RULES[@]}"; do
    if ((${SRCR_CHECK_PASS[${i}]} == 1)); then marker="[x]"; else marker="[ ]"; fi
    printf '  %s %s\n' "${marker}" "${SRCR_CHECK_RULES[${i}]}"
    printf '        %s\n' "${SRCR_CHECK_DETAILS[${i}]}"
  done
  printf '\n'
  printf '%.0s-' {1..72}
  printf '\nVerdict: %s\n\n' "${SRCR_OVERALL}"
  printf "Reference: Matt Pocock's 6-item review checklist from write-a-skill (MIT).\n"
}

# @description JSON report / JSON-отчёт
_srcr_render_json() {
  local i bool
  printf '{\n'
  printf '  "folder": "%s",\n' "$(_srcr_json_escape "${SRCR_FOLDER}")"
  if [[ -n ${SRCR_SKILL_MD} ]]; then
    printf '  "skill_md": "%s",\n' "$(_srcr_json_escape "${SRCR_SKILL_MD}")"
  fi
  printf '  "checks": ['
  for i in "${!SRCR_CHECK_RULES[@]}"; do
    ((i > 0)) && printf ','
    bool="false"
    ((${SRCR_CHECK_PASS[${i}]} == 1)) && bool="true"
    printf '\n    {\n'
    printf '      "rule": "%s",\n' "$(_srcr_json_escape "${SRCR_CHECK_RULES[${i}]}")"
    printf '      "pass": %s,\n' "${bool}"
    printf '      "detail": "%s"\n' \
      "$(_srcr_json_escape "${SRCR_CHECK_DETAILS[${i}]}")"
    printf '    }'
  done
  ((${#SRCR_CHECK_RULES[@]} > 0)) && printf '\n  '
  printf '],\n'
  printf '  "passed": %s,\n' "${SRCR_PASSED}"
  printf '  "total": %s,\n' "${SRCR_TOTAL}"
  printf '  "overall": "%s"\n' "${SRCR_OVERALL}"
  printf '}\n'
}

# =============================================================================
# CLI
# =============================================================================

_srcr_usage() {
  cat <<'HELP'
Usage: skill_review_checklist_runner.sh [path/to/skill-folder/] [--output text|json]

Run Matt Pocock's 6-item review checklist on a skill folder.
Exit code: 0 on PASS, 1 on WARN/FAIL or bad input.
With no path, validates this skill's own folder (embedded sample).
HELP
}

srcr_main() {
  local path=""
  local output="text"

  while (($# > 0)); do
    case $1 in
      --output) output=${2:?--output requires a value}; shift 2 ;;
      --output=*) output=${1#*=}; shift ;;
      -h | --help) _srcr_usage; return 0 ;;
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

  # Embedded sample: this skill's own folder / встроенный образец: свой каталог
  local folder=${path}
  if [[ -z ${folder} ]]; then
    folder="$(cd -- "${__script_dir}/.." && pwd -P)"
  fi

  if [[ ! -d ${folder} ]]; then
    log::error "not a directory: ${folder}"
    return 1
  fi

  srcr_analyze "${folder}"
  _srcr_summarize

  if [[ ${output} == json ]]; then
    _srcr_render_json
  else
    _srcr_render_text
  fi

  [[ ${SRCR_OVERALL} == "PASS" ]]
}

srcr_main "$@"
