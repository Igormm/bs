#!/usr/bin/env bash
# shellcheck shell=bash
#
# skill_structure_validator.sh — Validate a skill folder structure against
# Matt Pocock's write-a-skill pattern.
# Проверка структуры каталога скилла по паттерну Matt Pocock.
#
# Checks / Проверки:
#   1. SKILL.md present at folder root / SKILL.md в корне каталога
#   2. SKILL.md <= --max-lines (default 100)
#   3. Over-ceiling SKILL.md requires reference files / при превышении лимита
#      нужны файлы-справочники (*.md в корне или references//examples/*.md)
#   4. References one level deep / справочники не глубже одного уровня
#   5. No circular cross-references / без циклических ссылок между .md
#   6. scripts/ folder (informational / информационно, всегда PASS)
#
# Exit code / Код выхода: 0 on PASS, 1 on WARN/FAIL or bad input.
#
# Usage:
#   skill_structure_validator.sh [path/to/skill-folder/] [--output text|json]
#                                [--max-lines N]

set -euo pipefail

# BS bootstrap / бутстрап BS (repo root is 4 levels up from this script)
__script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
export BS_SILENT=1
# shellcheck disable=SC1091
source "${__script_dir}/../../../../bootstrap/init.sh"

# @global SSV_DEFAULT_MAX_LINES — Constant: SKILL.md line ceiling (category: constant)
# @global SSV_DEFAULT_MAX_LINES — Константа: потолок строк SKILL.md (категория: constant)
readonly SSV_DEFAULT_MAX_LINES=100

# Check results: parallel arrays / результаты проверок: параллельные массивы
declare -a SSV_CHECK_RULES=()
declare -a SSV_CHECK_PASS=()
declare -a SSV_CHECK_DETAILS=()

# Found reference files / найденные файлы-справочники
declare -a SSV_REF_FILES=()

# =============================================================================
# Helpers / Вспомогательные функции
# =============================================================================

# @description JSON-escape a string / Экранировать строку для JSON
_ssv_json_escape() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\t'/\\t}
  s=${s//$'\r'/\\r}
  s=${s//$'\n'/\\n}
  printf '%s' "${s}"
}

# @description Textual path normalization (., ..) without touching the FS
# @description Текстовая нормализация пути (., ..) без обращения к ФС
_ssv_normpath() {
  local -r input=$1
  local abs=0
  [[ ${input:0:1} == / ]] && abs=1
  local -a parts=() stack=()
  local part out=""
  IFS='/' read -r -a parts <<< "${input}"
  for part in ${parts[@]+"${parts[@]}"}; do
    case "${part}" in
      "" | .) ;;
      ..)
        if ((${#stack[@]} > 0)) && [[ ${stack[-1]} != ".." ]]; then
          unset 'stack[-1]'
        else
          stack+=("..")
        fi
        ;;
      *) stack+=("${part}") ;;
    esac
  done
  for part in ${stack[@]+"${stack[@]}"}; do
    out+="/${part}"
  done
  if ((abs)); then
    [[ -z ${out} ]] && out="/"
  else
    out=${out#/}
    [[ -z ${out} ]] && out="."
  fi
  printf '%s' "${out}"
}

# @description Extract local .md link targets from a file (one per line)
# @description Извлечь локальные ссылки на .md из файла (по одной на строку)
_ssv_md_links() {
  local -r file=$1
  grep -oE '\[[^]]+\]\([^)]*\.md(#[^)]*)?\)' -- "${file}" 2>/dev/null \
    | sed -E 's/^\[[^]]*\]\(//; s/\)$//; s/#.*$//' \
    | grep -v '^http' \
    || true
}

# @description Append a check result / Добавить результат проверки
# @param $1 Rule name / имя правила
# @param $2 Pass flag: 1 = pass, 0 = fail / признак: 1 = прошло, 0 = упало
# @param $3 Detail text / текст детали
_ssv_add_check() {
  SSV_CHECK_RULES+=("$1")
  SSV_CHECK_PASS+=("$2")
  SSV_CHECK_DETAILS+=("$3")
}

# @description Python-style list repr of paths: ['a', 'b']
# @description Список путей в стиле Python: ['a', 'b']
_ssv_py_list() {
  local out="[" first=1 item
  for item in "$@"; do
    ((first)) || out+=", "
    out+="'${item}'"
    first=0
  done
  printf '%s]' "${out}"
}

# =============================================================================
# Analysis / Анализ
# =============================================================================

# @description Run all structure checks on FOLDER
# @description Выполнить все проверки структуры для КАТАЛОГА
# @param $1 Skill folder / каталог скилла
# @param $2 Max SKILL.md lines / потолок строк SKILL.md
ssv_analyze() {
  local folder=$1
  local -r max_lines=$2

  # rstrip("/") equivalent / аналог rstrip("/")
  while [[ ${folder} == */ && ${folder} != / ]]; do
    folder=${folder%/}
  done
  SSV_FOLDER=${folder}

  # Check 1: SKILL.md present / проверка 1: наличие SKILL.md
  local skill_md=""
  [[ -f ${folder}/SKILL.md ]] && skill_md="${folder}/SKILL.md"
  if [[ -z ${skill_md} ]]; then
    _ssv_add_check "skill_md_present" 0 "SKILL.md not found at ${folder}"
    SSV_SKILL_MD=""
    SSV_SKILL_MD_LINES=0
    # Python original hardcodes FAIL here / оригинал жёстко ставит FAIL
    SSV_FORCE_FAIL=1
    return 0
  fi
  _ssv_add_check "skill_md_present" 1 "${skill_md}"
  SSV_SKILL_MD=${skill_md}

  # Check 2: line count / проверка 2: число строк (awk считает как Python)
  local lines
  lines=$(awk 'END {print NR}' "${skill_md}")
  SSV_SKILL_MD_LINES=${lines}
  local line_pass=0
  ((lines <= max_lines)) && line_pass=1
  _ssv_add_check "skill_md_line_count" "${line_pass}" \
    "${lines} lines (limit ${max_lines})"

  # Reference files: *.md at root (except SKILL.md) + one level in
  # references//examples/ / файлы-справочники: *.md в корне + 1 уровень
  SSV_REF_FILES=()
  local entry
  while IFS= read -r entry; do
    [[ -f ${entry} ]] && SSV_REF_FILES+=("${entry}")
  done < <(find "${folder}" -mindepth 1 -maxdepth 1 -type f -name '*.md' \
    ! -name 'SKILL.md' | sort)
  local sub
  for sub in references examples; do
    if [[ -d ${folder}/${sub} ]]; then
      while IFS= read -r entry; do
        SSV_REF_FILES+=("${entry}")
      done < <(find "${folder}/${sub}" -mindepth 1 -maxdepth 1 -type f \
        -name '*.md' | sort)
    fi
  done

  # Check 3: refs required only when over ceiling
  # проверка 3: справочники обязательны лишь при превышении потолка
  if ((line_pass == 0)); then
    if ((${#SSV_REF_FILES[@]} > 0)); then
      _ssv_add_check "reference_files_when_split_needed" 1 \
        "Found ${#SSV_REF_FILES[@]} reference file(s)"
    else
      _ssv_add_check "reference_files_when_split_needed" 0 \
        "SKILL.md exceeds ceiling but no reference files present"
    fi
  else
    _ssv_add_check "reference_files_when_split_needed" 1 \
      "SKILL.md under ceiling; reference split not required"
  fi

  # Check 4: nothing nested below references/ / проверка 4: нет вложенности
  local -a deeper=()
  if [[ -d ${folder}/references ]]; then
    while IFS= read -r entry; do
      deeper+=("${entry}")
    done < <(find "${folder}/references" -mindepth 2 -type f -name '*.md' \
      | sort)
  fi
  if ((${#deeper[@]} > 0)); then
    _ssv_add_check "references_one_level_deep" 0 \
      "Found nested ref files (violations): $(_ssv_py_list "${deeper[@]}")"
  else
    _ssv_add_check "references_one_level_deep" 1 \
      "All references are one level deep (or at root)"
  fi

  # Check 5: circular cross-references / проверка 5: циклические ссылки
  local -a all_md=("${skill_md}" ${SSV_REF_FILES[@]+"${SSV_REF_FILES[@]}"})
  local -A links_of=()
  local f link target
  for f in ${all_md[@]+"${all_md[@]}"}; do
    links_of["${f}"]=""
    while IFS= read -r link; do
      [[ -z ${link} ]] && continue
      target=$(_ssv_normpath "$(dirname -- "${f}")/${link}")
      # Keep only links resolving to known files / только ссылки на наши файлы
      local known=1 g
      for g in ${all_md[@]+"${all_md[@]}"}; do
        [[ ${g} == "${target}" ]] && known=0 && break
      done
      ((known == 0)) && links_of["${f}"]+="${target}"$'\n'
    done < <(_ssv_md_links "${f}")
  done

  local -a circular=()
  local -A seen_pairs=()
  local a b pair key_a key_b
  for a in ${all_md[@]+"${all_md[@]}"}; do
    while IFS= read -r b; do
      [[ -z ${b} ]] && continue
      # Mutual link? / взаимная ссылка?
      if printf '%s' "${links_of[${b}]:-}" | grep -qxF -- "${a}"; then
        key_a=${a}
        key_b=${b}
        [[ ${key_a} > ${key_b} ]] && key_a=${b} && key_b=${a}
        pair="${key_a}|${key_b}"
        [[ -n ${seen_pairs[${pair}]:-} ]] && continue
        seen_pairs["${pair}"]=1
        circular+=("('${a}', '${b}')")
      fi
    done <<< "${links_of[${a}]}"
  done
  if ((${#circular[@]} > 0)); then
    local joined=""
    local c
    for c in "${circular[@]}"; do
      [[ -n ${joined} ]] && joined+=", "
      joined+="${c}"
    done
    _ssv_add_check "no_circular_references" 0 \
      "Circular refs detected: [${joined}]"
  else
    _ssv_add_check "no_circular_references" 1 \
      "No circular references between markdown files"
  fi

  # Check 6: scripts/ folder (always passes / всегда проходит)
  if [[ -d ${folder}/scripts ]]; then
    _ssv_add_check "scripts_folder_present" 1 "scripts/ folder exists"
  else
    _ssv_add_check "scripts_folder_present" 1 \
      "No scripts/ folder (optional per Matt's pattern)"
  fi
}

# =============================================================================
# Rendering / Вывод
# =============================================================================

# @description Compute passed/total/overall into SSV_PASSED/SSV_TOTAL/SSV_OVERALL
# @description Вычислить passed/total/overall в SSV_PASSED/SSV_TOTAL/SSV_OVERALL
_ssv_summarize() {
  SSV_TOTAL=${#SSV_CHECK_RULES[@]}
  SSV_PASSED=0
  local p
  for p in ${SSV_CHECK_PASS[@]+"${SSV_CHECK_PASS[@]}"}; do
    ((p == 1)) && ((++SSV_PASSED))
  done
  if ((${SSV_FORCE_FAIL:-0} == 1)); then
    SSV_OVERALL="FAIL"
  elif ((SSV_PASSED == SSV_TOTAL)); then
    SSV_OVERALL="PASS"
  elif ((SSV_PASSED >= SSV_TOTAL - 1)); then
    SSV_OVERALL="WARN"
  else
    SSV_OVERALL="FAIL"
  fi
}

# @description Text report / Текстовый отчёт
_ssv_render_text() {
  local i rule detail marker
  printf '%.0s=' {1..72}
  printf '\nSKILL STRUCTURE VALIDATOR\n'
  printf 'Folder: %s\n' "${SSV_FOLDER}"
  printf 'Max-lines threshold: %s\n' "${SSV_MAX_LINES}"
  printf '%.0s=' {1..72}
  printf '\n\n'
  printf 'SKILL.md: %s  (%s lines)\n' "${SSV_SKILL_MD:-}" "${SSV_SKILL_MD_LINES:-0}"
  printf 'Reference files: %s\n' "${#SSV_REF_FILES[@]}"
  printf '\n'
  printf '%.0s-' {1..72}
  printf '\nChecks: %s / %s passed\n\n' "${SSV_PASSED}" "${SSV_TOTAL}"
  for i in "${!SSV_CHECK_RULES[@]}"; do
    rule=${SSV_CHECK_RULES[${i}]}
    detail=${SSV_CHECK_DETAILS[${i}]}
    if ((${SSV_CHECK_PASS[${i}]} == 1)); then
      marker="PASS"
    else
      marker="FAIL"
    fi
    printf '  [%s] %-35s  %s\n' "${marker}" "${rule}" "${detail}"
  done
  printf '\n'
  printf '%.0s-' {1..72}
  printf '\nVerdict: %s\n' "${SSV_OVERALL}"
}

# @description JSON report / JSON-отчёт
_ssv_render_json() {
  local i
  printf '{\n'
  printf '  "folder": "%s",\n' "$(_ssv_json_escape "${SSV_FOLDER}")"
  printf '  "max_lines_threshold": %s,\n' "${SSV_MAX_LINES}"
  printf '  "skill_md": "%s",\n' "$(_ssv_json_escape "${SSV_SKILL_MD:-}")"
  printf '  "skill_md_lines": %s,\n' "${SSV_SKILL_MD_LINES:-0}"
  printf '  "reference_files": ['
  for i in "${!SSV_REF_FILES[@]}"; do
    ((i > 0)) && printf ','
    printf '\n    "%s"' "$(_ssv_json_escape "${SSV_REF_FILES[${i}]}")"
  done
  ((${#SSV_REF_FILES[@]} > 0)) && printf '\n  '
  printf '],\n'
  printf '  "checks": ['
  for i in "${!SSV_CHECK_RULES[@]}"; do
    ((i > 0)) && printf ','
    local bool="false"
    ((${SSV_CHECK_PASS[${i}]} == 1)) && bool="true"
    printf '\n    {\n'
    printf '      "rule": "%s",\n' "$(_ssv_json_escape "${SSV_CHECK_RULES[${i}]}")"
    printf '      "pass": %s,\n' "${bool}"
    printf '      "detail": "%s"\n' \
      "$(_ssv_json_escape "${SSV_CHECK_DETAILS[${i}]}")"
    printf '    }'
  done
  ((${#SSV_CHECK_RULES[@]} > 0)) && printf '\n  '
  printf '],\n'
  printf '  "passed": %s,\n' "${SSV_PASSED}"
  printf '  "total": %s,\n' "${SSV_TOTAL}"
  printf '  "overall": "%s"\n' "${SSV_OVERALL}"
  printf '}\n'
}

# =============================================================================
# CLI
# =============================================================================

_ssv_usage() {
  cat <<'HELP'
Usage: skill_structure_validator.sh [path/to/skill-folder/] [options]

Validate skill folder structure per Matt Pocock's write-a-skill pattern.

Options:
  --output text|json   Output format (default: text)
  --max-lines N        SKILL.md line ceiling (default: 100)
  -h, --help           Show this help

Exit code: 0 on PASS, 1 on WARN/FAIL or bad input.
With no path, validates this skill's own folder (embedded sample).
HELP
}

ssv_main() {
  local path=""
  local output="text"
  local max_lines=${SSV_DEFAULT_MAX_LINES}

  while (($# > 0)); do
    case $1 in
      --output) output=${2:?--output requires a value}; shift 2 ;;
      --output=*) output=${1#*=}; shift ;;
      --max-lines) max_lines=${2:?--max-lines requires a value}; shift 2 ;;
      --max-lines=*) max_lines=${1#*=}; shift ;;
      -h | --help) _ssv_usage; return 0 ;;
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
  if [[ ! ${max_lines} =~ ^[0-9]+$ ]]; then
    log::error "invalid --max-lines: ${max_lines} (expected integer)"
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

  SSV_MAX_LINES=${max_lines}
  SSV_SKILL_MD=""
  SSV_SKILL_MD_LINES=0
  SSV_REF_FILES=()
  ssv_analyze "${folder}" "${max_lines}"
  _ssv_summarize

  if [[ ${output} == json ]]; then
    _ssv_render_json
  else
    _ssv_render_text
  fi

  [[ ${SSV_OVERALL} == "PASS" ]]
}

ssv_main "$@"
