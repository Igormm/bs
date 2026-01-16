#!/usr/bin/env bs
# shellcheck shell=bash
#
# bootstrap/loader.sh — модуль загрузки с ленивой загрузкой и предотвращением повторного подключения
# bootstrap/loader.sh — loading module with lazy loading and duplicate loading prevention
#

set -euo pipefail

# ============================================================================
# ПРОВЕРКА ВЕРСИИ BASH / BASH VERSION CHECK
# ============================================================================

# Проверка версии Bash на наличие необходимых возможностей
# Check Bash version for required features
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
    echo "BS: ERROR: Bash 4.0+ required for associative arrays" >&2
    exit 1
fi

# ============================================================================
# ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ / GLOBAL VARIABLES
# ============================================================================

# Ассоциативный массив для отслеживания загруженных модулей
# Associative array for tracking loaded modules
declare -g -A BOSA_LOADED_MODULES

# Ассоциативный массив для отслеживания модулей, ожидающих ленивой загрузки
# Associative array for tracking modules pending lazy loading
declare -g -A BOSA_LAZY_MODULES

# Ассоциативный массив для отслеживания функций, связанных с модулями
# Associative array for tracking functions associated with modules
declare -g -A BOSA_MODULE_FUNCTIONS

# Глобальный стек загрузки для обнаружения циклов
# Global loading stack for cycle detection
declare -g -a BOSA_LOAD_STACK=()

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
    for item in "${BOSA_LOAD_STACK[@]}"; do
        if [[ "${item}" == "${module_path}" ]]; then
            echo "BS: error: circular dependency detected: ${BOSA_LOAD_STACK[*]} -> ${module_path}" >&2
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
    local module_file="${BOSA_ROOT}/${module_path}.sh"
    
    # Парсим комментарии вида: # @depends core/logger, lib/system/utils
    # Parse comments like: # @depends core/logger, lib/system/utils
    local depends_line
    depends_line=$(grep -m1 "^[[:space:]]*#.*@depends" "${module_file}" 2>/dev/null || echo "")
    
    if [[ -z "${depends_line}" ]]; then
        return 0  # Нет зависимостей / No dependencies
    fi
    
    # Извлекаем список зависимостей
    # Extract dependency list
    local deps
    deps=$(echo "${depends_line}" | sed 's/.*@depends[[:space:]]*//; s/[[:space:]]*$//')
    
    # Загружаем каждую зависимость
    # Load each dependency
    local dep
    for dep in ${deps//,/ }; do
        dep=$(echo "${dep}" | xargs)  # Trim whitespace
        if [[ -z "${dep}" ]]; then
            continue
        fi
        
        if [[ -z "${BOSA_LOADED_MODULES["${dep}"]:-}" ]]; then
            if ! load "${dep}"; then
                echo "BS: error: failed to load dependency '${dep}' for module '${module_path}'" >&2
                return 1
            fi
        fi
    done
    
    return 0
}

# @private
# @description Регистрировать функции модуля для ленивой загрузки
# @description Register module functions for lazy loading
# @param $1 Путь к модулю
# @param $1 Module path
# @param $2 Список функций через запятую
# @param $2 List of functions separated by comma
load::__register_lazy_functions() {
    local module_path="${1:?Missing module path}"
    local module_functions="${2:?Missing module functions}"
    
    # Парсим список функций
    # Parse function list
    local func
    for func in ${module_functions//,/ }; do
        func=$(echo "${func}" | xargs)  # Trim whitespace
        if [[ -z "${func}" ]]; then
            continue
        fi
        
        # Регистрируем функцию
        # Register function
        BOSA_MODULE_FUNCTIONS["${func}"]="${module_path}"
        
        # Создаем wrapper для автоматической загрузки при вызове
        # Create wrapper for automatic loading on call
        eval "
            ${func}() {
                # Загружаем модуль, если не загружен
                # Load module if not loaded
                if [[ -z \"\${BOSA_LOADED_MODULES['${module_path}']:-}\" ]]; then
                    load '${module_path}' 'eager' || return 1
                fi
                # Вызываем оригинальную функцию
                # Call the original function
                ${func}_original \"\$@\"
            }
        "
    done
}

# ============================================================================
# ОСНОВНАЯ ФУНКЦИЯ ЗАГРУЗКИ / MAIN LOADING FUNCTION
# ============================================================================

# @description Загрузить модуль по пути относительно BOSA_ROOT (немедленная или ленивая загрузка)
# @description Load module by path relative to BOSA_ROOT (immediate or lazy loading)
# @param $1 Путь к модулю без расширения .sh (например: "core/logger")
# @param $1 Module path without .sh extension (e.g.: "core/logger")
# @param $2 Режим загрузки: "lazy" для ленивой загрузки (по умолчанию: "eager")
# @param $2 Loading mode: "lazy" for lazy loading (default: "eager")
# @param $3 Функции модуля, разделённые запятой (опционально, для ленивой загрузки)
# @param $3 Module functions separated by comma (optional, for lazy loading)
# @example
#   load "core/logger"                    # Eager loading (default)
#   load "core/logger" "eager"           # Explicit eager loading
#   load "core/logger" "lazy"            # Lazy loading
#   load "lib/data/algorithms" "lazy" "algorithms::sort,algorithms::search"
load() {
    local module_path="${1:?Missing module path}"
    local mode="${2:-eager}"  # Default to eager loading for backward compatibility
    local module_functions="${3:-}"
    
    # Валидация BOSA_ROOT
    # Validate BOSA_ROOT
    if [[ -z "${BOSA_ROOT:-}" ]]; then
        echo "BS: error: BOSA_ROOT is not set" >&2
        return 1
    fi
    
    if [[ ! -d "${BOSA_ROOT}" ]]; then
        echo "BS: error: BOSA_ROOT directory not found: ${BOSA_ROOT}" >&2
        return 1
    fi
    
    # Проверка формата списка функций при ленивой загрузке
    # Validate function list format for lazy loading
    if [[ "${mode}" == "lazy" && -n "${module_functions}" ]]; then
        # Проверка корректности формата списка функций
        # Validate function list format
        if [[ ! "${module_functions}" =~ ^[a-zA-Z_][a-zA-Z0-9_:]*([,][a-zA-Z_][a-zA-Z0-9_:]*)*$ ]]; then
            {
                echo "BS: error: invalid function list format: ${module_functions}" >&2
                echo "BS: hint: use format like 'func1,namespace::func2,other::func3'" >&2
            } >&2
            return 1
        fi
    fi
    
    # Проверка на повторную загрузку / Check for duplicate loading
    if [[ -n "${BOSA_LOADED_MODULES["${module_path}"]:-}" ]]; then
        if log::available log::debug; then
            log::debug "Module already loaded: ${module_path}"
        fi
        return 0
    fi
    
    # Проверка циклических зависимостей
    # Check for circular dependencies
    if ! load::__check_circular_dependency "${module_path}"; then
        return 1
    fi
    
    # Добавляем модуль в стек загрузки
    # Add module to loading stack
    BOSA_LOAD_STACK+=("${module_path}")
    
    local module_file="${BOSA_ROOT}/${module_path}.sh"
    
    # Проверка существования файла / Check file existence
    if [[ ! -f "${module_file}" ]]; then
        # Удаляем модуль из стека загрузки
        # Remove module from loading stack
        BOSA_LOAD_STACK=("${BOSA_LOAD_STACK[@]:0:${#BOSA_LOAD_STACK[@]}-1}")
        
        {
            echo "BS: error: module not found: ${module_path}" >&2
            echo "BS: hint: expected file: ${module_file}" >&2
        } >&2
        return 1
    fi
    
    # Загрузка зависимостей
    # Load dependencies
    if ! load::__load_dependencies "${module_path}"; then
        # Удаляем модуль из стека загрузки
        # Remove module from loading stack
        BOSA_LOAD_STACK=("${BOSA_LOAD_STACK[@]:0:${#BOSA_LOAD_STACK[@]}-1}")
        return 1
    fi
    
    # Безопасная загрузка модуля с перехватом ошибок
    # Safe module loading with error capture
    local load_error
    if ! load_error=$(source "${module_file}" 2>&1); then
        # Удаляем модуль из стека загрузки
        # Remove module from loading stack
        BOSA_LOAD_STACK=("${BOSA_LOAD_STACK[@]:0:${#BOSA_LOAD_STACK[@]}-1}")
        echo "BS: error: failed to load module: ${module_path}" >&2
        echo "BS: details: ${load_error}" >&2
        return 1
    fi
    
    # Удаляем модуль из стека загрузки
    # Remove module from loading stack
    BOSA_LOAD_STACK=("${BOSA_LOAD_STACK[@]:0:${#BOSA_LOAD_STACK[@]}-1}")
    
    # Отметка как загруженного / Mark as loaded
    BOSA_LOADED_MODULES["${module_path}"]="1"
    
    # Определение режима загрузки / Determine loading mode
    case "${mode}" in
        eager|"")
            # Удаление из ленивых модулей, если там была / Remove from lazy modules if present
            unset "BOSA_LAZY_MODULES[${module_path}]" 2>/dev/null || true
            
            if log::available log::debug; then
                log::debug "Module loaded (eager): ${module_path}"
            fi
            return 0
            ;;
        lazy)
            # Регистрация модуля для ленивой загрузки
            # Register module for lazy loading
            BOSA_LAZY_MODULES["${module_path}"]="${module_functions}"
            
            # Если указаны функции, сохранить их для отслеживания
            # If functions are specified, save them for tracking
            if [[ -n "${module_functions}" ]]; then
                # Регистрация функций для ленивой загрузки
                # Register functions for lazy loading
                load::__register_lazy_functions "${module_path}" "${module_functions}"
                
                # Создание обёрток для функций, которые будут загружать модуль при первом вызове
                # Create wrappers for functions that will load the module on first call
                local func_name
                IFS=',' read -ra funcs <<< "${module_functions}"
                for func_name in "${funcs[@]}"; do
                    create_lazy_function_wrapper "${func_name}" "${module_path}"
                done
            fi
            
            if log::available log::debug; then
                log::debug "Module registered for lazy loading: ${module_path}"
            fi
            return 0
            ;;
        *)
            {
                echo "BS: error: invalid loading mode: ${mode}, use 'eager' or 'lazy'" >&2
                echo "BS: hint: valid modes are 'eager' (immediate loading) or 'lazy' (deferred loading)" >&2
            } >&2
            return 1
            ;;
    esac
}

# ============================================================================
# АЛИАСЫ ДЛЯ УДОБСТВА / CONVENIENCE ALIASES
# ============================================================================

# @description Загрузить модуль немедленно (алиас для load с eager режимом)
# @description Load module immediately (alias for load with eager mode)
# @param $1 Путь к модулю
# @example
#   load_now "core/logger"
load_now() {
    load "$1" "eager"
}

# @description Загрузить модуль лениво (алиас для load с lazy режимом)
# @description Load module lazily (alias for load with lazy mode)
# @param $1 Путь к модулю
# @param $2 Функции модуля, разделённые запятой (опционально)
# @example
#   load_lazy "lib/data/algorithms" "algorithms::sort,algorithms::search"
load_lazy() {
    load "$1" "lazy" "${2:-}"
}

# ============================================================================
# ФУНКЦИИ ЛЕНИВОЙ ЗАГРУЗКИ / LAZY LOADING FUNCTIONS
# ============================================================================

# @description Создать обёртку функции для ленивой загрузки модуля при первом вызове
# @description Create function wrapper for lazy loading module on first call
# @param $1 Имя функции
# @param $1 Function name
# @param $2 Путь к модулю
# @param $2 Module path
# @example
#   create_lazy_function_wrapper "algorithms::sort_array" "lib/data/algorithms"
create_lazy_function_wrapper() {
    local func_name="${1:?Missing function name}"
    local module_path="${2:?Missing module path}"
    
    # Создание функции-обёртки, которая загружает модуль при первом вызове
    # Create wrapper function that loads module on first call
    eval "
    ${func_name}() {
        # Проверка, загружен ли модуль / Check if module is loaded
        if [[ -z \"\${BOSA_LOADED_MODULES['${module_path}']:-}\" ]]; then
            # Загрузить модуль при первом вызове функции
            # Load module on first function call
            load '${module_path}' 'eager' || {
                if command -v log::error >/dev/null 2>&1; then
                    log::error \"Failed to load module: ${module_path}\"
                else
                    echo \"BS: error: Failed to load module: ${module_path}\" >&2
                fi
                return 1
            }
        fi
        
        # Вызвать реальную функцию / Call the actual function
        # Используется встроенная команда 'command' для избежания рекурсии
        # Use 'command' builtin to avoid recursion
        \"\${FUNCNAME[0]}__impl\" \"\${@}\"
    }
    
    # Внутренняя реализация, которая будет переопределена после загрузки модуля
    # Internal implementation that will be replaced after module loading
    ${func_name}__impl() {
        # После загрузки модуля эта функция будет заменена настоящей реализацией
        # After module loading, this function will be replaced with the real implementation
        if command -v log::error >/dev/null 2>&1; then
            log::error \"Function ${func_name} was not properly implemented after loading module ${module_path}\"
        else
            echo \"BS: error: Function ${func_name} was not properly implemented after loading module ${module_path}\" >&2
        fi
        return 1
    }
    "
    
    if log::available log::debug; then
        log::debug "Created lazy wrapper for function: ${func_name}"
    fi
}

# @description Загрузить все зарегистрированные ленивые модули
# @description Load all registered lazy modules
# @example
#   load_lazy_all
load_lazy_all() {
    local module_path
    
    if log::available log::debug; then
        log::debug "Loading all lazy modules..."
    fi
    
    # Итерация по всем ленивым модулям / Iterate over all lazy modules
    for module_path in "${!BOSA_LAZY_MODULES[@]}"; do
        # Проверка, не загружен ли модуль уже / Check if not already loaded
        if [[ -z "${BOSA_LOADED_MODULES["${module_path}"]:-}" ]]; then
            load "${module_path}" "eager" || {
                if log::available log::warn; then
                    log::warn "Failed to load lazy module: ${module_path}"
                else
                    echo "BS: warning: Failed to load lazy module: ${module_path}" >&2
                fi
            }
        fi
    done
    
    if log::available log::debug; then
        log::debug "All lazy modules loaded"
    fi
    return 0
}

# @description Загрузить конкретный ленивый модуль по требованию
# @description Load specific lazy module on demand
# @param $1 Путь к модулю
# @param $1 Module path
# @example
#   load_lazy_on_demand "lib/data/algorithms"
load_lazy_on_demand() {
    local module_path="${1:?Missing module path}"
    
    # Проверка, зарегистрирован ли модуль для ленивой загрузки
    # Check if module is registered for lazy loading
    if [[ -z "${BOSA_LAZY_MODULES["${module_path}"]:-}" ]]; then
        if log::available log::warn; then
            log::warn "Module not registered for lazy loading: ${module_path}"
        else
            echo "BS: warning: Module not registered for lazy loading: ${module_path}" >&2
        fi
        return 1
    fi
    
    # Проверка, не загружен ли модуль уже / Check if not already loaded
    if [[ -n "${BOSA_LOADED_MODULES["${module_path}"]:-}" ]]; then
        if log::available log::debug; then
            log::debug "Module already loaded: ${module_path}"
        fi
        return 0
    fi
    
    # Загрузить модуль / Load module
    load "${module_path}" "eager"
}

# ============================================================================
# УТИЛИТЫ ДЛЯ УПРАВЛЕНИЯ ЛЕНИВОЙ ЗАГРУЗКОЙ / LAZY LOADING UTILITIES
# ============================================================================

# @description Получить статус ленивых модулей
# @description Get lazy modules status
# @example
#   load_lazy_status
load_lazy_status() {
    echo "=== Lazy Loading Status ==="
    echo "Registered lazy modules: ${#BOSA_LAZY_MODULES[@]}"
    
    if [[ ${#BOSA_LAZY_MODULES[@]} -gt 0 ]]; then
        echo ""
        echo "Lazy modules:"
        for module in "${!BOSA_LAZY_MODULES[@]}"; do
            local status="pending"
            if [[ -n "${BOSA_LOADED_MODULES["${module}"]:-}" ]]; then
                status="loaded"
            fi
            echo "  - ${module} [${status}]"
        done
    fi
    
    echo ""
    echo "Loaded modules: ${#BOSA_LOADED_MODULES[@]}"
    if [[ ${#BOSA_LOADED_MODULES[@]} -gt 0 ]]; then
        echo "Loaded modules:"
        for module in "${!BOSA_LOADED_MODULES[@]}"; do
            echo "  - ${module}"
        done
    fi
}

# @description Очистить все ленивые модули
# @description Clear all lazy modules
# @example
#   load_lazy_clear
load_lazy_clear() {
    # Keep loaded modules but clear lazy registration
    BOSA_LAZY_MODULES=()
    BOSA_MODULE_FUNCTIONS=()
    if log::available log::debug; then
        log::debug "Cleared all lazy module registrations"
    fi
}

# ============================================================================
# ОБРАТНАЯ СОВМЕСТИМОСТЬ / BACKWARD COMPATIBILITY
# ============================================================================

# @description Алиас для обратной совместимости
# @description Backward compatibility alias
import() {
    load "$@"
}

# @description Полное имя функции для обратной совместимости
# @description Full function name for backward compatibility
bs::load() {
    load "$@"
}

# @description Алиас для ленивой загрузки
# @description Alias for lazy loading
bs::load_lazy() {
    load "$1" "lazy" "${2:-}"
}