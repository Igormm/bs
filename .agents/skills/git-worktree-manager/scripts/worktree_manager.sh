#!/usr/bin/env bash
# shellcheck shell=bash
# .agents/skills/git-worktree-manager/scripts/worktree_manager.sh — create and prepare git worktrees with deterministic port allocation
# .agents/skills/git-worktree-manager/scripts/worktree_manager.sh — создать и подготовить git worktree с детерминированным выделением портов

# Bash port of the former worktree_manager.py (this repo is Python-free).
# Баш-порт прежнего worktree_manager.py (репозиторий без Python).
#
# Supports / Поддерживает:
# - JSON input from stdin or --input file / JSON-ввод из stdin или файла --input
# - Worktree creation from existing/new branch / создание worktree из существующей или новой ветки
# - .env file sync from main repo / синхронизация .env-файлов из основного репо
# - Optional dependency installation / опциональная установка зависимостей
# - JSON or text output / вывод в формате JSON или текста
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

# Env files synced into each new worktree / Env-файлы, копируемые в каждый новый worktree
readonly ENV_FILES=(".env" ".env.local" ".env.development" ".envrc")

# Lockfile -> install command (parallel arrays) / Локфайл -> команда установки (параллельные массивы)
readonly LOCKFILES=("pnpm-lock.yaml" "yarn.lock" "package-lock.json" "bun.lockb" "requirements.txt")
readonly LOCKFILE_COMMANDS=(
    "pnpm install"
    "yarn install"
    "npm install"
    "bun install"
    "python3 -m pip install -r requirements.txt"
)

usage() {
    cat <<'HELP'
usage: worktree_manager.sh [-h] [--input INPUT] [--repo REPO] [--branch BRANCH]
                           [--name NAME] [--base-branch BASE_BRANCH]
                           [--app-base APP_BASE] [--db-base DB_BASE]
                           [--redis-base REDIS_BASE] [--stride STRIDE]
                           [--install-deps] [--format {text,json}]

Create and prepare a git worktree.

options:
  -h, --help               show this help message and exit
  --input INPUT            Path to JSON input file. If omitted, reads JSON from stdin when piped.
  --repo REPO              Path to repository root (default: current directory).
  --branch BRANCH          Branch name for the worktree.
  --name NAME              Worktree directory name (created adjacent to repo).
  --base-branch BRANCH     Base branch when creating a new branch (default: main).
  --app-base PORT          Base app port (default: 3000).
  --db-base PORT           Base DB port (default: 5432).
  --redis-base PORT        Base Redis port (default: 6379).
  --stride N               Port stride between worktrees (default: 10).
  --install-deps           Install dependencies in the new worktree.
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

# List worktree paths of a repo / Список путей worktree репозитория
worktree_paths() {
    git -C "${1}" worktree list --porcelain | sed -n 's/^worktree //p'
}

# Allocate the next free port triple: base + index*stride, collision-checked
# against .worktree-ports.json of all existing worktrees
# Выделить следующую свободную тройку портов: base + index*stride, с проверкой
# коллизий по .worktree-ports.json всех существующих worktree
find_next_ports() {
    local -r repo="${1}" app_base="${2}" db_base="${3}" redis_base="${4}" stride="${5}"
    local -A used=()
    local wt_path ports_file port
    while IFS= read -r wt_path; do
        ports_file="${wt_path}/.worktree-ports.json"
        [[ -f "${ports_file}" ]] || continue
        while IFS= read -r port; do
            [[ -n "${port}" ]] && used["${port}"]=1
        done < <(grep -oE ':[[:space:]]*[0-9]+' "${ports_file}" | grep -oE '[0-9]+' || true)
    done < <(worktree_paths "${repo}")

    local -i index=0
    local app db redis
    while true; do
        app=$((app_base + index * stride))
        db=$((db_base + index * stride))
        redis=$((redis_base + index * stride))
        if [[ -z "${used[${app}]:-}" && -z "${used[${db}]:-}" && -z "${used[${redis}]:-}" ]]; then
            printf '%s %s %s\n' "${app}" "${db}" "${redis}"
            return 0
        fi
        index+=1
    done
}

# Copy .env* files from the main repo into the worktree / Копировать .env*-файлы
# из основного репо в worktree; prints copied names, one per line
sync_env_files() {
    local -r src_repo="${1}" dest_repo="${2}"
    local name
    for name in "${ENV_FILES[@]}"; do
        if [[ -f "${src_repo}/${name}" ]]; then
            cp -p -- "${src_repo}/${name}" "${dest_repo}/${name}"
            printf '%s\n' "${name}"
        fi
    done
}

# Install dependencies if a known lockfile is present / Установить зависимости
# при наличии известного локфайла; prints the status line
install_dependencies() {
    local -r wt_path="${1}" install="${2}"
    [[ "${install}" -eq 1 ]] || { printf 'skipped'; return 0; }

    local -i i
    local cmd_line err
    local -a cmd
    for ((i = 0; i < ${#LOCKFILES[@]}; i++)); do
        if [[ -f "${wt_path}/${LOCKFILES[${i}]}" ]]; then
            cmd_line="${LOCKFILE_COMMANDS[${i}]}"
            read -r -a cmd <<< "${cmd_line}"
            if ! err="$(cd -- "${wt_path}" && "${cmd[@]}" 2>&1 >/dev/null)"; then
                die "Dependency install failed: ${cmd_line}"$'\n'"${err}"
            fi
            printf 'installed via %s' "${cmd_line}"
            return 0
        fi
    done
    printf 'no known lockfile found'
}

# Create the worktree if missing; prints the worktree path
# Создать worktree при отсутствии; печатает путь worktree
ensure_worktree() {
    local -r repo="${1}" branch="${2}" name="${3}" base_branch="${4}"
    local -r wt_path="$(dirname -- "${repo}")/${name}"

    local existing
    if existing="$(worktree_paths "${repo}" | grep -Fx -- "${wt_path}" || true)" \
        && [[ -n "${existing}" ]]; then
        printf '%s\n' "${wt_path}"
        return 0
    fi

    local err
    if git -C "${repo}" show-ref --verify --quiet "refs/heads/${branch}"; then
        if ! err="$(git -C "${repo}" worktree add "${wt_path}" "${branch}" 2>&1 >/dev/null)"; then
            die "Failed to create worktree: ${err}"
        fi
    else
        if ! err="$(git -C "${repo}" worktree add -b "${branch}" "${wt_path}" "${base_branch}" 2>&1 >/dev/null)"; then
            die "Failed to create worktree: ${err}"
        fi
    fi
    printf '%s\n' "${wt_path}"
}

main() {
    local opt_input="" opt_repo="." opt_branch="" opt_name=""
    local opt_base_branch="main" opt_format="text"
    local opt_app_base="3000" opt_db_base="5432" opt_redis_base="6379" opt_stride="10"
    local -i install_deps=0

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
            --branch)   [[ $# -ge 2 ]] || { log::error "argument --branch: expected one argument"; exit 2; }; opt_branch="${2}"; shift 2 ;;
            --branch=*) opt_branch="${1#*=}"; shift ;;
            --name)     [[ $# -ge 2 ]] || { log::error "argument --name: expected one argument"; exit 2; }; opt_name="${2}"; shift 2 ;;
            --name=*)   opt_name="${1#*=}"; shift ;;
            --base-branch)   [[ $# -ge 2 ]] || { log::error "argument --base-branch: expected one argument"; exit 2; }; opt_base_branch="${2}"; shift 2 ;;
            --base-branch=*) opt_base_branch="${1#*=}"; shift ;;
            --app-base)   [[ $# -ge 2 ]] || { log::error "argument --app-base: expected one argument"; exit 2; }; opt_app_base="${2}"; shift 2 ;;
            --app-base=*) opt_app_base="${1#*=}"; shift ;;
            --db-base)   [[ $# -ge 2 ]] || { log::error "argument --db-base: expected one argument"; exit 2; }; opt_db_base="${2}"; shift 2 ;;
            --db-base=*) opt_db_base="${1#*=}"; shift ;;
            --redis-base)   [[ $# -ge 2 ]] || { log::error "argument --redis-base: expected one argument"; exit 2; }; opt_redis_base="${2}"; shift 2 ;;
            --redis-base=*) opt_redis_base="${1#*=}"; shift ;;
            --stride)   [[ $# -ge 2 ]] || { log::error "argument --stride: expected one argument"; exit 2; }; opt_stride="${2}"; shift 2 ;;
            --stride=*) opt_stride="${1#*=}"; shift ;;
            --install-deps) install_deps=1; shift ;;
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

    local repo branch name base_branch
    repo="$(resolve "${payload}" repo "${opt_repo}")"
    branch="$(resolve "${payload}" branch "${opt_branch}")"
    name="$(resolve "${payload}" name "${opt_name}")"
    base_branch="$(resolve "${payload}" base_branch "${opt_base_branch}")"
    local app_base db_base redis_base stride
    app_base="$(resolve "${payload}" app_base "${opt_app_base}")"
    db_base="$(resolve "${payload}" db_base "${opt_db_base}")"
    redis_base="$(resolve "${payload}" redis_base "${opt_redis_base}")"
    stride="$(resolve "${payload}" stride "${opt_stride}")"
    local install_json
    if install_json="$(json_get "${payload}" install_deps)"; then
        [[ "${install_json}" == "true" || "${install_json}" == "1" ]] && install_deps=1 || install_deps=0
    fi

    local int_re='^-?[0-9]+$'
    [[ "${app_base}" =~ ${int_re} ]]   || die "invalid int for app_base: '${app_base}'"
    [[ "${db_base}" =~ ${int_re} ]]    || die "invalid int for db_base: '${db_base}'"
    [[ "${redis_base}" =~ ${int_re} ]] || die "invalid int for redis_base: '${redis_base}'"
    [[ "${stride}" =~ ${int_re} ]]     || die "invalid int for stride: '${stride}'"

    [[ -n "${branch}" && -n "${name}" ]] \
        || die "Missing required values: --branch and --name (or provide via JSON input)."

    [[ -d "${repo}" ]] || die "Not a git repository: ${repo}"
    repo="$(cd -- "${repo}" && pwd -P)"
    git -C "${repo}" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
        || die "Not a git repository: ${repo}"

    local wt_path
    wt_path="$(ensure_worktree "${repo}" "${branch}" "${name}" "${base_branch}")"

    # created == ports file did not exist before this run (as in the Python original)
    # created == файл портов не существовал до этого запуска (как в Python-оригинале)
    local created=false
    [[ ! -f "${wt_path}/.worktree-ports.json" ]] && created=true

    local ports app db redis
    ports="$(find_next_ports "${repo}" "${app_base}" "${db_base}" "${redis_base}" "${stride}")"
    read -r app db redis <<< "${ports}"
    printf '{\n  "app": %s,\n  "db": %s,\n  "redis": %s\n}' "${app}" "${db}" "${redis}" \
        > "${wt_path}/.worktree-ports.json"

    local copied_files
    copied_files="$(sync_env_files "${repo}" "${wt_path}")"
    local install_status
    install_status="$(install_dependencies "${wt_path}" "${install_deps}")"

    if [[ "${opt_format}" == "json" ]]; then
        local copied_json="[]"
        if [[ -n "${copied_files}" ]]; then
            local item
            copied_json=""
            while IFS= read -r item; do
                [[ -n "${copied_json}" ]] && copied_json+=","
                copied_json+=$'\n'"    \"$(json_escape "${item}")\""
            done <<< "${copied_files}"
            copied_json="[${copied_json}"$'\n'"  ]"
        fi
        printf '{\n'
        printf '  "repo": "%s",\n' "$(json_escape "${repo}")"
        printf '  "worktree_path": "%s",\n' "$(json_escape "${wt_path}")"
        printf '  "branch": "%s",\n' "$(json_escape "${branch}")"
        printf '  "created": %s,\n' "${created}"
        printf '  "ports": {\n    "app": %s,\n    "db": %s,\n    "redis": %s\n  },\n' "${app}" "${db}" "${redis}"
        printf '  "copied_env_files": %s,\n' "${copied_json}"
        printf '  "dependency_install": "%s"\n' "$(json_escape "${install_status}")"
        printf '}\n'
    else
        local created_word="False" copied_word="none"
        [[ "${created}" == "true" ]] && created_word="True"
        [[ -n "${copied_files}" ]] && copied_word="$(paste -sd ', ' <<< "${copied_files}")"
        printf 'Worktree prepared\n'
        printf -- '- repo: %s\n' "${repo}"
        printf -- '- path: %s\n' "${wt_path}"
        printf -- '- branch: %s\n' "${branch}"
        printf -- '- created: %s\n' "${created_word}"
        printf -- '- ports: app=%s db=%s redis=%s\n' "${app}" "${db}" "${redis}"
        printf -- '- copied env files: %s\n' "${copied_word}"
        printf -- '- dependency install: %s\n' "${install_status}"
    fi
}

main "$@"
