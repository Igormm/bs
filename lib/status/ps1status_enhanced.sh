#!/usr/bin/env bs
#
# BS Framework - PS1 Status Module
# Фреймворк BS - Модуль PS1 статусов
#
# НАЗНАЧЕНИЕ: Модуль для отображения статуса системы в командной строке
# PURPOSE: Module for displaying system status in command line
#
# ЗАВИСИМОСТИ: bash 4.0+, core/const.sh, core/logger.sh, core/errorhandler.sh
# DEPENDENCIES: bash 4.0+, core/const.sh, core/logger.sh, core/errorhandler.sh
#
# ИСПОЛЬЗУЕТСЯ: В интерактивных shell для мониторинга системы
# USAGE: In interactive shells for system monitoring
#

# ════════════════════════════════════════════════════════════════════════════════
# ИНИЦИАЛИЗАЦИЯ МОДУЛЯ / MODULE INITIALIZATION
# ════════════════════════════════════════════════════════════════════════════════

# Подключение зависимостей / Import dependencies
# ИСПОЛЬЗУЕТСЯ: Для доступа к константам, логированию и обработке ошибок
# USAGE: For access to constants, logging and error handling
source "${BS_HOME}/core/const.sh"        # Константы фреймворка / Framework constants
source "${BS_HOME}/core/logger.sh"       # Система логирования / Logging system
source "${BS_HOME}/core/errorhandler.sh" # Обработчик ошибок / Error handler

# ════════════════════════════════════════════════════════════════════════════════
# КОНСТАНТЫ МОДУЛЯ / MODULE CONSTANTS
# ════════════════════════════════════════════════════════════════════════════════

# Префикс для переменных модуля / Module variable prefix
# НАЗНАЧЕНИЕ: Избегает конфликтов имен с другими модулями
# PURPOSE: Prevents name conflicts with other modules
readonly PS1_STATUS_MODULE_PREFIX="PS1_STATUS"

# Каталог для кэша статусов / Status cache directory
# НАЗНАЧЕНИЕ: Хранение временных данных о статусе компонентов
# PURPOSE: Storing temporary status data of components
readonly PS1_STATUS_CACHE_DIR="/tmp/bs_ps1_status"

# ════════════════════════════════════════════════════════════════════════════════
# ФУНКЦИЯ: ps1status::init
# FUNCTION: ps1status::init
#
# НАЗНАЧЕНИЕ: Инициализация модуля PS1 статусов
# PURPOSE: Initialize PS1 status module
#
# АРГУМЕНТЫ:
# ARGUMENTS:
#   Нет / None
#
# ВОЗВРАЩАЕТ:
# RETURNS:
#   0 - Успех / Success
#   1 - Ошибка / Error
#
# ЗАВИСИМОСТИ:
# DEPENDENCIES:
#   - core/const.sh (константы / constants)
#   - core/logger.sh (логирование / logging)
#   - core/errorhandler.sh (обработка ошибок / error handling)
#
# ИСПОЛЬЗУЕТСЯ В:
# USED IN:
#   - Инициализации фреймворка / Framework initialization
#   - Настройке интерактивной сессии / Interactive session setup
#
# ПРИМЕР:
# EXAMPLE:
#   ps1status::init
#
# ════════════════════════════════════════════════════════════════════════════════
ps1status::init() {
    # Имя функции для логирования / Function name for logging
    # НАЗНАЧЕНИЕ: Используется для идентификации в логах
    # PURPOSE: Used for identification in logs
    local func_name="ps1status::init"
    
    # Логирование начала инициализации / Log initialization start
    # НАЗНАЧЕНИЕ: Информирование о начале процесса
    # PURPOSE: Inform about process start
    log::info "Инициализация модуля PS1 статусов..."
    log::info "Initializing PS1 Status module..."
    
    # Создание каталога кэша / Create cache directory
    # НАЗНАЧЕНИЕ: Обеспечение существования каталога для временных файлов
    # PURPOSE: Ensure cache directory exists for temporary files
    if [[ ! -d "${PS1_STATUS_CACHE_DIR}" ]]; then
        mkdir -p "${PS1_STATUS_CACHE_DIR}" || {
            # Обработка ошибки создания каталога / Handle directory creation error
            # НАЗНАЧЕНИЕ: Логирование ошибки и продолжение работы без кэша
            # PURPOSE: Log error and continue without cache
            log::warn "Не удалось создать каталог кэша: ${PS1_STATUS_CACHE_DIR}"
            log::warn "Failed to create cache directory: ${PS1_STATUS_CACHE_DIR}"
        }
    fi
    
    # Инициализация компонентов по умолчанию / Initialize default components
    # НАЗНАЧЕНИЕ: Включение базовых компонентов статуса
    # PURPOSE: Enable basic status components
    ps1status::enable_component "wireguard"
    ps1status::enable_component "network"
    ps1status::enable_component "system"
    
    # Логирование успешной инициализации / Log successful initialization
    # НАЗНАЧЕНИЕ: Подтверждение готовности модуля
    # PURPOSE: Confirm module readiness
    log::success "Модуль PS1 статусов инициализирован успешно"
    log::success "PS1 Status module initialized successfully"
}

# КОНЕЦ ФУНКЦИИ: ps1status::init
# END OF FUNCTION: ps1status::init
#

# ════════════════════════════════════════════════════════════════════════════════
# ФУНКЦИЯ: ps1status::enable_component
# FUNCTION: ps1status::enable_component
#
# НАЗНАЧЕНИЕ: Включение компонента статуса
# PURPOSE: Enable status component
#
# АРГУМЕНТЫ:
# ARGUMENTS:
#   $1 - Имя компонента / Component name
#
# ВОЗВРАЩАЕТ:
# RETURNS:
#   0 - Успех / Success
#   1 - Ошибка (неверный аргумент) / Error (invalid argument)
#
# ЗАВИСИМОСТИ:
# DEPENDENCIES:
#   - log::info (логирование / logging)
#
# ИСПОЛЬЗУЕТСЯ В:
# USED IN:
#   - ps1status::init (инициализация / initialization)
#   - Интерактивной настройке / Interactive configuration
#
# ПРИМЕР:
# EXAMPLE:
#   ps1status::enable_component "wireguard"
#   ps1status::enable_component "network"
#
# ════════════════════════════════════════════════════════════════════════════════
ps1status::enable_component() {
    # Имя функции для логирования / Function name for logging
    local func_name="ps1status::enable_component"
    
    # Имя компонента из аргумента / Component name from argument
    # НАЗНАЧЕНИЕ: Получение имени включаемого компонента
    # PURPOSE: Get name of component to enable
    local component="${1:-}"
    
    # Проверка аргумента / Argument validation
    # НАЗНАЧЕНИЕ: Обеспечение наличия обязательного аргумента
    # PURPOSE: Ensure required argument is provided
    if [[ -z "${component}" ]]; then
        # Логирование ошибки / Log error
        # НАЗНАЧЕНИЕ: Информирование о неверном использовании
        # PURPOSE: Inform about incorrect usage
        log::error "${func_name}: Требуется имя компонента"
        log::error "${func_name}: Component name required"
        return 1
    fi
    
    # Логирование включения компонента / Log component enabling
    # НАЗНАЧЕНИЕ: Отслеживание изменений конфигурации
    # PURPOSE: Track configuration changes
    log::info "Включение компонента: ${component}"
    log::info "Enabling component: ${component}"
    
    # Добавление компонента в список активных / Add to active list
    # НАЗНАЧЕНИЕ: Сохранение состояния компонента
    # PURPOSE: Save component state
    PS1_STATUS_ACTIVE_COMPONENTS+=("${component}")
    
    # Создание файла-флага / Create flag file
    # НАЗНАЧЕНИЕ: Маркер активности для других процессов
    # PURPOSE: Activity marker for other processes
    touch "${PS1_STATUS_CACHE_DIR}/${component}.enabled"
    
    # Успешное завершение / Successful completion
    # НАЗНАЧЕНИЕ: Возврат кода успеха
    # PURPOSE: Return success code
    return 0
}

# КОНЕЦ ФУНКЦИИ: ps1status::enable_component
# END OF FUNCTION: ps1status::enable_component
#

# ════════════════════════════════════════════════════════════════════════════════
# ФУНКЦИЯ: ps1status::get_wireguard_status
# FUNCTION: ps1status::get_wireguard_status
#
# НАЗНАЧЕНИЕ: Получение статуса WireGuard VPN
# PURPOSE: Get WireGuard VPN status
#
# АРГУМЕНТЫ:
# ARGUMENTS:
#   Нет / None
#
# ВОЗВРАЩАЕТ:
# RETURNS:
#   Строка статуса / Status string
#
# ЗАВИСИМОСТИ:
# DEPENDENCIES:
#   - wg (утилита WireGuard)
#   - ip (утилита iproute2)
#
# ИСПОЛЬЗУЕТСЯ В:
# USED IN:
#   - ps1status::update / PS1 status update
#   - Мониторинге VPN / VPN monitoring
#
# ════════════════════════════════════════════════════════════════════════════════
ps1status::get_wireguard_status() {
    # Имя функции для логирования / Function name for logging
    local func_name="ps1status::get_wireguard_status"
    
    # Файл статуса WireGuard / WireGuard status file
    # НАЗНАЧЕНИЕ: Кэширование последнего известного статуса
    # PURPOSE: Caching last known status
    local status_file="${PS1_STATUS_CACHE_DIR}/wireguard.status"
    
    # Инициализация статуса / Initialize status
    # НАЗНАЧЕНИЕ: Начальное значение - отключено
    # PURPOSE: Default value - disabled
    local status="down"
    
    # Проверка существования файла статуса / Check status file existence
    # НАЗНАЧЕНИЕ: Использование кэша для ускорения
    # PURPOSE: Use cache for performance
    if [[ -f "${status_file}" ]]; then
        # Чтение статуса из файла / Read status from file
        # НАЗНАЧЕНИЕ: Получение сохраненного значения
        # PURPOSE: Get saved value
        status=$(cat "${status_file}")
    fi
    
    # Форматирование вывода / Format output
    # НАЗНАЧЕНИЕ: Создание визуального индикатора
    # PURPOSE: Create visual indicator
    case "${status}" in
        up)
            # VPN подключен / VPN connected
            # НАЗНАЧЕНИЕ: Зеленый индикатор "вверх"
            # PURPOSE: Green "up" indicator
            echo -e "${PS1_STATUS_COLOR_WIREGUARD_UP}WG↑${PS1_STATUS_COLOR_RESET}"
            ;;
        down)
            # VPN отключен / VPN disconnected
            # НАЗНАЧЕНИЕ: Красный индикатор "вниз"
            # PURPOSE: Red "down" indicator
            echo -e "${PS1_STATUS_COLOR_WIREGUARD_DOWN}WG↓${PS1_STATUS_COLOR_RESET}"
            ;;
        *)
            # Неизвестный статус / Unknown status
            # НАЗНАЧЕНИЕ: Желтый индикатор "вопрос"
            # PURPOSE: Yellow "question" indicator
            echo -e "${PS1_STATUS_COLOR_WIREGUARD_DOWN}WG?${PS1_STATUS_COLOR_RESET}"
            ;;
    esac
}

# КОНЕЦ ФУНКЦИИ: ps1status::get_wireguard_status
# END OF FUNCTION: ps1status::get_wireguard_status
#

# ════════════════════════════════════════════════════════════════════════════════
# ЭКСПОРТ ФУНКЦИЙ / FUNCTION EXPORTS
# ════════════════════════════════════════════════════════════════════════════════

# Делаем функции доступными для других скриптов / Make functions available to other scripts
# НАЗНАЧЕНИЕ: Экспорт в глобальное пространство имен
# PURPOSE: Export to global namespace
export -f ps1status::init
export -f ps1status::enable_component
export -f ps1status::get_wireguard_status

# ════════════════════════════════════════════════════════════════════════════════
# ИНИЦИАЛИЗАЦИЯ ПРИ ИМПОРТЕ / INITIALIZATION ON IMPORT
# ════════════════════════════════════════════════════════════════════════════════

# Автоматическая инициализация при подключении / Auto-initialize on import
# НАЗНАЧЕНИЕ: Удобство использования - модуль готов сразу
# PURPOSE: Convenience - module is ready immediately
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Запуск как скрипт / Running as script
    log::info "Модуль PS1 статусов запущен напрямую"
    log::info "PS1 Status module run directly"
else
    # Импорт как модуль / Import as module
    log::debug "Модуль PS1 статусов импортирован"
    log::debug "PS1 Status module imported"
fi
