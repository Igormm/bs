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
if [[ -f "$(dirname -- "${BASH_SOURCE[0]}")/bs.sh" ]]; then
  # shellcheck disable=SC1090
  source "$(dirname -- "${BASH_SOURCE[0]}")/bs.sh"
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