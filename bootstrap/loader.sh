#!/usr/bin/env bs
# shellcheck shell=bash
#
# bootstrap/loader.sh — модуль загрузки с предотвращением повторного подключения
# bootstrap/loader.sh — loading module with duplicate loading prevention
#

# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points

# Pre-kernel root namespace: bs::shell::*, bs::script_dir, PATH tweak.
# Idempotent via its own guard — safe when init.sh already sourced it.
# Pre-kernel namespace: bs::shell::*, bs::script_dir, PATH-твик.
# Идемпотентен через собственный guard — безопасно, если init.sh уже подключил его.
if [[ -f "${BS_BOOTSTRAP_DIR:-}/bs.sh" ]]; then
  # shellcheck disable=SC1090
  source "${BS_BOOTSTRAP_DIR}/bs.sh"
fi

# ============================================================================
# ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ / GLOBAL VARIABLES
# ============================================================================

# @global BS_LOADED_MODULES — Loader: registry of loaded modules (guard names) (category: env)
# @global BS_LOADED_MODULES — Loader: реестр загруженных модулей (guard-имена) (категория: env)
declare -g -A BS_LOADED_MODULES

# @global BS_LOAD_STACK — Loader: load stack for cycle detection (category: env)
# @global BS_LOAD_STACK — Loader: стек загрузки для обнаружения циклов (категория: env)
declare -g -a BS_LOAD_STACK=()

# ============================================================================
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ / HELPER FUNCTIONS
# ============================================================================

# @private
# @description Проверяет, доступна ли функция логирования
# @description Checks if logging function is available
log::available() {
    declare -f "$1" >/dev/null 2>&1
}

# @private
# @description Проверить циклические зависимости
# @description Check for circular dependencies
# @param $1 Путь к модулю
# @param $1 Module path
load::__check_circular_dependency() {
    local module_path="${1:?Missing module path}"
    
    # Проверяем, находится ли модуль уже в стеке загрузки
    # Check if module is already in loading stack
    local item
    for item in "${BS_LOAD_STACK[@]}"; do
        if [[ "${item}" == "${module_path}" ]]; then
            echo "BS: error: circular dependency detected: ${BS_LOAD_STACK[*]} -> ${module_path}" >&2
            return 1
        fi
    done
    
    return 0
}

# @private
# @description Загрузить зависимости модуля
# @description Load module dependencies
# @param $1 Путь к модулю
# @param $1 Module path
load::__load_dependencies() {
    local module_path="${1:?Missing module path}"
    local module_file="${BS_ROOT}/${module_path}.sh"

    if [[ ! -f "${module_file}" ]]; then
        echo "BS: error: module file not found: ${module_file}" >&2
        return 1
    fi

    # Парсим комментарии вида: # @depends core/logger, lib/system/utils
    # Parse comments like: # @depends core/logger, lib/system/utils
    local depends_line=""
    local line
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" =~ ^[[:space:]]*#.*@depends[[:space:]]+(.+) ]]; then
            depends_line="${BASH_REMATCH[1]}"
            # Отрезаем trailing-комментарий (всё после очередного #)
            # Strip any trailing comment after another #
            depends_line="${depends_line%%#*}"
            depends_line="${depends_line#"${depends_line%%[![:space:]]*}"}"
            depends_line="${depends_line%"${depends_line##*[![:space:]]}"}"
            break
        fi
    done < "${module_file}"

    if [[ -z "${depends_line}" ]]; then
        return 0  # Нет зависимостей / No dependencies
    fi

    # Загружаем каждую зависимость
    # Load each dependency
    local -a deps
    local IFS=','
    read -ra deps <<< "${depends_line}"

    local dep
    for dep in "${deps[@]}"; do
        dep="${dep#"${dep%%[![:space:]]*}"}"
        dep="${dep%"${dep##*[![:space:]]}"}"
        [[ -z "${dep}" ]] && continue

        if [[ -z "${BS_LOADED_MODULES["${dep}"]:-}" ]]; then
            if ! load "${dep}"; then
                echo "BS: error: failed to load dependency '${dep}' for module '${module_path}'" >&2
                return 1
            fi
        fi
    done

    return 0
}

# 
# ОСНОВНАЯ ФУНКЦИЯ ЗАГРУЗКИ / MAIN LOADING FUNCTION
# 

# @description --strict-shell: refuse a lib/ module whose @shell tier does not
#   fit the shell BS was started from. core/ is the kernel and always allowed.
# @description --strict-shell: отказать модулю lib/, чей tier @shell не подходит
#   оболочке, из которой запущен BS. core/ — ядро, ему можно всегда.
load::__strict_shell_check() {
    local module_path="${1}"
    [[ "${BS_SHELL_STRICT:-0}" == "1" ]] || return 0
    [[ "${module_path}" == lib/* ]] || return 0
    declare -F bs_shell_file_tier >/dev/null || return 0
    local tier origin="${BS_ORIGIN_SHELL:-bash}"
    tier="$(bs_shell_file_tier "${BS_ROOT}/${module_path}.sh")"
    bs_shell_tier_allows "${tier}" "${origin}" && return 0
    printf '%s\n' \
        "BS: модуль '${module_path}' (@shell ${tier}) нельзя исполнять из оболочки '${origin}' (--strict-shell)" \
        "BS: module '${module_path}' (@shell ${tier}) cannot run from shell '${origin}' (--strict-shell)" \
        "    Запустите из подходящей оболочки или уберите --strict-shell / Run from a fitting shell or drop --strict-shell" >&2
    return 1
}

# @description Загрузить модуль по пути относительно BS_ROOT
# @description Load module by path relative to BS_ROOT
# @param $1 Путь к модулю без расширения .sh (например: "core/logger")
# @param $1 Module path without .sh extension (e.g.: "core/logger")
# @example
#   load "core/logger"
load() {
    local module_path="${1:?Missing module path}"
    
    # Валидация BS_ROOT
    # Validate BS_ROOT
    if [[ -z "${BS_ROOT:-}" ]]; then
        echo "BS: error: BS_ROOT is not set" >&2
        return 1
    fi
    
    if [[ ! -d "${BS_ROOT}" ]]; then
        echo "BS: error: BS_ROOT directory not found: ${BS_ROOT}" >&2
        return 1
    fi
    
    # Проверка на повторную загрузку / Check for duplicate loading
    if [[ -n "${BS_LOADED_MODULES["${module_path}"]:-}" ]]; then
        return 0
    fi
    
    # --strict-shell: tier модуля против исходной оболочки / module tier vs the origin shell
    load::__strict_shell_check "${module_path}" || return 1

    # Проверка циклических зависимостей / Check for circular dependencies
    if ! load::__check_circular_dependency "${module_path}"; then
        return 1
    fi
    
    # Добавляем модуль в стек загрузки / Add module to loading stack
    BS_LOAD_STACK+=("${module_path}")
    
    # Загружаем зависимости модуля / Load module dependencies
    if ! load::__load_dependencies "${module_path}"; then
        # Убираем модуль из стека загрузки при ошибке / Pop module from loading stack on error
        BS_LOAD_STACK=("${BS_LOAD_STACK[@]:0:${#BS_LOAD_STACK[@]}-1}")
        return 1
    fi
    
    # Загружаем файл модуля / Load module file
    local module_file="${BS_ROOT}/${module_path}.sh"
    if ! source "${module_file}"; then
        echo "BS: error: failed to load module '${module_path}'" >&2
        # Убираем модуль из стека загрузки при ошибке / Pop module from loading stack on error
        BS_LOAD_STACK=("${BS_LOAD_STACK[@]:0:${#BS_LOAD_STACK[@]}-1}")
        return 1
    fi
    
    # Удаляем модуль из стека загрузки / Remove module from loading stack
    BS_LOAD_STACK=("${BS_LOAD_STACK[@]:0:${#BS_LOAD_STACK[@]}-1}")
    
    # Помечаем модуль как загруженный / Mark module as loaded
    BS_LOADED_MODULES["${module_path}"]=1
    
    return 0
}

# @description Полное имя функции для обратной совместимости
# @description Full function name for backward compatibility
bs::load() {
    load "$@"
}