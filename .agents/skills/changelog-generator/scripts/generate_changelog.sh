#!/usr/bin/env bash
#
# generate_changelog.sh — generate changelog entries from Conventional Commits
# generate_changelog.sh — генерация записей changelog из Conventional Commits
#
# Input sources (priority order):
# Источники входных данных (по приоритету):
#   1) --input file with one commit subject per line / файл с темами (одна на строку)
#   2) stdin commit subjects / темы коммитов из stdin
#   3) git log from --from-tag/--to-tag or --from-ref/--to-ref
#
# Outputs markdown or JSON and can prepend into CHANGELOG.md.
# Выводит markdown или JSON и умеет дописывать запись в начало CHANGELOG.md.
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

# @global COMMIT_RE — Conventional Commits parse regex: type, scope, "!", summary
# @global COMMIT_RE — регекс разбора Conventional Commits: тип, scope, "!", тема (категория: constant)
readonly COMMIT_RE='^(feat|fix|perf|refactor|docs|test|build|ci|chore|security|deprecated|remove)(\(([^)]+)\))?(!)?:[[:space:]]+(.+)$'

# CLI options (mutable state) / Опции командной строки (изменяемое состояние)
opt_input=""
opt_from_tag=""
opt_to_tag=""
opt_from_ref=""
opt_to_ref=""
opt_next_version="Unreleased"
opt_date="$(date +%F)"
opt_format="markdown"
opt_write=""

# Parsed entry state / Разобранное состояние записи
declare -a section_security=() section_added=() section_changed=()
declare -a section_deprecated=() section_removed=() section_fixed=()
declare -a breaking_changes=()
declare -i parsed_count=0 has_breaking=0 has_feat=0
bump="patch"
entry_md=""

# Show usage help / Показать справку
usage() {
  cat <<'HELP'
Usage: generate_changelog.sh [OPTIONS]

Generate changelog from conventional commits.

Options:
  --input FILE        Text file with one commit subject per line
  --from-tag TAG      Git tag start (exclusive)
  --to-tag TAG        Git tag end (inclusive)
  --from-ref REF      Git ref start (exclusive)
  --to-ref REF        Git ref end (inclusive)
  --next-version VER  Version label for the generated entry (default: Unreleased)
  --date DATE         Release date, YYYY-MM-DD (default: today)
  --format FORMAT     Output format: markdown (default) or json
  --write FILE        Prepend generated markdown entry into this changelog file
  -h, --help          Show this help

Input priority: --input file, then stdin, then git range flags.
Приоритет входа: файл --input, затем stdin, затем git-флаги диапазона.
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
      --input=*)       opt_input="${1#*=}"; shift ;;
      --from-tag)
        (( $# >= 2 )) || cli_error "option --from-tag requires an argument"
        opt_from_tag="$2"; shift 2 ;;
      --from-tag=*)    opt_from_tag="${1#*=}"; shift ;;
      --to-tag)
        (( $# >= 2 )) || cli_error "option --to-tag requires an argument"
        opt_to_tag="$2"; shift 2 ;;
      --to-tag=*)      opt_to_tag="${1#*=}"; shift ;;
      --from-ref)
        (( $# >= 2 )) || cli_error "option --from-ref requires an argument"
        opt_from_ref="$2"; shift 2 ;;
      --from-ref=*)    opt_from_ref="${1#*=}"; shift ;;
      --to-ref)
        (( $# >= 2 )) || cli_error "option --to-ref requires an argument"
        opt_to_ref="$2"; shift 2 ;;
      --to-ref=*)      opt_to_ref="${1#*=}"; shift ;;
      --next-version)
        (( $# >= 2 )) || cli_error "option --next-version requires an argument"
        opt_next_version="$2"; shift 2 ;;
      --next-version=*) opt_next_version="${1#*=}"; shift ;;
      --date)
        (( $# >= 2 )) || cli_error "option --date requires an argument"
        opt_date="$2"; shift 2 ;;
      --date=*)        opt_date="${1#*=}"; shift ;;
      --format)
        (( $# >= 2 )) || cli_error "option --format requires an argument"
        opt_format="$2"; shift 2 ;;
      --format=*)      opt_format="${1#*=}"; shift ;;
      --write)
        (( $# >= 2 )) || cli_error "option --write requires an argument"
        opt_write="$2"; shift 2 ;;
      --write=*)       opt_write="${1#*=}"; shift ;;
      -h|--help)       usage; exit 0 ;;
      --)              shift; break ;;
      -*)              cli_error "unrecognized option: $1" ;;
      *)               cli_error "unexpected argument: $1" ;;
    esac
  done
  if [[ "${opt_format}" != "markdown" && "${opt_format}" != "json" ]]; then
    cli_error "invalid --format choice: '${opt_format}' (choose from: markdown, json)"
  fi
}

# Read commit subjects from a git range into the output array.
# Прочитать темы коммитов из git-диапазона в выходной массив.
# Args:
#   $1: range start (exclusive, may be empty) / начало диапазона (может быть пустым)
#   $2: range end (inclusive) / конец диапазона
#   $3: nameref of the output array / nameref выходного массива
lines_from_git() {
    local -r start="$1" end="$2"
    local -n __arr_git_out="$3"
    local range_spec="${end}"
    if [[ -n "${start}" ]]; then range_spec="${start}..${end}"; fi
    local git_out line
    if ! git_out="$(git log "${range_spec}" --pretty=format:%s --no-merges 2>&1)"; then
      cli_error "git log failed for range '${range_spec}': ${git_out}"
    fi
    while IFS= read -r line; do
      line="$(trim "${line}")"
      if [[ -n "${line}" ]]; then __arr_git_out+=("${line}"); fi
    done <<< "${git_out}"
}

# Load commit subjects from the first available source into the output array.
# Загрузить темы коммитов из первого доступного источника в выходной массив.
# Args:
#   $1: nameref of the output array / nameref выходного массива
load_commits() {
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

  # 3) git range: tags take precedence over refs / теги приоритетнее ref'ов
  if [[ -n "${opt_from_tag}" || -n "${opt_to_tag}" ]]; then
    if [[ -z "${opt_to_tag}" ]]; then
      cli_error "--to-tag is required when using tag range."
    fi
    lines_from_git "${opt_from_tag}" "${opt_to_tag}" __arr_load_out
    if (( ${#__arr_load_out[@]} > 0 )); then return 0; fi
  elif [[ -n "${opt_from_ref}" || -n "${opt_to_ref}" ]]; then
    if [[ -z "${opt_to_ref}" ]]; then
      cli_error "--to-ref is required when using ref range."
    fi
    lines_from_git "${opt_from_ref}" "${opt_to_ref}" __arr_load_out
    if (( ${#__arr_load_out[@]} > 0 )); then return 0; fi
  fi

  cli_error "No commit input found. Use --input, stdin, or git range flags."
}

# Map a commit type to a Keep a Changelog section (empty = not user-facing).
# Сопоставить тип коммита секции Keep a Changelog (пусто = не для пользователей).
map_section() {
  case "$1" in
    feat)             printf 'Added' ;;
    fix)              printf 'Fixed' ;;
    perf|refactor)    printf 'Changed' ;;
    security)         printf 'Security' ;;
    deprecated)       printf 'Deprecated' ;;
    remove)           printf 'Removed' ;;
    *)                return 1 ;;
  esac
}

# Parse subjects into sections and the breaking list (COMMIT_RE semantics).
# Разобрать темы по секциям и в список ломающих изменений (семантика COMMIT_RE).
# Args:
#   $1: nameref of the subjects array / nameref массива тем
parse_commits() {
  local -n __arr_parse_in="$1"
  local line ctype scope summary section
  for line in ${__arr_parse_in[@]+"${__arr_parse_in[@]}"}; do
    if [[ ! "${line}" =~ ${COMMIT_RE} ]]; then
      continue
    fi
    ctype="${BASH_REMATCH[1]}"
    scope="${BASH_REMATCH[3]}"
    summary="${BASH_REMATCH[5]}"
    parsed_count+=1

    # Breaking: "!" marker or "BREAKING CHANGE" in the subject
    # Ломающее: маркер "!" или "BREAKING CHANGE" в теме
    if [[ -n "${BASH_REMATCH[4]}" || "${line}" == *"BREAKING CHANGE"* ]]; then
      has_breaking=1
      breaking_changes+=("${summary}")
    fi
    if [[ "${ctype}" == "feat" ]]; then has_feat=1; fi

    if section="$(map_section "${ctype}")"; then
      local item="${summary}"
      if [[ -n "${scope}" ]]; then item="${scope}: ${summary}"; fi
      case "${section}" in
        Security)   section_security+=("${item}") ;;
        Added)      section_added+=("${item}") ;;
        Changed)    section_changed+=("${item}") ;;
        Deprecated) section_deprecated+=("${item}") ;;
        Removed)    section_removed+=("${item}") ;;
        Fixed)      section_fixed+=("${item}") ;;
      esac
    fi
  done
}

# SemVer bump: any breaking -> major, else any feat -> minor, else patch.
# SemVer-бамп: любое ломающее -> major, иначе любой feat -> minor, иначе patch.
determine_bump() {
  if (( has_breaking )); then
    bump="major"
  elif (( has_feat )); then
    bump="minor"
  else
    bump="patch"
  fi
}

# Render the entry as markdown into entry_md (ends with a single newline).
# Отрисовать запись в markdown в entry_md (завершается одним переводом строки).
render_markdown() {
  local out="## [${opt_next_version}] - ${opt_date}"$'\n\n'
  local item
  if (( ${#breaking_changes[@]} > 0 )); then
    out+='### Breaking'$'\n'
    for item in "${breaking_changes[@]}"; do
      out+="- ${item}"$'\n'
    done
    out+=$'\n'
  fi
  local -a ordered=(Security Added Changed Deprecated Removed Fixed)
  local name
  for name in "${ordered[@]}"; do
    local -n __arr_section="section_${name,,}"
    if (( ${#__arr_section[@]} == 0 )); then continue; fi
    out+="### ${name}"$'\n'
    for item in "${__arr_section[@]}"; do
      out+="- ${item}"$'\n'
    done
    out+=$'\n'
  done
  out+="<!-- recommended-semver-bump: ${bump} -->"$'\n'
  entry_md="${out}"
}

# Render one JSON string list at the given indent (helper for render_json).
# Отрисовать JSON-список строк с заданным отступом (помощник render_json).
# Args:
#   $1: indent / отступ
#   $2: nameref of the items array / nameref массива элементов
json_string_list() {
  local -r indent="$1"
  local -n __arr_items="$2"
  if (( ${#__arr_items[@]} == 0 )); then
    printf '[]'
    return 0
  fi
  printf '[\n'
  local -i i last=$(( ${#__arr_items[@]} - 1 ))
  for (( i = 0; i <= last; i++ )); do
    local comma=','
    if (( i == last )); then comma=''; fi
    printf '%s  "%s"%s\n' "${indent}" "$(json_escape "${__arr_items[$i]}")" "${comma}"
  done
  printf '%s]' "${indent}"
}

# JSON entry (shape of Python json.dumps(asdict(entry), indent=2);
# non-ASCII is emitted as raw UTF-8, not XXXX escapes).
# JSON-запись (форма Python json.dumps(asdict(entry), indent=2);
# не-ASCII выводится как UTF-8, а не как XXXX).
render_json() {
  printf '{\n'
  printf '  "version": "%s",\n' "$(json_escape "${opt_next_version}")"
  printf '  "release_date": "%s",\n' "$(json_escape "${opt_date}")"
  printf '  "sections": '
  local -a ordered=(Security Added Changed Deprecated Removed Fixed)
  local -i non_empty=0 name_i
  for name_i in "${!ordered[@]}"; do
    local -n __arr_probe="section_${ordered[$name_i],,}"
    if (( ${#__arr_probe[@]} > 0 )); then non_empty+=1; fi
  done
  if (( non_empty == 0 )); then
    printf '{},\n'
  else
    printf '{\n'
    local -i seen=0
    for name_i in "${!ordered[@]}"; do
      local -n __arr_sec="section_${ordered[$name_i],,}"
      if (( ${#__arr_sec[@]} == 0 )); then continue; fi
      seen+=1
      local comma=','
      if (( seen == non_empty )); then comma=''; fi
      printf '    "%s": ' "${ordered[$name_i]}"
      json_string_list '    ' __arr_sec
      printf '%s\n' "${comma}"
    done
    printf '  },\n'
  fi
  printf '  "breaking_changes": '
  json_string_list '  ' breaking_changes
  printf ',\n'
  printf '  "bump": "%s"\n' "${bump}"
  printf '}\n'
}

# Prepend the markdown entry into a changelog file, creating a safe header
# scaffold for a missing file (same rules as the Python prepend_changelog).
# Дописать markdown-запись в начало changelog-файла; для отсутствующего файла
# создаётся безопасный каркас заголовка (те же правила, что у Python-версии).
# Args:
#   $1: changelog path / путь к changelog
#   $2: entry markdown (ends with a newline) / markdown записи (с \n на конце)
prepend_changelog() {
  local -r path="$1" entry="$2"
  local original
  if [[ -f "${path}" ]]; then
    # $(...) strips trailing newlines; the sentinel keeps content byte-exact
    # $(...) съедает хвостовые переводы строк; страж сохраняет их побайтово
    original="$(cat -- "${path}"; printf 'x')"
    original="${original:0:${#original}-1}"
  else
    original=$'# Changelog\n\nAll notable changes to this project will be documented in this file.\n\n'
  fi

  local combined
  if [[ "${original}" == "# Changelog"* ]]; then
    local head tail
    if [[ "${original}" == *$'\n'* ]]; then
      head="${original%%$'\n'*}"$'\n'
      tail="${original#*$'\n'}"
    else
      head=""
      tail="${original}"
    fi
    while [[ "${tail}" == $'\n'* ]]; do tail="${tail:1}"; done
    combined="${head}"$'\n'"${entry}"$'\n'"${tail}"
  else
    combined=$'# Changelog\n\n'"${entry}"$'\n'"${original}"
  fi
  printf '%s' "${combined}" > "${path}"
}

main() {
  parse_args "$@"
  # lines is filled and consumed via namerefs (load_commits, parse_commits)
  # lines заполняется и читается через nameref (load_commits, parse_commits)
  # shellcheck disable=SC2034
  local -a lines=()
  load_commits lines
  parse_commits lines
  if (( parsed_count == 0 )); then
    cli_error "No valid conventional commit messages found in input."
  fi
  determine_bump
  render_markdown

  # --write always prepends the markdown rendering (as in the Python version)
  # --write всегда дописывает markdown-рендер (как в Python-версии)
  if [[ "${opt_format}" == "json" ]]; then
    render_json
    if [[ -n "${opt_write}" ]]; then
      prepend_changelog "${opt_write}" "${entry_md}"
    fi
  else
    printf '%s' "${entry_md}"
    if [[ -n "${opt_write}" ]]; then
      prepend_changelog "${opt_write}" "${entry_md}"
    fi
  fi
  exit 0
}

main "$@"
