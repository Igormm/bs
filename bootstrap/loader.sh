#!/usr/bin/env bs
#
# bootstrap/loader.sh — модуль загрузки с предотвращением повторного подключения
# bootstrap/loader.sh — loading module with duplicate loading prevention
#

set -euo pipefail

# Ассоциативный массив для отслеживания загруженных модулей
# Associative array for tracking loaded modules
declare -g -A BOSA_LOADED_MODULES

# @description Загрузить модуль по пути относительно BOSA_ROOT
# @description Load module by path relative to BOSA_ROOT
# @param $1 Путь к модулю без расширения .sh (например: "core/logger")
# @param $1 Module path without .sh extension (e.g.: "core/logger")
# @example
#   load "core/logger"
#   load "lib/system/utils"
load() {
    local module_path="${1:?Missing module path}"
    
    # Проверка на повторную загрузку / Check for duplicate loading
    if [[ -n "${BOSA_LOADED_MODULES["${module_path}"]:-}" ]]; then
        log::debug "Module already loaded: ${module_path}" 2>/dev/null || true
        return 0
    fi
    
    local full_path="${BOSA_ROOT}/${module_path}.sh"
    
    # Проверка существования файла / Check file existence
    if [[ ! -f "${full_path}" ]]; then
        log::error "Module not found: ${full_path}" 2>/dev/null || {
            echo "BS: error: module not found: ${full_path}" >&2
        }
        return 1
    fi
    
    # Загрузка модуля / Loading module
    source "${full_path}"
    
    # Отметка как загруженного / Mark as loaded
    BOSA_LOADED_MODULES["${module_path}"]="1"
    
    log::debug "Module loaded: ${module_path}" 2>/dev/null || true
    return 0
}

# @description Алиас для обратной совместимости
# @description Backward compatibility alias
import() {
    load "$@"
}

# @description Полное имя функции для обратной совместимости
# @description Full function name for backward compatibility
BS::load() {
    load "$@"
}
