#!/usr/bin/env bs
# shellcheck shell=bash
# @shell bash4 — нужны конструкции bash: double-bracket [[ ]], local/declare flags, case/replace expansion, regex =~ / needs bash constructs: double-bracket [[ ]], local/declare flags, case/replace expansion, regex =~
# locale.sh — Localization configuration for system setup / Конфигурация локализации для
# настройки системы
# @depends core/const, core/logger, core/utils, lib/system/devdriver

# Source Guard / Защита от повторной загрузки
bs::guard "SYSTEM_LOCALE" || return 0

# Зависимости / Dependencies
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh" \
    "./devdriver.sh"

# @description Set system locale / Установить системную локаль
# @param $1 Locale (e.g., "en_US.UTF-8", "ru_RU.UTF-8") / Локаль (например, "en_US.UTF-8",
# "ru_RU.UTF-8")
# @example
#   system::locale::set "en_US.UTF-8"
system::locale::set() {
    local locale="${1:-en_US.UTF-8}"
    local -r locale_gen="${BS_LOCALE_GEN:-/etc/locale.gen}"
    local -r default_locale="${BS_DEFAULT_LOCALE:-/etc/default/locale}"
    
    if [[ ! "${locale}" =~ ^[A-Za-z0-9_.@-]+$ ]]; then
        log::warn "Invalid locale name: ${locale}"
        return "${E_ERROR}"
    fi
    
    if utils::has localectl; then
        if ! utils::quiet localectl set-locale "${locale}"; then
            log::error "localectl failed to set locale ${locale}"
            return "${E_ERROR}"
        fi
    else
        if is::file "${locale_gen}"; then
            # The name is a literal, not a regex: dots are escaped / Имя — литерал,
            # а не регулярное выражение: точки экранируются
            local -r pattern="${locale//./\\.}"
            if ! sed -i "s/^#[[:space:]]*\(${pattern}\([[:space:]]\|\$\)\)/\1/" "${locale_gen}"; then
                log::error "Cannot edit ${locale_gen}"
                return "${E_ERROR}"
            fi
            if utils::has locale-gen && ! utils::quiet locale-gen; then
                log::error "locale-gen failed"
                return "${E_ERROR}"
            fi
        fi
        
        if is::file "${default_locale}"; then
            # Change only LANG: other settings (LC_*, LANGUAGE) stay / Меняем только LANG:
            # остальные настройки (LC_*, LANGUAGE) остаются
            if grep -q '^LANG=' "${default_locale}"; then
                if ! sed -i "s/^LANG=.*/LANG=${locale}/" "${default_locale}"; then
                    log::error "Cannot edit ${default_locale}"
                    return "${E_ERROR}"
                fi
            elif ! printf 'LANG=%s\n' "${locale}" >> "${default_locale}"; then
                log::error "Cannot write ${default_locale}"
                return "${E_ERROR}"
            fi
        else
            export LANG="${locale}"
            log::warn "No ${default_locale}: locale set for this session only"
            return 0
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

# ============================================================================
# Driver interface (driver::locale::) for lib/system/devicectl
# Драйверный интерфейс (driver::locale::) для lib/system/devicectl
# ============================================================================

# @private Каталог параметров локали / locale parameter catalogue.
# @stdout TSV param<TAB>type<TAB>default<TAB>choices<TAB>tip
driver::locale::__catalog() {
    printf 'lang\tstring\t\t\tlocale / локаль (en_US.UTF-8, ru_RU.UTF-8, …)\n'
}

# @private Текущая системная локаль: localectl status «System Locale: LANG=…» или $LANG.
driver::locale::__current() {
    local -r val="$(utils::attempt localectl status | sed -n 's/.*System Locale:[[:space:]]*LANG=\([A-Za-z0-9_.@-]*\).*/\1/p')"
    if [[ -n "${val}" ]]; then
        printf '%s' "${val}"
    else
        printf '%s' "${LANG:-}"
    fi
}

# @description Список устройств: одна логическая локаль системы.
# @stdout TSV handle<TAB>label<TAB>kind
driver::locale::detect() {
    if utils::has localectl || [[ -f /etc/locale.gen ]] || [[ -f /etc/default/locale ]]; then
        printf 'default\tSystem locale\tlocale\n'
        return 0
    fi
    log::warn "locale: no localectl or locale.gen"
    return "${LIB_ERROR_DEPENDENCY_MISSING}"
}

# @description Текущая локаль / current locale.
# @param $1 handle; $2 param
driver::locale::get() {
    local -r handle="$1" param="$2"
    case "${param}" in
        lang) driver::locale::__current ;;
        *) return "${E_INVALID}" ;;
    esac
    return 0
}

# @description Параметры локали / locale parameters.
# @param $1 handle
# @stdout TSV param<TAB>type<TAB>current<TAB>default<TAB>choices<TAB>tip
driver::locale::params() {
    local -r handle="$1"
    devdriver::params locale "${handle}" ""
}

# @description Живое применение локали / live apply of the locale.
# @param $1 handle; $2 param; $3 value
driver::locale::set() {
    local -r handle="$1" param="$2" value="$3"
    case "${param}" in
        lang) system::locale::set "${value}" ;;
        *) return "${E_INVALID}" ;;
    esac
}

# @description Снимок параметров локали / snapshot of locale params.
# @param $1 handle
# @stdout TSV param<TAB>value
driver::locale::snapshot() {
    local -r handle="$1"
    devdriver::snapshot locale "${handle}" ""
}
