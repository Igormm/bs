#!/usr/bin/env bs
# distro.sh — Distribution detection and compatibility / Определение дистрибутива и
# совместимость

# Global variables for detected distribution / Глобальные переменные для определенного
# дистрибутива
declare -g DISTRO_ID=""
declare -g DISTRO_NAME=""
declare -g DISTRO_VERSION=""
declare -g DISTRO_FAMILY=""  # debian, redhat, arch, suse, etc.
declare -g DISTRO_PACKAGE_MANAGER=""

# @description Detect Linux distribution / Определить дистрибутив Linux
# @example
#   system::distro::detect
system::distro::detect() {
    # Try /etc/os-release first (modern standard) / Попробовать /etc/os-release сначала
    # (современный стандарт)
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        DISTRO_ID="${ID:-unknown}"
        DISTRO_NAME="${NAME:-Unknown}"
        DISTRO_VERSION="${VERSION_ID:-unknown}"
    # Try lsb_release / Попробовать lsb_release
    elif command -v lsb_release >/dev/null 2>&1; then
        DISTRO_ID=$(lsb_release -si 2>/dev/null | tr '[:upper:]' '[:lower:]')
        DISTRO_NAME=$(lsb_release -sd 2>/dev/null)
        DISTRO_VERSION=$(lsb_release -sr 2>/dev/null)
    # Fallback to /etc/*-release files / Резервный вариант файлы /etc/*-release
    elif [[ -f /etc/debian_version ]]; then
        DISTRO_ID="debian"
        DISTRO_NAME="Debian"
        DISTRO_VERSION=$(cat /etc/debian_version 2>/dev/null)
    elif [[ -f /etc/redhat-release ]]; then
        DISTRO_ID="rhel"
        DISTRO_NAME=$(cat /etc/redhat-release 2>/dev/null | sed 's/ release.*//')
        DISTRO_VERSION=$(cat /etc/redhat-release 2>/dev/null | sed 's/.*release \([0-9]\+\).*/\1/')
    elif [[ -f /etc/SuSE-release ]]; then
        DISTRO_ID="suse"
        DISTRO_NAME="openSUSE"
        DISTRO_VERSION=$(grep VERSION /etc/SuSE-release 2>/dev/null | cut -d'=' -f2 | tr -d ' ')
    else
        DISTRO_ID="unknown"
        DISTRO_NAME="Unknown"
        DISTRO_VERSION="unknown"
    fi

    # Determine family and package manager / Определить семейство и менеджер пакетов
    case "${DISTRO_ID}" in
        ubuntu|debian|kali|raspbian|linuxmint|zorin|elementary|pop)
            DISTRO_FAMILY="debian"
            DISTRO_PACKAGE_MANAGER="apt"
            ;;
        fedora|rhel|centos|almalinux|rocky|ol|scientific)
            DISTRO_FAMILY="redhat"
            DISTRO_PACKAGE_MANAGER="dnf"
            # Check for yum on older systems / Проверить yum на старых системах
            if ! command -v dnf >/dev/null 2>&1 && command -v yum >/dev/null 2>&1; then
                DISTRO_PACKAGE_MANAGER="yum"
            fi
            ;;
        opensuse*|sles|suse)
            DISTRO_FAMILY="suse"
            DISTRO_PACKAGE_MANAGER="zypper"
            ;;
        arch|manjaro|endeavouros|garuda)
            DISTRO_FAMILY="arch"
            DISTRO_PACKAGE_MANAGER="pacman"
            ;;
        alpine)
            DISTRO_FAMILY="alpine"
            DISTRO_PACKAGE_MANAGER="apk"
            ;;
        gentoo)
            DISTRO_FAMILY="gentoo"
            DISTRO_PACKAGE_MANAGER="emerge"
            ;;
        slackware)
            DISTRO_FAMILY="slackware"
            DISTRO_PACKAGE_MANAGER="slackpkg"
            ;;
        *)
            DISTRO_FAMILY="unknown"
            DISTRO_PACKAGE_MANAGER="unknown"
            ;;
    esac

    log::debug "Detected distro: ${DISTRO_NAME} (${DISTRO_ID}) ${DISTRO_VERSION}, family: ${DISTRO_FAMILY}, pkg: ${DISTRO_PACKAGE_MANAGER}"
}

# @description Get distribution information / Получить информацию о дистрибутиве
# @example
#   system::distro::info
system::distro::info() {
    # Detect if not already done / Определить если еще не сделано
    if [[ -z "${DISTRO_ID}" ]]; then
        system::distro::detect
    fi

    echo "=== Distribution Information ==="
    echo "Name: ${DISTRO_NAME}"
    echo "ID: ${DISTRO_ID}"
    echo "Version: ${DISTRO_VERSION}"
    echo "Family: ${DISTRO_FAMILY}"
    echo "Package Manager: ${DISTRO_PACKAGE_MANAGER}"
}

# @description Check if current distro is in specified family / Проверить, относится ли
# текущий дистрибутив к указанному семейству
# @param $1 Family name / Имя семейства
# @return 0 if yes, 1 if no / 0 если да, 1 если нет
# @example
#   if system::distro::is_family "debian"; then
#       echo "Debian-based system"
#   fi
system::distro::is_family() {
    local family="${1}"

    # Detect if not already done / Определить если еще не сделано
    if [[ -z "${DISTRO_FAMILY}" ]]; then
        system::distro::detect
    fi

    [[ "${DISTRO_FAMILY}" == "${family}" ]]
}

# @description Get appropriate package manager command / Получить подходящую команду
# менеджера пакетов
# @param $1 Action (install|remove|update|upgrade|search) / Действие
# @return Command string / Строка команды
# @example
#   cmd=$(system::distro::package_command "install")
#   $cmd package_name
system::distro::package_command() {
    local action="${1}"

    # Detect if not already done / Определить если еще не сделано
    if [[ -z "${DISTRO_PACKAGE_MANAGER}" ]]; then
        system::distro::detect
    fi

    case "${DISTRO_PACKAGE_MANAGER}" in
        apt)
            case "${action}" in
                install) echo "apt-get install -y" ;;
                remove)  echo "apt-get remove -y" ;;
                update)  echo "apt-get update" ;;
                upgrade) echo "apt-get upgrade -y" ;;
                search)  echo "apt-cache search" ;;
                *)       echo "apt-get ${action}" ;;
            esac
            ;;
        dnf)
            case "${action}" in
                install) echo "dnf install -y" ;;
                remove)  echo "dnf remove -y" ;;
                update)  echo "dnf check-update" ;;
                upgrade) echo "dnf upgrade -y" ;;
                search)  echo "dnf search" ;;
                *)       echo "dnf ${action}" ;;
            esac
            ;;
        yum)
            case "${action}" in
                install) echo "yum install -y" ;;
                remove)  echo "yum remove -y" ;;
                update)  echo "yum check-update" ;;
                upgrade) echo "yum update -y" ;;
                search)  echo "yum search" ;;
                *)       echo "yum ${action}" ;;
            esac
            ;;
        zypper)
            case "${action}" in
                install) echo "zypper install -y" ;;
                remove)  echo "zypper remove -y" ;;
                update)  echo "zypper refresh" ;;
                upgrade) echo "zypper update -y" ;;
                search)  echo "zypper search" ;;
                *)       echo "zypper ${action}" ;;
            esac
            ;;
        pacman)
            case "${action}" in
                install) echo "pacman -S --noconfirm" ;;
                remove)  echo "pacman -R --noconfirm" ;;
                update)  echo "pacman -Sy" ;;
                upgrade) echo "pacman -Syu --noconfirm" ;;
                search)  echo "pacman -Ss" ;;
                *)       echo "pacman ${action}" ;;
            esac
            ;;
        apk)
            case "${action}" in
                install) echo "apk add" ;;
                remove)  echo "apk del" ;;
                update)  echo "apk update" ;;
                upgrade) echo "apk upgrade" ;;
                search)  echo "apk search" ;;
                *)       echo "apk ${action}" ;;
            esac
            ;;
        emerge)
            case "${action}" in
                install) echo "emerge" ;;
                remove)  echo "emerge --unmerge" ;;
                update)  echo "emerge --sync" ;;
                upgrade) echo "emerge --update --deep @world" ;;
                search)  echo "emerge --search" ;;
                *)       echo "emerge ${action}" ;;
            esac
            ;;
        *)
            log::warn "Unknown package manager: ${DISTRO_PACKAGE_MANAGER}"
            echo "${action}"
            ;;
    esac
}

# @description Install package(s) using appropriate package manager / Установить пакет(ы)
# используя подходящий менеджер пакетов
# @param $@ Package names / Имена пакетов
# @example
#   system::distro::install_package curl wget
system::distro::install_package() {
    if [[ $# -eq 0 ]]; then
        log::warn "No packages specified"
        return 1
    fi

    local install_cmd
    install_cmd=$(system::distro::package_command "install")

    if [[ "${install_cmd}" == "install" ]]; then
        log::error "Cannot determine package manager for installation"
        return 1
    fi

    log::info "Installing packages: $*"
    if ${install_cmd} "$@"; then
        log::info "Packages installed successfully"
        return 0
    else
        log::error "Failed to install packages"
        return 1
    fi
}

# @description Check if package is installed / Проверить, установлен ли пакет
# @param $1 Package name / Имя пакета
# @return 0 if installed, 1 if not / 0 если установлен, 1 если нет
# @example
#   if system::distro::is_package_installed "curl"; then
#       echo "curl is installed"
#   fi
system::distro::is_package_installed() {
    local package="${1}"

    if [[ -z "${package}" ]]; then
        return 1
    fi

    # Detect if not already done / Определить если еще не сделано
    if [[ -z "${DISTRO_PACKAGE_MANAGER}" ]]; then
        system::distro::detect
    fi

    case "${DISTRO_PACKAGE_MANAGER}" in
        apt)
            dpkg -l "${package}" 2>/dev/null | grep -q "^ii"
            ;;
        dnf|yum)
            rpm -q "${package}" >/dev/null 2>&1
            ;;
        zypper)
            rpm -q "${package}" >/dev/null 2>&1
            ;;
        pacman)
            pacman -Q "${package}" >/dev/null 2>&1
            ;;
        apk)
            apk info -e "${package}" >/dev/null 2>&1
            ;;
        emerge)
            equery list "${package}" >/dev/null 2>&1
            ;;
        *)
            # Generic check using which / Общая проверка с помощью which
            command -v "${package}" >/dev/null 2>&1
            ;;
    esac
}

# Initialize detection on module load / Инициализировать определение при загрузке модуля
system::distro::detect
