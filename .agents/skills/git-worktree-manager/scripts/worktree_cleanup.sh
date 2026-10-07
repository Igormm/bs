#!/usr/bin/env bash
# shellcheck shell=bash
# .agents/skills/git-worktree-manager/scripts/worktree_cleanup.sh — inspect and clean stale git worktrees with safety checks
# .agents/skills/git-worktree-manager/scripts/worktree_cleanup.sh — проанализировать и почистить устаревшие git worktree с проверками безопасности

# Bash port of the former worktree_cleanup.py (this repo is Python-free).
# Баш-порт прежнего worktree_cleanup.py (репозиторий без Python).
#
# Supports / Поддерживает:
# - JSON input from stdin or --input file / JSON-ввод из stdin или файла --input
# - Stale age detection / обнаружение устаревших по возрасту
# - Dirty working tree detection / обнаружение грязного рабочего дерева
# - Merged branch detection / обнаружение влитых веток
# - Optional removal of merged, clean stale worktrees / опциональное удаление
#   влитых чистых устаревших worktree
#
# Note: JSON input is parsed as a FLAT object ("key": scalar); nested values
# are not supported (the Python original used a full JSON parser).
# Примечание: JSON-ввод разбирается как ПЛОСКИЙ объект ("ключ": скаляр);
# вложенные значения не поддерживаются (оригинал на Python использовал полный парсер).

set -euo pipefail

# BS bootstrap: repo root is resolved from this script's location
# BS-бутстрап: корень репозитория вычисляется из расположения скрипта
export BS_SILENT=1
__script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck disable=SC1091
source "${__script_dir}/../../../../bootstrap/init.sh"

usage() {
    cat <<'HELP'
usage: worktree_cleanup.sh [-h] [--input INPUT] [--repo REPO]
                           [--base-branch BASE_BRANCH] [--stale-days STALE_DAYS]
                           [--remove-merged] [--force] [--format {text,json}]

Analyze and optionally cleanup stale git worktrees.

options:
  -h, --help               show this help message and exit
  --input INPUT            Path to JSON input file. If omitted, reads JSON from stdin when piped.
  --repo REPO              Repository root path (default: current directory).
  --base-branch BRANCH     Base branch to evaluate merged branches (default: main).
  --stale-days N           Threshold for stale worktrees (default: 14).
  --remove-merged          Remove worktrees that are stale, clean, and merged.
  --force                  Allow removal even if dirty (use carefully).
  --format {text,json}     Output format (default: text).
HELP
}

# Expected CLI error: message to stderr, exit 2 (mirrors the Python CLIError path)
# Ожидаемая ошибка CLI: сообщение в stderr, выход 2 (зеркалит путь CLIError из Python)
die() {
    log::error "${1}"
    exit 2
}

# Escape a string for JSON output / Экранировать строку для JSON-вывода
json_escape() {
    local s="${1}"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\t'/\\t}"
    s="${s//$'\r'/\\r}"
    printf '%s' "${s}"
}

# Extract a top-level scalar from a flat JSON object: "key": "str" | number | bool
# Извлечь скаляр верхнего уровня из плоского JSON-объекта
# Returns 1 (no output) when the key is absent / Возвращает 1 без вывода, если ключа нет
json_get() {
    local -r json="${1}" key="${2}"
    local raw
    raw="$(printf '%s\n' "${json}" \
        | grep -m 1 -oE "\"${key}\"[[:space:]]*:[[:space:]]*(\"([^\"\\\\]|\\\\.)*\"|-?[0-9]+|true|false)" \
        || true)"
    [[ -n "${raw}" ]] || return 1
    local value="${raw#*:}"
    # trim surrounding whitespace / срезать пробелы по краям
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    if [[ "${value}" == \"*\" ]]; then
        value="${value:1:${#value}-2}"
        # unescape \" and \\ (backslash protected first) / разэкранировать \" и \\
        value="${value//\\\\/$'\x01'}"
        value="${value//\\\"/\"}"
        value="${value//$'\x01'/\\}"
    fi
    printf '%s' "${value}"
}

# JSON payload wins over CLI value / Значение из JSON побеждает значение CLI
resolve() {
    local -r payload="${1}" key="${2}" fallback="${3}"
    local value
    if value="$(json_get "${payload}" "${key}")"; then
        printf '%s' "${value}"
    else
        printf '%s' "${fallback}"
    fi
}

# Resolve a directory path physically (kept as-is when missing) / Физически
# разрешить путь каталога (если каталога нет — вернуть как есть)
resolve_path() {
    local -r path="${1}"
    if [[ -d "${path}" ]]; then
        (cd -- "${path}" && pwd -P)
    else
        printf '%s\n' "${path}"
    fi
}

# Python-style bool word for text output / Булево слово в стиле Python для текстового вывода
bool_word() {
    [[ "${1}" == "true" ]] && printf 'True' || printf 'False'
}

main() {
    local opt_input="" opt_repo="." opt_base_branch="main" opt_stale_days="14"
    local opt_format="text"
    local -i remove_merged=0 force=0

    while [[ $# -gt 0 ]]; do
        case "${1}" in
            -h|--help)
                usage
                exit 0
                ;;
            --input)    [[ $# -ge 2 ]] || { log::error "argument --input: expected one argument"; exit 2; }; opt_input="${2}"; shift 2 ;;
            --input=*)  opt_input="${1#*=}"; shift ;;
            --repo)     [[ $# -ge 2 ]] || { log::error "argument --repo: expected one argument"; exit 2; }; opt_repo="${2}"; shift 2 ;;
            --repo=*)   opt_repo="${1#*=}"; shift ;;
            --base-branch)   [[ $# -ge 2 ]] || { log::error "argument --base-branch: expected one argument"; exit 2; }; opt_base_branch="${2}"; shift 2 ;;
            --base-branch=*) opt_base_branch="${1#*=}"; shift ;;
            --stale-days)   [[ $# -ge 2 ]] || { log::error "argument --stale-days: expected one argument"; exit 2; }; opt_stale_days="${2}"; shift 2 ;;
            --stale-days=*) opt_stale_days="${1#*=}"; shift ;;
            --remove-merged) remove_merged=1; shift ;;
            --force)         force=1; shift ;;
            --format)   [[ $# -ge 2 ]] || { log::error "argument --format: expected one argument"; exit 2; }; opt_format="${2}"; shift 2 ;;
            --format=*) opt_format="${1#*=}"; shift ;;
            *)
                log::error "unrecognized argument: ${1}"
                exit 2
                ;;
        esac
    done

    [[ "${opt_format}" == "text" || "${opt_format}" == "json" ]] \
        || die "argument --format: invalid choice: '${opt_format}' (choose from 'text', 'json')"

    # JSON input: --input file, or stdin when piped / JSON-ввод: файл --input
    # или stdin при конвейере
    local payload=""
    if [[ -n "${opt_input}" ]]; then
        payload="$(cat -- "${opt_input}" 2>/dev/null)" \
            || die "Failed reading --input file: ${opt_input}"
    elif [[ ! -t 0 ]]; then
        payload="$(cat || true)"
    fi
    payload="${payload#"${payload%%[![:space:]]*}"}"
    payload="${payload%"${payload##*[![:space:]]}"}"
    if [[ -n "${payload}" && ( "${payload}" != \{* || "${payload}" != *\} ) ]]; then
        if [[ -n "${opt_input}" ]]; then
            die "Failed reading --input file: invalid JSON (flat object expected)"
        fi
        die "Invalid JSON from stdin: flat JSON object expected"
    fi

    local repo base_branch stale_days
    repo="$(resolve "${payload}" repo "${opt_repo}")"
    stale_days="$(resolve "${payload}" stale_days "${opt_stale_days}")"
    base_branch="$(resolve "${payload}" base_branch "${opt_base_branch}")"
    local bool_json
    if bool_json="$(json_get "${payload}" remove_merged)"; then
        [[ "${bool_json}" == "true" || "${bool_json}" == "1" ]] && remove_merged=1 || remove_merged=0
    fi
    if bool_json="$(json_get "${payload}" force)"; then
        [[ "${bool_json}" == "true" || "${bool_json}" == "1" ]] && force=1 || force=0
    fi

    [[ "${stale_days}" =~ ^-?[0-9]+$ ]] || die "invalid int for stale_days: '${stale_days}'"

    [[ -d "${repo}" ]] || die "Not a git repository: ${repo}"
    repo="$(cd -- "${repo}" && pwd -P)"
    git -C "${repo}" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
        || die "Not a git repository: ${repo}"
    git -C "${repo}" rev-parse --verify "${base_branch}" >/dev/null 2>&1 \
        || die "Base branch not found: ${base_branch}"

    local -a entries=()
    mapfile -t entries < <(git -C "${repo}" worktree list --porcelain | sed -n 's/^worktree //p')
    [[ ${#entries[@]} -gt 0 ]] || die "No worktrees found."

    local main_path
    main_path="$(resolve_path "${entries[0]}")"

    # Parallel arrays of per-worktree facts / Параллельные массивы фактов о worktree
    local -a paths=() branches=() is_mains=() ages=() stales=() dirties=() mergeds=()
    local -a removed=()

    local -i now
    now="$(date +%s)"

    local raw_path path branch is_main dirty stale merged
    local -i age timestamp
    for raw_path in "${entries[@]}"; do
        path="$(resolve_path "${raw_path}")"
        branch="$(git -C "${path}" rev-parse --abbrev-ref HEAD 2>/dev/null)" \
            || die "Failed to inspect worktree (missing directory?): ${path}"

        timestamp="$(git -C "${path}" log -1 --format=%ct 2>/dev/null || printf '0')"
        timestamp="${timestamp:-0}"
        age=$(( (now - timestamp) / 86400 ))
        (( age < 0 )) && age=0

        if [[ -n "$(git -C "${path}" status --porcelain 2>/dev/null)" ]]; then
            dirty=true
        else
            dirty=false
        fi

        if (( age >= stale_days )); then
            stale=true
        else
            stale=false
        fi

        # Never report HEAD or the base branch itself as merged
        # HEAD и саму базовую ветку никогда не считаем влитыми
        if [[ "${branch}" == "HEAD" || "${branch}" == "${base_branch}" ]]; then
            merged=false
        elif git -C "${repo}" merge-base --is-ancestor "${branch}" "${base_branch}" 2>/dev/null; then
            merged=true
        else
            merged=false
        fi

        if [[ "${path}" == "${main_path}" ]]; then
            is_main=true
        else
            is_main=false
        fi

        paths+=("${path}")
        branches+=("${branch}")
        is_mains+=("${is_main}")
        ages+=("${age}")
        stales+=("${stale}")
        dirties+=("${dirty}")
        mergeds+=("${merged}")

        if [[ "${remove_merged}" -eq 1 && "${is_main}" == "false" && "${stale}" == "true" \
            && "${merged}" == "true" && ( "${force}" -eq 1 || "${dirty}" == "false" ) ]]; then
            local -a rm_cmd=(git -C "${repo}" worktree remove "${path}")
            local err
            (( force == 1 )) && rm_cmd+=("--force")
            if ! err="$("${rm_cmd[@]}" 2>&1 >/dev/null)"; then
                die "Failed removing worktree ${path}: ${err}"
            fi
            removed+=("${path}")
        fi
    done

    if [[ "${opt_format}" == "json" ]]; then
        printf '{\n  "worktrees": ['
        local -i i
        for ((i = 0; i < ${#paths[@]}; i++)); do
            (( i > 0 )) && printf ','
        printf '\n    {\n'
        printf '      "path": "%s",\n' "$(json_escape "${paths[${i}]}")"
        printf '      "branch": "%s",\n' "$(json_escape "${branches[${i}]}")"
        printf '      "is_main": %s,\n' "${is_mains[${i}]}"
        printf '      "age_days": %s,\n' "${ages[${i}]}"
        printf '      "stale": %s,\n' "${stales[${i}]}"
        printf '      "dirty": %s,\n' "${dirties[${i}]}"
        printf '      "merged_into_base": %s\n' "${mergeds[${i}]}"
        printf '    }'
        done
        if [[ ${#paths[@]} -gt 0 ]]; then
            printf '\n  ],\n  "removed": ['
        else
            printf '],\n  "removed": ['
        fi
        for ((i = 0; i < ${#removed[@]}; i++)); do
            (( i > 0 )) && printf ','
            printf '\n    "%s"' "$(json_escape "${removed[${i}]}")"
        done
        if [[ ${#removed[@]} -gt 0 ]]; then
            printf '\n  ]\n}\n'
        else
            printf ']\n}\n'
        fi
    else
        printf 'Worktree cleanup report\n'
        local -i i
        for ((i = 0; i < ${#paths[@]}; i++)); do
            printf -- '- %s | branch=%s | age=%sd | stale=%s dirty=%s merged=%s\n' \
                "${paths[${i}]}" "${branches[${i}]}" "${ages[${i}]}" \
                "$(bool_word "${stales[${i}]}")" "$(bool_word "${dirties[${i}]}")" \
                "$(bool_word "${mergeds[${i}]}")"
        done
        if [[ ${#removed[@]} -gt 0 ]]; then
            printf 'Removed:\n'
            for path in "${removed[@]}"; do
                printf -- '- %s\n' "${path}"
            done
        fi
    fi
}

main "$@"
