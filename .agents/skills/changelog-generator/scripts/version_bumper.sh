#!/usr/bin/env bash
#
# version_bumper.sh — recommend the next semantic version from Conventional Commits
# version_bumper.sh — рекомендация следующей semver-версии по Conventional Commits
#
# Analyzes commits since the last tag to determine the correct version bump
# (major/minor/patch) based on conventional commits. Handles pre-release
# versions (alpha, beta, rc) and generates version bump commands for various
# package files.
# Анализирует коммиты с последнего тега и определяет нужный бамп версии
# (major/minor/patch) по conventional commits. Поддерживает предрелизы
# (alpha, beta, rc) и генерирует команды бампа для разных пакетных файлов.
#
# Input: current version + commit list JSON or git log
# Вход: текущая версия + список коммитов в JSON или git log
# Output: recommended new version + bump commands + updated file snippets
# Выход: рекомендуемая версия + команды бампа + обновлённые сниппеты файлов
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

# CLI options (mutable state) / Опции командной строки (изменяемое состояние)
opt_current_version=""
opt_input=""
opt_input_format="git-log"
opt_prerelease=""
opt_output_format="text"
opt_output=""
opt_include_commands=0
opt_include_files=0
opt_custom_rules=""
opt_ignore_types=""
opt_analysis=0

# Parsed commits state / Состояние разобранных коммитов
declare -a C_TYPE=() C_SCOPE=() C_DESC=() C_BREAKING=() C_BREAKING_DESC=() C_HASH=()

# Custom type->bump rules and ignored types / Кастомные правила тип->бамп и игнорируемые типы
declare -A CUSTOM_RULES=()
declare -a IGNORE_TYPES=(test ci build chore docs style)

# Current version (V_*) and recommended version (NV_*) state
# Текущая версия (V_*) и рекомендуемая версия (NV_*)
V_MAJOR=0 V_MINOR=0 V_PATCH=0 V_PRE_TYPE="" V_PRE_NUM="" V_ERRMSG=""
NV_MAJOR=0 NV_MINOR=0 NV_PATCH=0 NV_PRE_TYPE="" NV_PRE_NUM=""
NV_STR="" NV_STR_V=""
BUMP_TYPE="none"

# Analysis buckets / Корзины анализа
A_TOTAL=0
declare -a A_BREAKING_IDX=() A_FEATURES_IDX=() A_FIXES_IDX=() A_IGNORED_IDX=()
declare -A BY_TYPE=()
declare -a BY_TYPE_ORDER=()

# Bump commands and file update snippets (values are newline-joined lines)
# Команды бампа и сниппеты обновления файлов (значения — строки, склеенные \n)
declare -a CMD_ORDER=() FILE_ORDER=()
declare -A BUMP_COMMANDS=() FILE_UPDATES=()

output_text=""

# Show usage help / Показать справку
usage() {
  cat <<'HELP'
Usage: version_bumper.sh --current-version VER [OPTIONS]

Determine version bump based on conventional commits.

Options:
  -c, --current-version VER   Current version, e.g. 1.2.3 or v1.2.3 (required)
  -i, --input FILE            Input file with commits (default: stdin)
      --input-format FORMAT   Input format: git-log (default) or json
  -p, --prerelease TYPE       Generate pre-release version: alpha, beta or rc
  -f, --output-format FORMAT  Output format: text (default), json or commands
  -o, --output FILE           Output file (default: stdout)
      --include-commands      Include bump commands in output
      --include-files         Include file update snippets
      --custom-rules JSON     JSON string with custom type->bump rules
      --ignore-types CSV      Comma-separated list of types to ignore
  -a, --analysis              Include detailed commit analysis
  -h, --help                  Show this help

git-log input must be real 'git log --oneline' output (hex hashes).
Вход git-log должен быть настоящим выводом 'git log --oneline' (hex-хэши).
HELP
}

# Argument-level CLI error: message to stderr, exit 2 (like argparse)
# Ошибка уровня аргументов CLI: сообщение в stderr, выход 2 (как argparse)
arg_error() {
  log::error "$1"
  exit 2
}

# Data/parse error: message to stderr, exit 1 (like the Python main() errors)
# Ошибка данных/разбора: сообщение в stderr, выход 1 (как ошибки main() в Python)
data_error() {
  log::error "$1"
  exit 1
}

# Strip leading/trailing whitespace like Python str.strip()
# Обрезка пробельных символов по краям, как Python str.strip()
trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "${s}"
}

# Normalize a decimal integer: strip leading zeros ("008" -> "8", "00" -> "0").
# Keeps later arithmetic safe from octal interpretation.
# Нормализовать десятичное целое: убрать ведущие нули ("008" -> "8", "00" -> "0").
# Защищает последующую арифметику от восьмеричной интерпретации.
normalize_int() {
  local v="$1"
  v="${v#"${v%%[!0]*}"}"
  printf '%s' "${v:-0}"
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
      -c|--current-version)
        (( $# >= 2 )) || arg_error "option $1 requires an argument"
        opt_current_version="$2"; shift 2 ;;
      --current-version=*) opt_current_version="${1#*=}"; shift ;;
      -i|--input)
        (( $# >= 2 )) || arg_error "option $1 requires an argument"
        opt_input="$2"; shift 2 ;;
      --input=*)           opt_input="${1#*=}"; shift ;;
      --input-format)
        (( $# >= 2 )) || arg_error "option --input-format requires an argument"
        opt_input_format="$2"; shift 2 ;;
      --input-format=*)    opt_input_format="${1#*=}"; shift ;;
      -p|--prerelease)
        (( $# >= 2 )) || arg_error "option $1 requires an argument"
        opt_prerelease="$2"; shift 2 ;;
      --prerelease=*)      opt_prerelease="${1#*=}"; shift ;;
      -f|--output-format)
        (( $# >= 2 )) || arg_error "option $1 requires an argument"
        opt_output_format="$2"; shift 2 ;;
      --output-format=*)   opt_output_format="${1#*=}"; shift ;;
      -o|--output)
        (( $# >= 2 )) || arg_error "option $1 requires an argument"
        opt_output="$2"; shift 2 ;;
      --output=*)          opt_output="${1#*=}"; shift ;;
      --include-commands)  opt_include_commands=1; shift ;;
      --include-files)     opt_include_files=1; shift ;;
      --custom-rules)
        (( $# >= 2 )) || arg_error "option --custom-rules requires an argument"
        opt_custom_rules="$2"; shift 2 ;;
      --custom-rules=*)    opt_custom_rules="${1#*=}"; shift ;;
      --ignore-types)
        (( $# >= 2 )) || arg_error "option --ignore-types requires an argument"
        opt_ignore_types="$2"; shift 2 ;;
      --ignore-types=*)    opt_ignore_types="${1#*=}"; shift ;;
      -a|--analysis)       opt_analysis=1; shift ;;
      -h|--help)           usage; exit 0 ;;
      --)                  shift; break ;;
      -*)                  arg_error "unrecognized option: $1" ;;
      *)                   arg_error "unexpected argument: $1" ;;
    esac
  done
  if [[ "${opt_input_format}" != "git-log" && "${opt_input_format}" != "json" ]]; then
    arg_error "argument --input-format: invalid choice: '${opt_input_format}' (choose from: git-log, json)"
  fi
  if [[ -n "${opt_prerelease}" && "${opt_prerelease}" != "alpha" \
      && "${opt_prerelease}" != "beta" && "${opt_prerelease}" != "rc" ]]; then
    arg_error "argument --prerelease/-p: invalid choice: '${opt_prerelease}' (choose from: alpha, beta, rc)"
  fi
  if [[ "${opt_output_format}" != "text" && "${opt_output_format}" != "json" \
      && "${opt_output_format}" != "commands" ]]; then
    arg_error "argument --output-format/-f: invalid choice: '${opt_output_format}' (choose from: text, json, commands)"
  fi
}

# Parse a version string into the V_* globals: semantic version with optional
# "v" prefix and optional -alpha/-beta/-rc pre-release (Python Version.parse).
# Разобрать строку версии в глобалы V_*: semver с опциональным префиксом "v"
# и опциональным предрелизом -alpha/-beta/-rc (Python Version.parse).
# Args:
#   $1: version string / строка версии
# Returns / Возвращает: 0 on success; 1 with V_ERRMSG set on invalid input.
version_parse() {
  local v="$1"
  V_ERRMSG=""
  # Python lstrip('v'): all leading v's are stripped / lstrip('v'): все ведущие v
  while [[ "${v}" == v* ]]; do v="${v#v}"; done
  local -r re='^([0-9]+)\.([0-9]+)\.([0-9]+)(-([[:alnum:]_]+)\.?([0-9]+)?)?$'
  if [[ ! "${v}" =~ ${re} ]]; then
    V_ERRMSG="Invalid version format: $1"
    return 1
  fi
  V_MAJOR="$(normalize_int "${BASH_REMATCH[1]}")"
  V_MINOR="$(normalize_int "${BASH_REMATCH[2]}")"
  V_PATCH="$(normalize_int "${BASH_REMATCH[3]}")"
  V_PRE_TYPE=""
  V_PRE_NUM=""
  if [[ -n "${BASH_REMATCH[4]}" ]]; then
    local pre="${BASH_REMATCH[5],,}"
    case "${pre}" in
      alpha)  V_PRE_TYPE="alpha" ;;
      beta)   V_PRE_TYPE="beta" ;;
      rc)     V_PRE_TYPE="rc" ;;
      alpha*) V_PRE_TYPE="alpha" ;;
      beta*)  V_PRE_TYPE="beta" ;;
      rc*)    V_PRE_TYPE="rc" ;;
      *)
        V_ERRMSG="Unknown pre-release type: ${pre}"
        return 1
        ;;
    esac
    if [[ -n "${BASH_REMATCH[6]}" ]]; then
      V_PRE_NUM="$(normalize_int "${BASH_REMATCH[6]}")"
    elif [[ "${pre}" =~ ([0-9]+)$ ]]; then
      # combined identifier like "alpha1" / слитный идентификатор вида "alpha1"
      V_PRE_NUM="$(normalize_int "${BASH_REMATCH[1]}")"
    else
      V_PRE_NUM=1
    fi
  fi
  return 0
}

# Compute the recommended version into NV_* (same rules as Python Version.bump).
# Вычислить рекомендуемую версию в NV_* (те же правила, что у Python Version.bump).
# Args:
#   $1: bump type: none|patch|minor|major / тип бампа
#   $2: requested pre-release type or empty / запрошенный тип предрелиза или пусто
version_bump() {
  local -r bump_type="$1" pre_arg="$2"
  # bump "none" returns the current version unchanged (pre-release included)
  # бамп "none" возвращает текущую версию без изменений (включая предрелиз)
  if [[ "${bump_type}" == "none" ]]; then
    NV_MAJOR=${V_MAJOR} NV_MINOR=${V_MINOR} NV_PATCH=${V_PATCH}
    NV_PRE_TYPE="${V_PRE_TYPE}" NV_PRE_NUM="${V_PRE_NUM}"
    return 0
  fi
  local -i major=${V_MAJOR} minor=${V_MINOR} patch=${V_PATCH}
  local pre_type="" pre_num=""
  if [[ -n "${pre_arg}" ]]; then
    # explicit pre-release: bump numbers, then tag as <type>.1
    # явный предрелиз: бамп чисел, затем метка <тип>.1
    case "${bump_type}" in
      major) major+=1; minor=0; patch=0 ;;
      minor) minor+=1; patch=0 ;;
      patch) patch+=1 ;;
    esac
    pre_type="${pre_arg}"
    pre_num=1
  elif [[ -n "${V_PRE_TYPE}" ]]; then
    # already a pre-release and no --prerelease: promote to stable, numbers stay
    # уже предрелиз и нет --prerelease: повышение до стабильной, числа те же
    :
  else
    case "${bump_type}" in
      major) major+=1; minor=0; patch=0 ;;
      minor) minor+=1; patch=0 ;;
      patch) patch+=1 ;;
    esac
  fi
  NV_MAJOR=${major} NV_MINOR=${minor} NV_PATCH=${patch}
  NV_PRE_TYPE="${pre_type}" NV_PRE_NUM="${pre_num}"
}

# Render NV_* as a version string; $1=1 adds the "v" prefix.
# Отрисовать NV_* как строку версии; $1=1 добавляет префикс "v".
nv_string() {
  local base="${NV_MAJOR}.${NV_MINOR}.${NV_PATCH}"
  if [[ -n "${NV_PRE_TYPE}" ]]; then
    base+="-${NV_PRE_TYPE}"
    if [[ -n "${NV_PRE_NUM}" ]]; then base+=".${NV_PRE_NUM}"; fi
  fi
  if [[ "${1:-0}" == "1" ]]; then base="v${base}"; fi
  printf '%s' "${base}"
}

# Parse one conventional commit message and append it to the C_* arrays.
# Non-matching headers fall back to type "chore" (Python parse_message).
# Разобрать одно сообщение conventional commit и добавить в массивы C_*.
# Неподходящие заголовки получают тип "chore" (Python parse_message).
# Args:
#   $1: full message (may be multiline) / полное сообщение (может быть многострочным)
#   $2: commit hash or empty / хэш коммита или пусто
parse_commit_message() {
  local -r message="$1" hash="${2:-}"
  local header body=""
  header="${message%%$'\n'*}"
  if [[ "${message}" == *$'\n'* ]]; then body="${message#*$'\n'}"; fi

  local ctype="chore" scope="" desc="${header}"
  local -i breaking=0
  local breaking_desc=""
  # header: type(scope)!: description / заголовок: тип(scope)!: описание
  local -r hre='^([[:alnum:]_]+)(\([^)]+\))?(!)?:[[:space:]]*(.+)$'
  if [[ "${header}" =~ ${hre} ]]; then
    ctype="${BASH_REMATCH[1],,}"
    local sm="${BASH_REMATCH[2]}"
    if [[ -n "${sm}" ]]; then scope="${sm:1:${#sm}-2}"; fi
    if [[ -n "${BASH_REMATCH[3]}" ]]; then breaking=1; fi
    desc="$(trim "${BASH_REMATCH[4]}")"
  fi
  # BREAKING CHANGE: in the body/footer also marks the commit as breaking
  # BREAKING CHANGE: в теле/футере тоже помечает коммит как ломающий
  if [[ -n "${body}" && "${body}" == *"BREAKING CHANGE:"* ]]; then
    breaking=1
    local -r bre=$'BREAKING CHANGE:[[:space:]]*([^\n]+)'
    if [[ "${body}" =~ ${bre} ]]; then
      breaking_desc="$(trim "${BASH_REMATCH[1]}")"
    fi
  fi

  C_TYPE+=("${ctype}")
  C_SCOPE+=("${scope}")
  C_DESC+=("${desc}")
  C_BREAKING+=("${breaking}")
  C_BREAKING_DESC+=("${breaking_desc}")
  C_HASH+=("${hash}")
}

# Parse 'git log --oneline' style text (hex hash + message per line).
# Разобрать текст в стиле 'git log --oneline' (hex-хэш + сообщение на строку).
# Args:
#   $1: raw git log text / сырой текст git log
parse_git_log() {
  local -r data="$1"
  local line
  local -r oneline_re='^([a-f0-9]{7,40})[[:space:]]+(.+)$'
  while IFS= read -r line; do
    line="$(trim "${line}")"
    if [[ -z "${line}" ]]; then continue; fi
    if [[ "${line}" =~ ${oneline_re} ]]; then
      parse_commit_message "${BASH_REMATCH[2]}" "${BASH_REMATCH[1]}"
    fi
  done <<< "${data}"
}

# Extract message/hash pairs from a flat JSON array of objects
# ({"message": "...", "hash": "..."}). Escapes \" \\ \/ \n \t \r \b \f are
# unescaped; XXXX sequences and nested structures are not supported.
# Вытащить пары message/hash из плоского JSON-массива объектов
# ({"message": "...", "hash": "..."}). Экранирования \" \\ \/ \n \t \r \b \f
# раскрываются; последовательности XXXX и вложенность не поддерживаются.
# Output: records "message<US>hash<RS>" (US=0x1f, RS=0x1e).
# Выход: записи "message<US>hash<RS>".
json_extract_commits() {
  awk '
    function store_pair() {
      if (key == "message") rec_msg = val
      else if (key == "hash") rec_hash = val
    }
    function flush_record() {
      printf "%s%c%s%c", rec_msg, 31, rec_hash, 30
      rec_msg = ""; rec_hash = ""
    }
    { s = s $0 ORS }
    END {
      n = length(s)
      in_str = 0; esc = 0; state = 0
      key = ""; val = ""; rec_msg = ""; rec_hash = ""
      for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (in_str) {
          if (esc) {
            if (c == "n") c = "\n"
            else if (c == "t") c = "\t"
            else if (c == "r") c = "\r"
            else if (c == "b") c = "\b"
            else if (c == "f") c = "\f"
            if (state == 1) key = key c; else val = val c
            esc = 0
            continue
          }
          if (c == "\\") { esc = 1; continue }
          if (c == "\"") {
            in_str = 0
            if (state == 1) state = 2
            else if (state == 3) state = 4
            continue
          }
          if (state == 1) key = key c; else val = val c
          continue
        }
        if (c == "\"") {
          in_str = 1
          if (state == 0) { state = 1; key = "" }
          else if (state == 2) { state = 3; val = "" }
          continue
        }
        if (c == "{") { state = 0; rec_msg = ""; rec_hash = ""; continue }
        if (c == ",") { if (state == 4) { store_pair(); state = 0 } continue }
        if (c == "}") {
          if (state == 4) store_pair()
          flush_record()
          state = 0
          continue
        }
      }
    }'
}

# Parse commits from a flat JSON array of objects (Python parse_commits_from_json).
# Разобрать коммиты из плоского JSON-массива объектов (Python parse_commits_from_json).
# Args:
#   $1: raw JSON text / сырой JSON-текст
parse_json_commits() {
  local -r data="$1"
  local trimmed
  trimmed="$(trim "${data}")"
  if [[ "${trimmed}" != \[* ]]; then
    data_error "Error parsing commits: input is not a JSON array"
  fi
  local rec msg hash
  while IFS= read -r -d $'\x1e' rec; do
    if [[ "${rec}" == *$'\x1f'* ]]; then
      msg="${rec%%$'\x1f'*}"
      hash="${rec#*$'\x1f'}"
    else
      msg="${rec}"
      hash=""
    fi
    parse_commit_message "${msg}" "${hash}"
  done < <(printf '%s' "${data}" | json_extract_commits)
}

# Parse --custom-rules flat JSON object {"type": "bump"} into CUSTOM_RULES.
# Разобрать плоский JSON-объект --custom-rules {"тип": "бамп"} в CUSTOM_RULES.
parse_custom_rules() {
  local -r json="$1"
  local trimmed
  trimmed="$(trim "${json}")"
  if [[ "${trimmed}" != \{* || "${trimmed}" != *\} ]]; then
    data_error "Invalid custom rules: input is not a JSON object"
  fi
  local pair key val
  local -a pairs=()
  # one "key": "value" pair per line (flat objects only / только плоские объекты)
  while IFS= read -r pair; do
    if [[ -n "${pair}" ]]; then pairs+=("${pair}"); fi
  done < <(printf '%s' "${json}" | grep -oE '"[^"]+"[[:space:]]*:[[:space:]]*"[^"]+"' || true)
  local -r pair_re='^"([^"]+)"[[:space:]]*:[[:space:]]*"([^"]+)"$'
  for pair in ${pairs[@]+"${pairs[@]}"}; do
    if [[ "${pair}" =~ ${pair_re} ]]; then
      key="${BASH_REMATCH[1]}"
      val="${BASH_REMATCH[2],,}"
      case "${val}" in
        none|patch|minor|major) CUSTOM_RULES[${key}]="${val}" ;;
        *) data_error "Invalid custom rules: '${val}' is not a valid BumpType" ;;
      esac
    fi
  done
}

# Replace IGNORE_TYPES with a comma-separated list (Python --ignore-types).
# Заменить IGNORE_TYPES списком через запятую (Python --ignore-types).
parse_ignore_types() {
  IGNORE_TYPES=()
  local raw
  while IFS= read -r raw; do
    raw="$(trim "${raw}")"
    if [[ -n "${raw}" ]]; then IGNORE_TYPES+=("${raw}"); fi
  done <<< "${opt_ignore_types//,/$'\n'}"
}

# Determine the bump type from the parsed commits into BUMP_TYPE.
# Определить тип бампа по разобранным коммитам в BUMP_TYPE.
determine_bump() {
  BUMP_TYPE="none"
  if (( ${#C_TYPE[@]} == 0 )); then return 0; fi
  local -i has_breaking=0 has_feature=0 has_fix=0
  local -i i
  local t rule
  for (( i = 0; i < ${#C_TYPE[@]}; i++ )); do
    # breaking changes win over everything / ломающие изменения важнее всего
    if (( ${C_BREAKING[$i]} )); then
      has_breaking=1
      continue
    fi
    t="${C_TYPE[$i]}"
    # custom rules apply before the standard mapping / кастомные правила раньше стандартных
    if [[ -v "CUSTOM_RULES[${t}]" ]]; then
      rule="${CUSTOM_RULES[${t}]}"
      case "${rule}" in
        major) has_breaking=1 ;;
        minor) has_feature=1 ;;
        patch) has_fix=1 ;;
        none)  : ;;
      esac
      continue
    fi
    case "${t}" in
      feat|add)                 has_feature=1 ;;
      fix|security|perf|bugfix) has_fix=1 ;;
      # ignored types contribute nothing / игнорируемые типы не влияют на бамп
    esac
  done
  if   (( has_breaking )); then BUMP_TYPE="major"
  elif (( has_feature ));  then BUMP_TYPE="minor"
  elif (( has_fix ));      then BUMP_TYPE="patch"
  fi
}

# Bucket parsed commits for the --analysis report.
# Раскидать разобранные коммиты по корзинам для отчёта --analysis.
analyze_commits() {
  A_TOTAL=${#C_TYPE[@]}
  A_BREAKING_IDX=() A_FEATURES_IDX=() A_FIXES_IDX=() A_IGNORED_IDX=()
  BY_TYPE=() BY_TYPE_ORDER=()
  if (( A_TOTAL == 0 )); then return 0; fi
  local -i i
  local t ig
  for (( i = 0; i < A_TOTAL; i++ )); do
    t="${C_TYPE[$i]}"
    if [[ -v "BY_TYPE[${t}]" ]]; then
      BY_TYPE[${t}]=$(( BY_TYPE[${t}] + 1 ))
    else
      BY_TYPE[${t}]=1
      BY_TYPE_ORDER+=("${t}")
    fi
    if (( ${C_BREAKING[$i]} )); then
      A_BREAKING_IDX+=("${i}")
    elif [[ "${t}" == "feat" || "${t}" == "add" ]]; then
      A_FEATURES_IDX+=("${i}")
    elif [[ "${t}" == "fix" || "${t}" == "security" \
         || "${t}" == "perf" || "${t}" == "bugfix" ]]; then
      A_FIXES_IDX+=("${i}")
    else
      for ig in ${IGNORE_TYPES[@]+"${IGNORE_TYPES[@]}"}; do
        if [[ "${t}" == "${ig}" ]]; then
          A_IGNORED_IDX+=("${i}")
          break
        fi
      done
    fi
  done
}

# Bump command templates for package managers (static, version substituted).
# Шаблоны команд бампа для пакетных менеджеров (статика с подстановкой версии).
build_bump_commands() {
  CMD_ORDER=(npm python rust git docker)
  BUMP_COMMANDS=(
    [npm]="npm version ${NV_STR} --no-git-tag-version"$'\n'"# Or manually edit package.json version field to '${NV_STR}'"
    [python]="# Update version in setup.py, __init__.py, or pyproject.toml"$'\n'"# setup.py: version='${NV_STR}'"$'\n'"# pyproject.toml: version = '${NV_STR}'"$'\n'"# __init__.py: __version__ = '${NV_STR}'"
    [rust]="# Update Cargo.toml"$'\n'"# [package]"$'\n'"# version = '${NV_STR}'"
    [git]="git tag -a ${NV_STR_V} -m 'Release ${NV_STR_V}'"$'\n'"git push origin ${NV_STR_V}"
    [docker]="docker build -t myapp:${NV_STR} ."$'\n'"docker tag myapp:${NV_STR} myapp:latest"
  )
}

# File update snippets for common package files (static, version substituted).
# Сниппеты обновления для типовых пакетных файлов (статика с подстановкой версии).
build_file_updates() {
  FILE_ORDER=("package.json" "pyproject.toml" "setup.py" "Cargo.toml" "__init__.py")
  FILE_UPDATES=(
    ["package.json"]="$(cat <<EOF
{
  "name": "your-package",
  "version": "${NV_STR}",
  "description": "Your package description",
  "main": "index.js"
}
EOF
)"
    ["pyproject.toml"]="$(cat <<EOF
[build-system]
requires = ["setuptools>=61.0", "wheel"]
build-backend = "setuptools.build_meta"

[project]
name = "your-package"
version = "${NV_STR}"
description = "Your package description"
authors = [
    {name = "Your Name", email = "your.email@example.com"},
]
EOF
)"$'\n'
    ["setup.py"]="$(cat <<EOF
from setuptools import setup, find_packages

setup(
    name="your-package",
    version="${NV_STR}",
    description="Your package description",
    packages=find_packages(),
    python_requires=">=3.8",
)
EOF
)"$'\n'
    ["Cargo.toml"]="$(cat <<EOF
[package]
name = "your-package"
version = "${NV_STR}"
edition = "2021"
description = "Your package description"
EOF
)"$'\n'
    ["__init__.py"]="$(cat <<EOF
"""Your package."""

__version__ = "${NV_STR}"
__author__ = "Your Name"
__email__ = "your.email@example.com"
EOF
)"$'\n'
  )
}

# Join lines with \n like Python "\n".join into output_text (no trailing newline).
# Склеить строки через \n как Python "\n".join в output_text (без хвостового \n).
# Args:
#   $1: nameref of the lines array / nameref массива строк
join_lines() {
  local -n __arr_join="$1"
  output_text=""
  local -i i last=$(( ${#__arr_join[@]} - 1 ))
  for (( i = 0; i <= last; i++ )); do
    if (( i > 0 )); then output_text+=$'\n'; fi
    output_text+="${__arr_join[$i]}"
  done
}

# Text output (same layout as the Python text format).
# Текстовый вывод (тот же вид, что у текстового формата Python-версии).
render_text() {
  local -a lines=(
    "Current Version: ${opt_current_version}"
    "Recommended Version: ${NV_STR}"
    "With v prefix: ${NV_STR_V}"
    "Bump Type: ${BUMP_TYPE}"
    ""
  )
  if (( opt_analysis )); then
    analyze_commits
    lines+=(
      "Commit Analysis:"
      "- Total commits: ${A_TOTAL}"
      "- Breaking changes: ${#A_BREAKING_IDX[@]}"
      "- New features: ${#A_FEATURES_IDX[@]}"
      "- Bug fixes: ${#A_FIXES_IDX[@]}"
      "- Ignored commits: ${#A_IGNORED_IDX[@]}"
      ""
    )
    if (( ${#A_BREAKING_IDX[@]} > 0 )); then
      lines+=("Breaking Changes:")
      local -i idx
      local scope
      for idx in ${A_BREAKING_IDX[@]+"${A_BREAKING_IDX[@]}"}; do
        scope=""
        if [[ -n "${C_SCOPE[$idx]}" ]]; then scope="(${C_SCOPE[$idx]})"; fi
        lines+=("  - ${C_TYPE[$idx]}${scope}: ${C_DESC[$idx]}")
      done
      lines+=("")
    fi
  fi
  if (( opt_include_commands )); then
    build_bump_commands
    lines+=("Bump Commands:")
    local cat cmd
    for cat in "${CMD_ORDER[@]}"; do
      lines+=("  ${cat}:")
      while IFS= read -r cmd; do
        # comments are guidance, not commands / комментарии — подсказки, не команды
        if [[ "${cmd}" != \#* ]]; then
          lines+=("    ${cmd}")
        fi
      done <<< "${BUMP_COMMANDS[${cat}]}"
    done
    # one trailing blank after the whole block (not per category)
    # одна хвостовая пустая строка после всего блока (не на категорию)
    lines+=("")
  fi
  join_lines lines
}

# Commands output (same layout as the Python commands format).
# Вывод команд (тот же вид, что у формата commands Python-версии).
render_commands() {
  build_bump_commands
  local -a lines=(
    "# Version Bump Commands"
    "# Current: ${opt_current_version}"
    "# New: ${NV_STR}"
    "# Bump Type: ${BUMP_TYPE}"
    ""
  )
  local cat cmd
  for cat in "${CMD_ORDER[@]}"; do
    lines+=("## ${cat^^}")
    while IFS= read -r cmd; do
      lines+=("${cmd}")
    done <<< "${BUMP_COMMANDS[${cat}]}"
    lines+=("")
  done
  join_lines lines
}

# Render one analysis list of commit objects (helper for render_json).
# Отрисовать один список объектов коммитов для анализа (помощник render_json).
# Args:
#   $1: item indent (6 spaces for analysis lists) / отступ элементов
#   $2: object kind: breaking|feature|fix|ignored / вид объекта
#   $3: nameref of the index array / nameref массива индексов
json_commit_objects() {
  local -r indent="$1" kind="$2"
  local -n __arr_idx="$3"
  if (( ${#__arr_idx[@]} == 0 )); then
    printf '[]'
    return 0
  fi
  local out='['
  local -i n_i last=$(( ${#__arr_idx[@]} - 1 )) idx
  for (( n_i = 0; n_i <= last; n_i++ )); do
    idx=${__arr_idx[$n_i]}
    out+=$'\n'"${indent}"'{'
    if [[ "${kind}" == "breaking" || "${kind}" == "ignored" ]]; then
      out+=$'\n'"${indent}"'  "type": "'"$(json_escape "${C_TYPE[$idx]}")"'",'
    fi
    out+=$'\n'"${indent}"'  "scope": "'"$(json_escape "${C_SCOPE[$idx]}")"'",'
    out+=$'\n'"${indent}"'  "description": "'"$(json_escape "${C_DESC[$idx]}")"'",'
    if [[ "${kind}" == "breaking" ]]; then
      out+=$'\n'"${indent}"'  "breaking_description": "'"$(json_escape "${C_BREAKING_DESC[$idx]}")"'",'
    fi
    out+=$'\n'"${indent}"'  "hash": "'"$(json_escape "${C_HASH[$idx]}")"'"'
    out+=$'\n'"${indent}"'}'
    if (( n_i < last )); then out+=','; fi
  done
  out+=$'\n'"${indent:2}"']'
  printf '%s' "${out}"
}

# The "analysis" chunk for JSON output / Кусок "analysis" для JSON-вывода
json_analysis_chunk() {
  analyze_commits
  local s='  "analysis": {'
  s+=$'\n    "total_commits": '"${A_TOTAL}"','
  if (( ${#BY_TYPE_ORDER[@]} == 0 )); then
    s+=$'\n    "by_type": {},'
  else
    s+=$'\n    "by_type": {'
    local -i i
    local t
    for i in "${!BY_TYPE_ORDER[@]}"; do
      t="${BY_TYPE_ORDER[$i]}"
      s+=$'\n      "'"$(json_escape "${t}")"'": '"${BY_TYPE[${t}]}"
      if (( i < ${#BY_TYPE_ORDER[@]} - 1 )); then s+=','; fi
    done
    s+=$'\n    },'
  fi
  s+=$'\n    "breaking_changes": '"$(json_commit_objects '      ' breaking A_BREAKING_IDX)"','
  s+=$'\n    "features": '"$(json_commit_objects '      ' feature A_FEATURES_IDX)"','
  s+=$'\n    "fixes": '"$(json_commit_objects '      ' fix A_FIXES_IDX)"','
  s+=$'\n    "ignored": '"$(json_commit_objects '      ' ignored A_IGNORED_IDX)"
  s+=$'\n  }'
  printf '%s' "${s}"
}

# The "commands" chunk for JSON output / Кусок "commands" для JSON-вывода
json_commands_chunk() {
  build_bump_commands
  local s='  "commands": {'
  local -i ci last_ci=$(( ${#CMD_ORDER[@]} - 1 )) i
  local cat cmd
  for (( ci = 0; ci <= last_ci; ci++ )); do
    cat="${CMD_ORDER[$ci]}"
    local -a cmd_lines=()
    while IFS= read -r cmd; do
      cmd_lines+=("${cmd}")
    done <<< "${BUMP_COMMANDS[${cat}]}"
    s+=$'\n    "'"${cat}"'": ['
    for (( i = 0; i < ${#cmd_lines[@]}; i++ )); do
      s+=$'\n      "'"$(json_escape "${cmd_lines[$i]}")"'"'
      if (( i < ${#cmd_lines[@]} - 1 )); then s+=','; fi
    done
    s+=$'\n    ]'
    if (( ci < last_ci )); then s+=','; fi
  done
  s+=$'\n  }'
  printf '%s' "${s}"
}

# The "file_updates" chunk for JSON output / Кусок "file_updates" для JSON-вывода
json_file_updates_chunk() {
  build_file_updates
  local s='  "file_updates": {'
  local -i i last=$(( ${#FILE_ORDER[@]} - 1 ))
  local fname
  for (( i = 0; i <= last; i++ )); do
    fname="${FILE_ORDER[$i]}"
    s+=$'\n    "'"$(json_escape "${fname}")"'": "'"$(json_escape "${FILE_UPDATES[${fname}]}")"'"'
    if (( i < last )); then s+=','; fi
  done
  s+=$'\n  }'
  printf '%s' "${s}"
}

# JSON output (shape of Python json.dumps(output_data, indent=2);
# non-ASCII is emitted as raw UTF-8, not XXXX escapes).
# JSON-вывод (форма Python json.dumps(output_data, indent=2);
# не-ASCII выводится как UTF-8, а не как XXXX).
render_json() {
  local -a chunks=()
  chunks+=('  "current_version": "'"$(json_escape "${opt_current_version}")"'"')
  chunks+=('  "recommended_version": "'"$(json_escape "${NV_STR}")"'"')
  chunks+=('  "recommended_version_with_v": "'"$(json_escape "${NV_STR_V}")"'"')
  chunks+=('  "bump_type": "'"${BUMP_TYPE}"'"')
  if [[ -n "${opt_prerelease}" ]]; then
    chunks+=('  "prerelease": "'"${opt_prerelease}"'"')
  else
    chunks+=('  "prerelease": null')
  fi
  if (( opt_analysis )); then
    chunks+=("$(json_analysis_chunk)")
  fi
  if (( opt_include_commands )); then
    chunks+=("$(json_commands_chunk)")
  fi
  if (( opt_include_files )); then
    chunks+=("$(json_file_updates_chunk)")
  fi
  output_text='{'$'\n'
  local -i i last=$(( ${#chunks[@]} - 1 ))
  for (( i = 0; i <= last; i++ )); do
    output_text+="${chunks[$i]}"
    if (( i < last )); then output_text+=','; fi
    output_text+=$'\n'
  done
  output_text+='}'
}

main() {
  parse_args "$@"
  if [[ -z "${opt_current_version}" ]]; then
    arg_error "the following arguments are required: --current-version/-c"
  fi

  # Read input: --input file or stdin / Чтение входа: файл --input или stdin
  local input_data
  if [[ -n "${opt_input}" ]]; then
    if [[ ! -f "${opt_input}" ]]; then
      data_error "Error reading input file: ${opt_input}: no such file"
    fi
    input_data="$(cat -- "${opt_input}")"
  else
    input_data="$(cat)"
  fi
  if [[ -z "$(trim "${input_data}")" ]]; then
    data_error "No input data provided"
  fi

  # Current version first: it gates all later output
  # Сначала текущая версия: она влияет на весь дальнейший вывод
  if ! version_parse "${opt_current_version}"; then
    data_error "Invalid current version: ${V_ERRMSG}"
  fi

  if [[ -n "${opt_custom_rules}" ]]; then
    parse_custom_rules "${opt_custom_rules}"
  fi
  if [[ -n "${opt_ignore_types}" ]]; then
    parse_ignore_types
  fi

  case "${opt_input_format}" in
    json)    parse_json_commits "${input_data}" ;;
    *)       parse_git_log "${input_data}" ;;
  esac

  determine_bump
  version_bump "${BUMP_TYPE}" "${opt_prerelease}"
  NV_STR="$(nv_string 0)"
  NV_STR_V="$(nv_string 1)"

  case "${opt_output_format}" in
    json)     render_json ;;
    commands) render_commands ;;
    *)        render_text ;;
  esac

  # stdout gets a trailing newline (print), --output file does not (write)
  # stdout получает хвостовой перевод строки (print), файл --output — нет (write)
  if [[ -n "${opt_output}" ]]; then
    printf '%s' "${output_text}" > "${opt_output}"
  else
    printf '%s\n' "${output_text}"
  fi
  exit 0
}

main "$@"
