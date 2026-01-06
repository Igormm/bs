#!/usr/bin/env bs
# locale.sh — Localization configuration for system setup / Конфигурация локализации для
# настройки системы

# @description Set system locale / Установить системную локаль
# @param $1 Locale (e.g., "en_US.UTF-8", "ru_RU.UTF-8") / Локаль (например, "en_US.UTF-8",
# "ru_RU.UTF-8")
# @example
#   system::locale::set "en_US.UTF-8"
system::locale::set() {
    local locale="${1:-en_US.UTF-8}"
    
    # For systemd-based systems / Для систем на базе systemd
    if command -v localectl >/dev/null 2>&1; then
        localectl set-locale "${locale}" 2>/dev/null || true
    else
        # Fallback for non-systemd systems / Резервный вариант для систем без systemd
        if [[ -f "/etc/locale.gen" ]]; then
            # Uncomment the locale in /etc/locale.gen / Раскомментировать локаль в
            # /etc/locale.gen
            sed -i "s/^#${locale}/${locale}/" /etc/locale.gen 2>/dev/null || true
            # Generate the locale / Сгенерировать локаль
            if command -v locale-gen >/dev/null 2>&1; then
                locale-gen 2>/dev/null || true
            fi
        fi
        
        # Set the system locale / Установить системную локаль
        if [[ -f "/etc/default/locale" ]]; then
            echo "LANG=${locale}" > /etc/default/locale
        else
            export LANG="${locale}"
        fi
    fi
    
    log::info "System locale set to ${locale}"
}

# @description List available locales / Показать доступные локали
# @example
#   system::locale::list
system::locale::list() {
    if command -v localectl >/dev/null 2>&1; then
        localectl list-locales 2>/dev/null || true
    else
        locale -a 2>/dev/null || true
    fi
}

# @description Set language for current session / Установить язык для текущей сессии
# @param $1 Language code (e.g., "en_US.UTF-8", "ru_RU.UTF-8") / Код языка (например,
# "en_US.UTF-8", "ru_RU.UTF-8")
# @example
#   system::locale::language "en_US.UTF-8"
system::locale::language() {
    local lang="${1:-en_US.UTF-8}"
    export LANG="${lang}"
    export LANGUAGE="${lang}"
    log::info "Session language set to ${lang}"
}