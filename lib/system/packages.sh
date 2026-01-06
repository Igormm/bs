#!/usr/bin/env bs
# packages.sh — Package management for system setup / Управление пакетами для настройки
# системы

# @description Update package list / Обновить список пакетов
# @example
#   system::packages::update
system::packages::update() {
    # Detect package manager / Определить менеджер пакетов
    if command -v apt >/dev/null 2>&1; then
        apt update 2>/dev/null || true
        log::info "APT package list updated"
    elif command -v yum >/dev/null 2>&1; then
        yum check-update 2>/dev/null || true
        log::info "YUM package list updated"
    elif command -v dnf >/dev/null 2>&1; then
        dnf check-update 2>/dev/null || true
        log::info "DNF package list updated"
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Sy 2>/dev/null || true
        log::info "Pacman package list updated"
    elif command -v zypper >/dev/null 2>&1; then
        zypper refresh 2>/dev/null || true
        log::info "Zypper package list updated"
    else
        log::warn "No supported package manager found"
        return 1
    fi
}

# @description Install packages / Установить пакеты
# @param $@ Package names / Имена пакетов
# @example
#   system::packages::install "vim" "git" "curl"
system::packages::install() {
    if [[ $# -eq 0 ]]; then
        log::warn "No packages specified for installation"
        return 1
    fi
    
    # Detect package manager / Определить менеджер пакетов
    if command -v apt >/dev/null 2>&1; then
        apt install -y "$@" 2>/dev/null || true
        log::info "Packages installed with APT: $*"
    elif command -v yum >/dev/null 2>&1; then
        yum install -y "$@" 2>/dev/null || true
        log::info "Packages installed with YUM: $*"
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y "$@" 2>/dev/null || true
        log::info "Packages installed with DNF: $*"
    elif command -v pacman >/dev/null 2>&1; then
        pacman -S --noconfirm "$@" 2>/dev/null || true
        log::info "Packages installed with Pacman: $*"
    elif command -v zypper >/dev/null 2>&1; then
        zypper install -y "$@" 2>/dev/null || true
        log::info "Packages installed with Zypper: $*"
    else
        log::warn "No supported package manager found"
        return 1
    fi
}

# @description Remove packages / Удалить пакеты
# @param $@ Package names / Имена пакетов
# @example
#   system::packages::remove "vim" "git"
system::packages::remove() {
    if [[ $# -eq 0 ]]; then
        log::warn "No packages specified for removal"
        return 1
    fi
    
    # Detect package manager / Определить менеджер пакетов
    if command -v apt >/dev/null 2>&1; then
        apt remove -y "$@" 2>/dev/null || true
        log::info "Packages removed with APT: $*"
    elif command -v yum >/dev/null 2>&1; then
        yum remove -y "$@" 2>/dev/null || true
        log::info "Packages removed with YUM: $*"
    elif command -v dnf >/dev/null 2>&1; then
        dnf remove -y "$@" 2>/dev/null || true
        log::info "Packages removed with DNF: $*"
    elif command -v pacman >/dev/null 2>&1; then
        pacman -R --noconfirm "$@" 2>/dev/null || true
        log::info "Packages removed with Pacman: $*"
    elif command -v zypper >/dev/null 2>&1; then
        zypper remove -y "$@" 2>/dev/null || true
        log::info "Packages removed with Zypper: $*"
    else
        log::warn "No supported package manager found"
        return 1
    fi
}

# @description Upgrade all packages / Обновить все пакеты
# @example
#   system::packages::upgrade
system::packages::upgrade() {
    # Detect package manager / Определить менеджер пакетов
    if command -v apt >/dev/null 2>&1; then
        apt upgrade -y 2>/dev/null || true
        log::info "Packages upgraded with APT"
    elif command -v yum >/dev/null 2>&1; then
        yum update -y 2>/dev/null || true
        log::info "Packages upgraded with YUM"
    elif command -v dnf >/dev/null 2>&1; then
        dnf upgrade -y 2>/dev/null || true
        log::info "Packages upgraded with DNF"
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Syu --noconfirm 2>/dev/null || true
        log::info "Packages upgraded with Pacman"
    elif command -v zypper >/dev/null 2>&1; then
        zypper update -y 2>/dev/null || true
        log::info "Packages upgraded with Zypper"
    else
        log::warn "No supported package manager found"
        return 1
    fi
}

# @description Search for packages / Найти пакеты
# @param $1 Search term / Поисковый запрос
# @example
#   system::packages::search "vim"
system::packages::search() {
    local search_term="${1}"
    
    if [[ -z "${search_term}" ]]; then
        log::warn "Search term not specified"
        return 1
    fi
    
    # Detect package manager / Определить менеджер пакетов
    if command -v apt >/dev/null 2>&1; then
        apt search "${search_term}" 2>/dev/null || true
    elif command -v yum >/dev/null 2>&1; then
        yum search "${search_term}" 2>/dev/null || true
    elif command -v dnf >/dev/null 2>&1; then
        dnf search "${search_term}" 2>/dev/null || true
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Ss "${search_term}" 2>/dev/null || true
    elif command -v zypper >/dev/null 2>&1; then
        zypper search "${search_term}" 2>/dev/null || true
    else
        log::warn "No supported package manager found"
        return 1
    fi
}

# @description List installed packages / Показать установленные пакеты
# @example
#   system::packages::list
system::packages::list() {
    # Detect package manager
    if command -v apt >/dev/null 2>&1; then
        apt list --installed 2>/dev/null || true
    elif command -v yum >/dev/null 2>&1; then
        yum list installed 2>/dev/null || true
    elif command -v dnf >/dev/null 2>&1; then
        dnf list installed 2>/dev/null || true
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Q 2>/dev/null || true
    elif command -v zypper >/dev/null 2>&1; then
        zypper search -i 2>/dev/null || true
    else
        log::warn "No supported package manager found"
        return 1
    fi
}

# @description Add repository / Добавить репозиторий
# @param $1 Repository specification / Спецификация репозитория
# @example
#   system::packages::add_repo "ppa:deadsnakes/ppa"
system::packages::add_repo() {
    local repo="${1}"
    
    if [[ -z "${repo}" ]]; then
        log::warn "Repository specification not provided"
        return 1
    fi
    
    # Detect package manager / Определить менеджер пакетов
    if command -v apt >/dev/null 2>&1; then
        if [[ "${repo}" == ppa:* ]]; then
            apt-add-repository -y "${repo}" 2>/dev/null || true
        else
            echo "${repo}" >> /etc/apt/sources.list
        fi
        log::info "Repository added for APT: ${repo}"
    elif command -v yum >/dev/null 2>&1; then
        yum-config-manager --add-repo "${repo}" 2>/dev/null || true
        log::info "Repository added for YUM: ${repo}"
    elif command -v dnf >/dev/null 2>&1; then
        dnf config-manager --add-repo "${repo}" 2>/dev/null || true
        log::info "Repository added for DNF: ${repo}"
    else
        log::warn "Repository management not implemented for this package manager"
        return 1
    fi
}

# @description Remove repository / Удалить репозиторий
# @param $1 Repository specification / Спецификация репозитория
# @example
#   system::packages::remove_repo "ppa:deadsnakes/ppa"
system::packages::remove_repo() {
    local repo="${1}"
    
    if [[ -z "${repo}" ]]; then
        log::warn "Repository specification not provided"
        return 1
    fi
    
    # Detect package manager / Определить менеджер пакетов
    if command -v apt >/dev/null 2>&1; then
        if [[ "${repo}" == ppa:* ]]; then
            apt-add-repository -r -y "${repo}" 2>/dev/null || true
        else
            # Remove from sources.list / Удалить из sources.list
            sed -i "\|${repo}|d" /etc/apt/sources.list 2>/dev/null || true
        fi
        log::info "Repository removed for APT: ${repo}"
    elif command -v yum >/dev/null 2>&1; then
        # For YUM, we need to find and remove the repo file / Для YUM нужно найти и
        # удалить файл репозитория
        local repo_file=$(find /etc/yum.repos.d/ -name "*.repo" -exec grep -l "${repo}" {} \; 2>/dev/null)
        if [[ -n "${repo_file}" ]]; then
            rm -f "${repo_file}" 2>/dev/null || true
            log::info "Repository file removed for YUM: ${repo_file}"
        fi
    elif command -v dnf >/dev/null 2>&1; then
        # For DNF, we need to find and remove the repo file / Для DNF нужно найти и
        # удалить файл репозитория
        local repo_file=$(find /etc/yum.repos.d/ -name "*.repo" -exec grep -l "${repo}" {} \; 2>/dev/null)
        if [[ -n "${repo_file}" ]]; then
            rm -f "${repo_file}" 2>/dev/null || true
            log::info "Repository file removed for DNF: ${repo_file}"
        fi
    else
        log::warn "Repository management not implemented for this package manager"
        return 1
    fi
}