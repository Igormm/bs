#!/usr/bin/env bs
# lib/system/platformcheck.sh — Platform compatibility checker for BS
# lib/system/platformcheck.sh — Модуль проверки совместимости платформ для BS
#
# Этот модуль проверяет совместимость фреймворка с различными платформами:
# macOS, AlmaLinux, Debian, Ubuntu, Fedora, ALT Linux
# This module checks framework compatibility with various platforms:
# macOS, AlmaLinux, Debian, Ubuntu, Fedora, ALT Linux

# Примечание: строгий режим (set -euo pipefail) задаётся только в точках входа
# Note: strict mode (set -euo pipefail) is set only in entry points

declare -g PLATFORM_CHECK_VERSION="1.0.0"
declare -g -A PLATFORM_CHECK_RESULTS

# ==========================================
# Проверка платформ / Platform checks
# ==========================================

# @description Check if running on macOS
# @description Проверить, запущен ли на macOS
# @return 0 if macOS, 1 otherwise / 0 если macOS, иначе 1
# @example
#   if platformcheck::is_macos; then ...
platformcheck::is_macos() {
    if [[ "$OSTYPE" == "darwin"* ]] || [[ -n "${MACOS:-}" ]]; then
        return 0
    else
        return 1
    fi
}

# @description Check if running on AlmaLinux
# @description Проверить, запущен ли на AlmaLinux
# @return 0 if AlmaLinux, 1 otherwise / 0 если AlmaLinux, иначе 1
# @example
#   if platformcheck::is_alma; then ...
platformcheck::is_alma() {
    if [[ -f /etc/almalinux-release ]] || [[ -f /etc/redhat-release && $(cat /etc/redhat-release) == *"AlmaLinux"* ]]; then
        return 0
    else
        return 1
    fi
}

# @description Check if running on Debian
# @description Проверить, запущен ли на Debian
# @return 0 if Debian, 1 otherwise / 0 если Debian, иначе 1
# @example
#   if platformcheck::is_debian; then ...
platformcheck::is_debian() {
    if [[ -f /etc/debian_version ]] && [[ ! -f /etc/lsb-release ]]; then
        return 0
    else
        return 1
    fi
}

# @description Check if running on Ubuntu
# @description Проверить, запущен ли на Ubuntu
# @return 0 if Ubuntu, 1 otherwise / 0 если Ubuntu, иначе 1
# @example
#   if platformcheck::is_ubuntu; then ...
platformcheck::is_ubuntu() {
    if [[ -f /etc/lsb-release ]] && [[ $(cat /etc/lsb-release) == *"Ubuntu"* ]]; then
        return 0
    else
        return 1
    fi
}

# @description Check if running on Fedora
# @description Проверить, запущен ли на Fedora
# @return 0 if Fedora, 1 otherwise / 0 если Fedora, иначе 1
# @example
#   if platformcheck::is_fedora; then ...
platformcheck::is_fedora() {
    if [[ -f /etc/fedora-release ]] || [[ -f /etc/redhat-release && $(cat /etc/redhat-release) == *"Fedora"* ]]; then
        return 0
    else
        return 1
    fi
}

# @description Check if running on ALT Linux
# @description Проверить, запущен ли на ALT Linux
# @return 0 if ALT Linux, 1 otherwise / 0 если ALT Linux, иначе 1
# @example
#   if platformcheck::is_altlinux; then ...
platformcheck::is_altlinux() {
    if [[ -f /etc/altlinux-release ]] || [[ -f /etc/os-release && $(cat /etc/os-release) == *"ALT"* ]]; then
        return 0
    else
        return 1
    fi
}

# @description Get platform information
# @description Получить информацию о платформе
# @return Platform info string / Строка с информацией о платформе
# @example
#   platform_info=$(platformcheck::get_info)
platformcheck::get_info() {
    local os_name=""
    local os_version=""
    local kernel_version=""
    
    # Определяем ОС / Detect OS
    if platformcheck::is_macos; then
        os_name="macOS"
        os_version=$(utils::quiet_err sw_vers -productVersion || echo "Unknown")
    elif platformcheck::is_alma; then
        os_name="AlmaLinux"
        os_version=$(utils::quiet_err cat /etc/almalinux-release | awk '{print $2}' || echo "Unknown")
    elif platformcheck::is_ubuntu; then
        os_name="Ubuntu"
        os_version=$(utils::quiet_err lsb_release -rs || echo "Unknown")
    elif platformcheck::is_debian; then
        os_name="Debian"
        os_version=$(utils::quiet_err cat /etc/debian_version || echo "Unknown")
    elif platformcheck::is_fedora; then
        os_name="Fedora"
        os_version=$(utils::quiet_err cat /etc/fedora-release | awk '{print $3}' || echo "Unknown")
    elif platformcheck::is_altlinux; then
        os_name="ALT Linux"
        os_version=$(utils::quiet_err cat /etc/altlinux-release | head -1 | awk '{print $3}' || echo "Unknown")
    else
        os_name=$(utils::quiet_err cat /etc/os-release | grep "^NAME=" | cut -d'"' -f2 || echo "Unknown")
        os_version=$(utils::quiet_err cat /etc/os-release | grep "^VERSION_ID=" | cut -d'"' -f2 || echo "Unknown")
    fi
    
    # Получаем версию ядра / Get kernel version
    kernel_version=$(uname -r)
    
    echo "OS: $os_name $os_version, Kernel: $kernel_version"
}

# @description Check platform compatibility
# @description Проверить совместимость платформы
# @return 0 if compatible, 1 otherwise / 0 если совместимо, иначе 1
# @example
#   if platformcheck::is_compatible; then ...
platformcheck::is_compatible() {
    local supported_platforms=("macOS" "AlmaLinux" "Ubuntu" "Debian" "Fedora" "ALT Linux")
    local platform_info
    platform_info=$(platformcheck::get_info)
    
    for platform in "${supported_platforms[@]}"; do
        if [[ "$platform_info" == *"$platform"* ]]; then
            return 0
        fi
    done
    
    return 1
}

# @description Get detailed platform report
# @description Получить детальный отчет о платформе
# @return Detailed platform report / Детальный отчет о платформе
# @example
#   report=$(platformcheck::get_report)
platformcheck::get_report() {
    local report=""
    local platform_info
    platform_info=$(platformcheck::get_info)
    
    report+="Platform Information / Информация о платформе:\n"
    report+="  $platform_info\n\n"
    
    report+="Compatibility Check / Проверка совместимости:\n"
    if platformcheck::is_compatible; then
        report+="  ${COLOR_GREEN}✓ Supported platform / Поддерживаемая платформа${COLOR_RESET}\n"
    else
        report+="  ${COLOR_RED}✗ Unsupported platform / Неподдерживаемая платформа${COLOR_RESET}\n"
    fi
    
    report+="\nPlatform Detection / Обнаружение платформы:\n"
    platformcheck::is_macos && report+="  ${COLOR_GREEN}✓ macOS${COLOR_RESET}\n" || report+="  ${COLOR_RED}✗ macOS${COLOR_RESET}\n"
    platformcheck::is_alma && report+="  ${COLOR_GREEN}✓ AlmaLinux${COLOR_RESET}\n" || report+="  ${COLOR_RED}✗ AlmaLinux${COLOR_RESET}\n"
    platformcheck::is_ubuntu && report+="  ${COLOR_GREEN}✓ Ubuntu${COLOR_RESET}\n" || report+="  ${COLOR_RED}✗ Ubuntu${COLOR_RESET}\n"
    platformcheck::is_debian && report+="  ${COLOR_GREEN}✓ Debian${COLOR_RESET}\n" || report+="  ${COLOR_RED}✗ Debian${COLOR_RESET}\n"
    platformcheck::is_fedora && report+="  ${COLOR_GREEN}✓ Fedora${COLOR_RESET}\n" || report+="  ${COLOR_RED}✗ Fedora${COLOR_RESET}\n"
    platformcheck::is_altlinux && report+="  ${COLOR_GREEN}✓ ALT Linux${COLOR_RESET}\n" || report+="  ${COLOR_RED}✗ ALT Linux${COLOR_RESET}\n"
    
    echo -e "$report"
}

# ==========================================
# Проверки зависимостей / Dependency checks
# ==========================================

# @description Check if required tools are available
# @description Проверить доступность необходимых инструментов
# @return 0 if all tools available, 1 otherwise / 0 если все инструменты доступны, иначе 1
# @example
#   if platformcheck::check_dependencies; then ...
platformcheck::check_dependencies() {
    local required_tools=("bash" "grep" "sed" "awk" "cut" "cat" "uname")
    local missing_tools=()
    
    for tool in "${required_tools[@]}"; do
        if ! utils::has "$tool"; then
            missing_tools+=("$tool")
        fi
    done

    if [[ ${#missing_tools[@]} -eq 0 ]]; then
        utils::quiet_err log::info "All required tools are available" || true
        return 0
    else
        utils::quiet_err log::error "Missing required tools: ${missing_tools[*]}" || {
            echo "Missing required tools: ${missing_tools[*]}" >&2
        }
        return 1
    fi
}

# @description Check macOS-specific dependencies
# @description Проверить зависимости macOS
# @return 0 if all macOS tools available, 1 otherwise / 0 если все инструменты macOS
# доступны, иначе 1
# @example
#   if platformcheck::check_macos_deps; then ...
platformcheck::check_macos_deps() {
    if ! platformcheck::is_macos; then
        return 0  # Not macOS, skip check
    fi
    
    local macos_tools=("sw_vers" "osascript")
    local missing_tools=()
    
    for tool in "${macos_tools[@]}"; do
        if ! utils::has "$tool"; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -eq 0 ]]; then
        utils::quiet_err log::info "All macOS tools are available" || true
        return 0
    else
        utils::quiet_err log::warn "Missing macOS tools: ${missing_tools[*]}" || true
        return 1
    fi
}

# @description Check Linux-specific dependencies
# @description Проверить зависимости Linux
# @return 0 if all Linux tools available, 1 otherwise / 0 если все инструменты Linux
# доступны, иначе 1
# @example
#   if platformcheck::check_linux_deps; then ...
platformcheck::check_linux_deps() {
    if platformcheck::is_macos; then
        return 0  # Not Linux, skip check
    fi
    
    local linux_tools=("lsb_release" "systemctl" "ip")
    local missing_tools=()
    
    for tool in "${linux_tools[@]}"; do
        if ! utils::has "$tool"; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -eq 0 ]]; then
        utils::quiet_err log::info "All Linux tools are available" || true
        return 0
    else
        utils::quiet_err log::warn "Missing Linux tools: ${missing_tools[*]}" || true
        return 1
    fi
}

# ==========================================
# Установка зависимостей / Dependency installation
# ==========================================

# @description Install missing dependencies for platform
# @description Установить недостающие зависимости для платформы
# @return 0 if successful, 1 otherwise / 0 если успешно, иначе 1
# @example
#   platformcheck::install_dependencies
platformcheck::install_dependencies() {
    utils::quiet_err log::info "Checking and installing dependencies..." || true
    
    if platformcheck::is_macos; then
        platformcheck::install_macos_deps
    else
        platformcheck::install_linux_deps
    fi
}

# @description Install macOS dependencies
# @description Установить зависимости macOS
# @example
#   platformcheck::install_macos_deps
platformcheck::install_macos_deps() {
    utils::quiet_err log::info "Installing macOS dependencies..." || true
    
    # Проверяем Homebrew / Check Homebrew
    if ! utils::has brew; then
        utils::quiet_err log::info "Homebrew not found. Installing..." || true
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    
    # Устанавливаем необходимые пакеты / Install necessary packages
    brew install coreutils gnu-sed grep
    
    utils::quiet_err log::success "macOS dependencies installed" || true
}

# @description Install Linux dependencies
# @description Установить зависимости Linux
# @example
#   platformcheck::install_linux_deps
platformcheck::install_linux_deps() {
    utils::quiet_err log::info "Installing Linux dependencies..." || true
    
    load "lib/system/distrologic"
    
    # Устанавливаем необходимые пакеты / Install necessary packages
    system::distrologic::pkg_install_cross "curl" "wget" "git" "tree" "jq"
    
    utils::quiet_err log::success "Linux dependencies installed" || true
}

# ==========================================
# Утилиты / Utilities
# ==========================================

# @description Show platform compatibility report
# @description Показать отчет о совместимости платформы
# @example
#   platformcheck::show_report
platformcheck::show_report() {
    utils::quiet_err log::header "Platform Compatibility Report" || true
    utils::quiet_err log::header "Отчет о совместимости платформы" || true
    
    platformcheck::get_report
    
    echo
    echo -e "${COLOR_BLUE}Dependency Check / Проверка зависимостей:${COLOR_RESET}"
    if platformcheck::check_dependencies; then
        echo -e "  ${COLOR_GREEN}✓ All dependencies satisfied / Все зависимости удовлетворены${COLOR_RESET}"
    else
        echo -e "  ${COLOR_RED}✗ Some dependencies missing / Некоторые зависимости отсутствуют${COLOR_RESET}"
        platformcheck::install_dependencies
    fi
    
    echo
    echo -e "${COLOR_BLUE}Platform Support / Поддержка платформ:${COLOR_RESET}"
    platformcheck::is_macos && echo -e "  ${COLOR_GREEN}✓ macOS support available / Поддержка macOS доступна${COLOR_RESET}" || echo -e "  ${COLOR_RED}✗ macOS support missing / Поддержка macOS отсутствует${COLOR_RESET}"
    platformcheck::is_alma && echo -e "  ${COLOR_GREEN}✓ AlmaLinux support available / Поддержка AlmaLinux доступна${COLOR_RESET}" || echo -e "  ${COLOR_RED}✗ AlmaLinux support missing / Поддержка AlmaLinux отсутствует${COLOR_RESET}"
    platformcheck::is_ubuntu && echo -e "  ${COLOR_GREEN}✓ Ubuntu support available / Поддержка Ubuntu доступна${COLOR_RESET}" || echo -e "  ${COLOR_RED}✗ Ubuntu support missing / Поддержка Ubuntu отсутствует${COLOR_RESET}"
    platformcheck::is_debian && echo -e "  ${COLOR_GREEN}✓ Debian support available / Поддержка Debian доступна${COLOR_RESET}" || echo -e "  ${COLOR_RED}✗ Debian support missing / Поддержка Debian отсутствует${COLOR_RESET}"
    platformcheck::is_fedora && echo -e "  ${COLOR_GREEN}✓ Fedora support available / Поддержка Fedora доступна${COLOR_RESET}" || echo -e "  ${COLOR_RED}✗ Fedora support missing / Поддержка Fedora отсутствует${COLOR_RESET}"
    platformcheck::is_altlinux && echo -e "  ${COLOR_GREEN}✓ ALT Linux support available / Поддержка ALT Linux доступна${COLOR_RESET}" || echo -e "  ${COLOR_RED}✗ ALT Linux support missing / Поддержка ALT Linux отсутствует${COLOR_RESET}"
}

# ==========================================
# Инициализация / Initialization
# ==========================================

# Инициализируем модуль при загрузке
# Initialize module on load
if [[ -z "${PLATFORM_CHECK_INITIALIZED:-}" ]]; then
    PLATFORM_CHECK_INITIALIZED="1"
    utils::quiet_err log::debug "Platform check module initialized" || true
fi
