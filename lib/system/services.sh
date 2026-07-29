#!/usr/bin/env bs
# services.sh — Service management for system setup / Управление сервисами для настройки
# системы

# @description Start a system service / Запустить системный сервис
# @param $1 Service name / Имя сервиса
# @example
#   system::services::start "sshd"
system::services::start() {
    local service="${1}"
    
    if [[ -z "${service}" ]]; then
        log::warn "Service name not specified"
        return 1
    fi
    
    # Try systemd first / Попробовать systemd сначала
    if command -v systemctl >/dev/null 2>&1; then
        systemctl start "${service}" 2>/dev/null || true
        log::info "Service ${service} started (systemd)"
    else
        # Fallback to service command / Резервный вариант команды service
        if command -v service >/dev/null 2>&1; then
            service "${service}" start 2>/dev/null || true
            log::info "Service ${service} started (service)"
        else
            # Fallback to direct init script / Резервный вариант прямого init скрипта
            if [[ -x "/etc/init.d/${service}" ]]; then
                "/etc/init.d/${service}" start 2>/dev/null || true
                log::info "Service ${service} started (init.d)"
            else
                log::warn "No suitable method to start service ${service}"
                return 1
            fi
        fi
    fi
}

# @description Stop a system service / Остановить системный сервис
# @param $1 Service name / Имя сервиса
# @example
#   system::services::stop "sshd"
system::services::stop() {
    local service="${1}"
    
    if [[ -z "${service}" ]]; then
        log::warn "Service name not specified"
        return 1
    fi
    
    # Try systemd first / Попробовать systemd сначала
    if command -v systemctl >/dev/null 2>&1; then
        systemctl stop "${service}" 2>/dev/null || true
        log::info "Service ${service} stopped (systemd)"
    else
        # Fallback to service command / Резервный вариант команды service
        if command -v service >/dev/null 2>&1; then
            service "${service}" stop 2>/dev/null || true
            log::info "Service ${service} stopped (service)"
        else
            # Fallback to direct init script / Резервный вариант прямого init скрипта
            if [[ -x "/etc/init.d/${service}" ]]; then
                "/etc/init.d/${service}" stop 2>/dev/null || true
                log::info "Service ${service} stopped (init.d)"
            else
                log::warn "No suitable method to stop service ${service}"
                return 1
            fi
        fi
    fi
}

# @description Enable a system service to start at boot / Включить автозапуск системного
# сервиса при загрузке
# @param $1 Service name / Имя сервиса
# @example
#   system::services::enable "sshd"
system::services::enable() {
    local service="${1}"
    
    if [[ -z "${service}" ]]; then
        log::warn "Service name not specified"
        return 1
    fi
    
    # Try systemd first / Попробовать systemd сначала
    if command -v systemctl >/dev/null 2>&1; then
        systemctl enable "${service}" 2>/dev/null || true
        log::info "Service ${service} enabled (systemd)"
    else
        # Fallback to update-rc.d or chkconfig / Резервный вариант update-rc.d или
        # chkconfig
        if command -v update-rc.d >/dev/null 2>&1; then
            update-rc.d "${service}" defaults 2>/dev/null || true
            log::info "Service ${service} enabled (update-rc.d)"
        elif command -v chkconfig >/dev/null 2>&1; then
            chkconfig "${service}" on 2>/dev/null || true
            log::info "Service ${service} enabled (chkconfig)"
        else
            log::warn "No suitable method to enable service ${service}"
            return 1
        fi
    fi
}

# @description Disable a system service from starting at boot / Отключить автозапуск
# системного сервиса при загрузке
# @param $1 Service name / Имя сервиса
# @example
#   system::services::disable "sshd"
system::services::disable() {
    local service="${1}"
    
    if [[ -z "${service}" ]]; then
        log::warn "Service name not specified"
        return 1
    fi
    
    # Try systemd first / Попробовать systemd сначала
    if command -v systemctl >/dev/null 2>&1; then
        systemctl disable "${service}" 2>/dev/null || true
        log::info "Service ${service} disabled (systemd)"
    else
        # Fallback to update-rc.d or chkconfig / Резервный вариант update-rc.d или
        # chkconfig
        if command -v update-rc.d >/dev/null 2>&1; then
            update-rc.d -f "${service}" remove 2>/dev/null || true
            log::info "Service ${service} disabled (update-rc.d)"
        elif command -v chkconfig >/dev/null 2>&1; then
            chkconfig "${service}" off 2>/dev/null || true
            log::info "Service ${service} disabled (chkconfig)"
        else
            log::warn "No suitable method to disable service ${service}"
            return 1
        fi
    fi
}

# @description Restart a system service / Перезапустить системный сервис
# @param $1 Service name / Имя сервиса
# @example
#   system::services::restart "sshd"
system::services::restart() {
    local service="${1}"
    
    if [[ -z "${service}" ]]; then
        log::warn "Service name not specified"
        return 1
    fi
    
    # Try systemd first / Попробовать systemd сначала
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart "${service}" 2>/dev/null || true
        log::info "Service ${service} restarted (systemd)"
    else
        # Fallback to service command / Резервный вариант команды service
        if command -v service >/dev/null 2>&1; then
            service "${service}" restart 2>/dev/null || true
            log::info "Service ${service} restarted (service)"
        else
            # Fallback to direct init script / Резервный вариант прямого init скрипта
            if [[ -x "/etc/init.d/${service}" ]]; then
                "/etc/init.d/${service}" restart 2>/dev/null || true
                log::info "Service ${service} restarted (init.d)"
            else
                log::warn "No suitable method to restart service ${service}"
                return 1
            fi
        fi
    fi
}

# @description Check if a service is active/running / Проверить, активен ли сервис/запущен
# ли
# @param $1 Service name / Имя сервиса
# @example
#   system::services::status "sshd"
system::services::status() {
    local service="${1}"
    
    if [[ -z "${service}" ]]; then
        log::warn "Service name not specified"
        return 1
    fi
    
    # Try systemd first / Попробовать systemd сначала
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl is-active --quiet "${service}" 2>/dev/null; then
            log::info "Service ${service} is running"
            return 0
        else
            log::info "Service ${service} is not running"
            return 1
        fi
    else
        # Fallback to service command / Резервный вариант команды service
        if command -v service >/dev/null 2>&1; then
            service "${service}" status 2>/dev/null || true
        else
            # Fallback to direct init script / Резервный вариант прямого init скрипта
            if [[ -x "/etc/init.d/${service}" ]]; then
                "/etc/init.d/${service}" status 2>/dev/null || true
            else
                log::warn "No suitable method to check status of service ${service}"
                return 1
            fi
        fi
    fi
}

# @description List all system services / Показать все системные сервисы
# @example
#   system::services::list
system::services::list() {
    # Try systemd first / Попробовать systemd сначала
    if command -v systemctl >/dev/null 2>&1; then
        systemctl list-units --type=service --all 2>/dev/null | grep -E "^[a-zA-Z]" | awk '{print $1}'
    else
        # Fallback to listing init scripts / Резервный вариант списка init скриптов
        if [[ -d "/etc/init.d" ]]; then
            ls -1 /etc/init.d/ 2>/dev/null | grep -v "README"
        else
            log::warn "No suitable method to list services"
            return 1
        fi
    fi
}

## @brief Перезапускает системный сервис
## @param $1 service_name - Имя сервиса (например, "nginx", "sshd")
## @return 0=успех, 2=неверные аргументы, 4=сервис не найден, 8=ОС не поддерживается
## @example service::restart "nginx"
function service::restart() {
    local -r FN="${FUNCNAME[0]}"

    # Валидация
    if [[ $# -lt 1 ]]; then
        log::error "${FN}: недостаточно аргументов"
        return ${LIB_ERROR_INVALID_ARGS}
    fi

    local -r service="${1}"
    # Определяем дистрибутив через system::distro (результат в DISTRO_ID)
    # Detect distribution via system::distro (result in DISTRO_ID)
    load "lib/system/distro"
    system::distro::detect
    local -r os_type="${DISTRO_ID}"
    local -i exit_code=0

    log::info "${FN}: перезапуск ${service} (${os_type})..."

    # Dry-run
    if [[ "${FRAMEWORK_DRY_RUN}" == "true" ]]; then
        log::info "${FN}: [DRY-RUN] перезапуск ${service}"
        return ${E_SUCCESS}
    fi

    # Дистрибутивная логика
    case "${os_type}" in
        debian|ubuntu)
            # Попробовать systemd сначала
            if command -v systemctl >/dev/null 2>&1; then
                if systemctl is-active --quiet "${service}" 2>/dev/null; then
                    systemctl restart "${service}" 2>/dev/null || exit_code=$?
                else
                    systemctl start "${service}" 2>/dev/null || exit_code=$?
                fi
            else
                # Fallback to service command
                if command -v service >/dev/null 2>&1; then
                    service "${service}" restart 2>/dev/null || exit_code=$?
                else
                    # Fallback to direct init script
                    if [[ -x "/etc/init.d/${service}" ]]; then
                        "/etc/init.d/${service}" restart 2>/dev/null || exit_code=$?
                    else
                        log::error "${FN}: метод перезапуска не найден для ${service}"
                        return ${LIB_ERROR_DEPENDENCY}
                    fi
                fi
            fi
            ;;
        fedora|rhel|centos)
            # Попробовать systemd сначала
            if command -v systemctl >/dev/null 2>&1; then
                if systemctl is-active --quiet "${service}" 2>/dev/null; then
                    systemctl restart "${service}" 2>/dev/null || exit_code=$?
                else
                    systemctl start "${service}" 2>/dev/null || exit_code=$?
                fi
            else
                # Fallback to service command
                if command -v service >/dev/null 2>&1; then
                    service "${service}" restart 2>/dev/null || exit_code=$?
                else
                    log::error "${FN}: метод перезапуска не найден для ${service}"
                    return ${LIB_ERROR_DEPENDENCY}
                fi
            fi
            ;;
        alt|altlinux)
            # Для ALT Linux использовать service или chkconfig
            if command -v service >/dev/null 2>&1; then
                service "${service}" restart 2>/dev/null || exit_code=$?
            else
                log::error "${FN}: метод перезапуска не найден для ${service}"
                return ${LIB_ERROR_DEPENDENCY}
            fi
            ;;
        *)
            log::error "${FN}: неподдерживаемая ОС"
            return ${LIB_ERROR_UNSUPPORTED_OS}
            ;;
    esac

    # Результат
    if [[ ${exit_code} -eq 0 ]]; then
        log::info "${FN}: успешно"
    else
        log::error "${FN}: ошибка, код: ${exit_code}"
    fi

    return ${exit_code}
}
