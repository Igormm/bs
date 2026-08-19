#!/usr/bin/env bs
# shellcheck shell=bash
# packages.sh — Package management for system setup / Управление пакетами для настройки
# системы
# @depends core/const, core/logger, core/utils, lib/io/files

# Source Guard / Защита от повторной загрузки
bs::guard "SYSTEM_PACKAGES" || return 0

# Зависимости / Dependencies
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh" "../io/files.sh"

# @description Update package list / Обновить список пакетов
# @example
#   system::packages::update
system::packages::update() {
    # Detect package manager / Определить менеджер пакетов
    if utils::has apt; then
        utils::quiet_err apt update || :
        log::info "APT package list updated"
    elif utils::has yum; then
        utils::quiet_err yum check-update || :
        log::info "YUM package list updated"
    elif utils::has dnf; then
        utils::quiet_err dnf check-update || :
        log::info "DNF package list updated"
    elif utils::has pacman; then
        utils::quiet_err pacman -Sy || :
        log::info "Pacman package list updated"
    elif utils::has zypper; then
        utils::quiet_err zypper refresh || :
        log::info "Zypper package list updated"
    else
        log::warn "No supported package manager found"
        return "${E_ERROR}"
    fi
}

# @description Install packages / Установить пакеты
# @param $@ Package names / Имена пакетов
# @example
#   system::packages::install "vim" "git" "curl"
system::packages::install() {
    if [[ $# -eq 0 ]]; then
        log::warn "No packages specified for installation"
        return "${E_ERROR}"
    fi
    
    # Detect package manager / Определить менеджер пакетов
    if utils::has apt; then
        utils::quiet_err apt install -y "$@"
        log::info "Packages installed with APT: $*"
    elif utils::has yum; then
        utils::quiet_err yum install -y "$@"
        log::info "Packages installed with YUM: $*"
    elif utils::has dnf; then
        utils::quiet_err dnf install -y "$@"
        log::info "Packages installed with DNF: $*"
    elif utils::has pacman; then
        utils::quiet_err pacman -S --noconfirm "$@"
        log::info "Packages installed with Pacman: $*"
    elif utils::has zypper; then
        utils::quiet_err zypper install -y "$@"
        log::info "Packages installed with Zypper: $*"
    else
        log::warn "No supported package manager found"
        return "${E_ERROR}"
    fi
}

# @description Remove packages / Удалить пакеты
# @param $@ Package names / Имена пакетов
# @example
#   system::packages::remove "vim" "git"
system::packages::remove() {
    if [[ $# -eq 0 ]]; then
        log::warn "No packages specified for removal"
        return "${E_ERROR}"
    fi
    
    # Detect package manager / Определить менеджер пакетов
    if utils::has apt; then
        utils::quiet_err apt remove -y "$@"
        log::info "Packages removed with APT: $*"
    elif utils::has yum; then
        utils::quiet_err yum remove -y "$@"
        log::info "Packages removed with YUM: $*"
    elif utils::has dnf; then
        utils::quiet_err dnf remove -y "$@"
        log::info "Packages removed with DNF: $*"
    elif utils::has pacman; then
        utils::quiet_err pacman -R --noconfirm "$@"
        log::info "Packages removed with Pacman: $*"
    elif utils::has zypper; then
        utils::quiet_err zypper remove -y "$@"
        log::info "Packages removed with Zypper: $*"
    else
        log::warn "No supported package manager found"
        return "${E_ERROR}"
    fi
}

# @description Upgrade all packages / Обновить все пакеты
# @example
#   system::packages::upgrade
system::packages::upgrade() {
    # Detect package manager / Определить менеджер пакетов
    if utils::has apt; then
        utils::quiet_err apt upgrade -y
        log::info "Packages upgraded with APT"
    elif utils::has yum; then
        utils::quiet_err yum update -y
        log::info "Packages upgraded with YUM"
    elif utils::has dnf; then
        utils::quiet_err dnf upgrade -y
        log::info "Packages upgraded with DNF"
    elif utils::has pacman; then
        utils::quiet_err pacman -Syu --noconfirm
        log::info "Packages upgraded with Pacman"
    elif utils::has zypper; then
        utils::quiet_err zypper update -y
        log::info "Packages upgraded with Zypper"
    else
        log::warn "No supported package manager found"
        return "${E_ERROR}"
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
        return "${E_ERROR}"
    fi
    
    # Detect package manager / Определить менеджер пакетов
    if utils::has apt; then
        utils::quiet_err apt search "${search_term}" || :
    elif utils::has yum; then
        utils::quiet_err yum search "${search_term}" || :
    elif utils::has dnf; then
        utils::quiet_err dnf search "${search_term}" || :
    elif utils::has pacman; then
        utils::quiet_err pacman -Ss "${search_term}" || :
    elif utils::has zypper; then
        utils::quiet_err zypper search "${search_term}" || :
    else
        log::warn "No supported package manager found"
        return "${E_ERROR}"
    fi
}

# @description List installed packages / Показать установленные пакеты
# @example
#   system::packages::list
system::packages::list() {
    # Detect package manager
    if utils::has apt; then
        utils::quiet_err apt list --installed || :
    elif utils::has yum; then
        utils::quiet_err yum list installed || :
    elif utils::has dnf; then
        utils::quiet_err dnf list installed || :
    elif utils::has pacman; then
        utils::quiet_err pacman -Q || :
    elif utils::has zypper; then
        utils::quiet_err zypper search -i || :
    else
        log::warn "No supported package manager found"
        return "${E_ERROR}"
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
        return "${E_ERROR}"
    fi
    
    # Detect package manager / Определить менеджер пакетов
    if utils::has apt; then
        if [[ "${repo}" == ppa:* ]]; then
            utils::quiet_err apt-add-repository -y "${repo}"
        else
            io::files::append /etc/apt/sources.list "${repo}"
        fi
        log::info "Repository added for APT: ${repo}"
    elif utils::has yum; then
        utils::quiet_err yum-config-manager --add-repo "${repo}"
        log::info "Repository added for YUM: ${repo}"
    elif utils::has dnf; then
        utils::quiet_err dnf config-manager --add-repo "${repo}"
        log::info "Repository added for DNF: ${repo}"
    else
        log::warn "Repository management not implemented for this package manager"
        return "${E_ERROR}"
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
        return "${E_ERROR}"
    fi
    
    # Detect package manager / Определить менеджер пакетов
    if utils::has apt; then
        if [[ "${repo}" == ppa:* ]]; then
            utils::quiet_err apt-add-repository -r -y "${repo}"
        else
            # Remove from sources.list / Удалить из sources.list
            utils::quiet_err sed -i "\|${repo}|d" /etc/apt/sources.list
        fi
        log::info "Repository removed for APT: ${repo}"
    elif utils::has yum; then
        # For YUM, we need to find and remove the repo file / Для YUM нужно найти и
        # удалить файл репозитория
        local repo_file=$(utils::quiet_err find /etc/yum.repos.d/ -name "*.repo" -exec grep -l "${repo}" {} \;)
        if [[ -n "${repo_file}" ]]; then
            utils::quiet_err rm -f "${repo_file}"
            log::info "Repository file removed for YUM: ${repo_file}"
        fi
    elif utils::has dnf; then
        # For DNF, we need to find and remove the repo file / Для DNF нужно найти и
        # удалить файл репозитория
        local repo_file=$(utils::quiet_err find /etc/yum.repos.d/ -name "*.repo" -exec grep -l "${repo}" {} \;)
        if [[ -n "${repo_file}" ]]; then
            utils::quiet_err rm -f "${repo_file}"
            log::info "Repository file removed for DNF: ${repo_file}"
        fi
    else
        log::warn "Repository management not implemented for this package manager"
        return "${E_ERROR}"
    fi
}