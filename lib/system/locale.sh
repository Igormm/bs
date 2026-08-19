#!/usr/bin/env bs
# shellcheck shell=bash
# locale.sh — Localization configuration for system setup / Конфигурация локализации для
# настройки системы
# @depends core/const, core/logger, core/utils

# Source Guard / Защита от повторной загрузки
bs::guard "SYSTEM_LOCALE" || return 0

# Зависимости / Dependencies
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh"

# @description Set system locale / Установить системную локаль
# @param $1 Locale (e.g., "en_US.UTF-8", "ru_RU.UTF-8") / Локаль (например, "en_US.UTF-8",
# "ru_RU.UTF-8")
# @example
#   system::locale::set "en_US.UTF-8"
system::locale::set() {
    local locale="${1:-en_US.UTF-8}"
    
    # For systemd-based systems / Для систем на базе systemd
    if utils::has localectl; then
        utils::attempt localectl set-locale "${locale}"
    else
        # Fallback for non-systemd systems / Резервный вариант для систем без systemd
        if [[ -f "/etc/locale.gen" ]]; then
            # Uncomment the locale in /etc/locale.gen / Раскомментировать локаль в
            # /etc/locale.gen
            utils::attempt sed -i "s/^#${locale}/${locale}/" /etc/locale.gen
            # Generate the locale / Сгенерировать локаль
            if utils::has locale-gen; then
                utils::attempt locale-gen
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
    if utils::has localectl; then
        utils::attempt localectl list-locales
    else
        utils::attempt locale -a
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