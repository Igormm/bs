#!/usr/bin/env bs
# shellcheck shell=bash
# packages.sh — Package management for system setup / Управление пакетами для настройки
# системы
# @depends core/const, core/logger, core/utils, lib/io/files

# Source Guard / Защита от повторной загрузки
bs::guard "SYSTEM_PACKAGES" || return 0

# Зависимости / Dependencies
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh" "../io/files.sh"

# @private Run a package-manager command; log success, or the output tail on failure
# @private Выполнить команду пакетного менеджера; записать успех или хвост вывода при ошибке
# @param $1 Success message / Сообщение об успехе
# @param $@ Command and arguments / Команда и аргументы
# @return 0 on success, E_ERROR otherwise / 0 при успехе, иначе E_ERROR
system::packages::__run() {
    local -r message="${1:?message required}"
    shift
    # stdout остаётся видимым (прогресс), stderr собираем для сообщения об ошибке
    # stdout stays visible (progress), stderr is collected for the error message
    local errfile
    errfile="$(mktemp)" || errfile=""
    if "$@" 2> "${errfile:-/dev/null}"; then
        log::info "${message}"
        if is::not_empty "${errfile}"; then utils::ignore rm -f -- "${errfile}"; fi
        return 0
    fi
    log::error "Command failed / Команда не удалась: $*"
    if is::not_empty "${errfile}"; then
        log::error "$(tail -n 5 "${errfile}" 2>/dev/null)"
        utils::ignore rm -f -- "${errfile}"
    fi
    return "${E_ERROR}"
}

# @private Remove .repo files that mention the repository text (fixed-string match, one by one)
# @private Удалить .repo-файлы, где встречается текст репозитория (точное совпадение, по одному)
# @param $1 Repository text / Текст репозитория
# @param $2 Manager label for the log / Метка менеджера для журнала
system::packages::__remove_repo_files() {
    local -r repo="${1:?repo required}" label="${2:-}"
    local file
    while IFS= read -r file; do
        if is::empty "${file}"; then continue; fi
        if utils::quiet_err rm -f -- "${file}"; then
            log::info "Repository file removed for ${label}: ${file}"
        fi
    done < <(utils::attempt grep -rlF --include='*.repo' -- "${repo}" /etc/yum.repos.d/)
}

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
        system::packages::__run "Packages installed with APT: $*" apt install -y "$@" || return "${E_ERROR}"
    elif utils::has yum; then
        system::packages::__run "Packages installed with YUM: $*" yum install -y "$@" || return "${E_ERROR}"
    elif utils::has dnf; then
        system::packages::__run "Packages installed with DNF: $*" dnf install -y "$@" || return "${E_ERROR}"
    elif utils::has pacman; then
        system::packages::__run "Packages installed with Pacman: $*" pacman -S --noconfirm "$@" || return "${E_ERROR}"
    elif utils::has zypper; then
        system::packages::__run "Packages installed with Zypper: $*" zypper install -y "$@" || return "${E_ERROR}"
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
        system::packages::__run "Packages removed with APT: $*" apt remove -y "$@" || return "${E_ERROR}"
    elif utils::has yum; then
        system::packages::__run "Packages removed with YUM: $*" yum remove -y "$@" || return "${E_ERROR}"
    elif utils::has dnf; then
        system::packages::__run "Packages removed with DNF: $*" dnf remove -y "$@" || return "${E_ERROR}"
    elif utils::has pacman; then
        system::packages::__run "Packages removed with Pacman: $*" pacman -R --noconfirm "$@" || return "${E_ERROR}"
    elif utils::has zypper; then
        system::packages::__run "Packages removed with Zypper: $*" zypper remove -y "$@" || return "${E_ERROR}"
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
        system::packages::__run "Packages upgraded with APT" apt upgrade -y || return "${E_ERROR}"
    elif utils::has yum; then
        system::packages::__run "Packages upgraded with YUM" yum update -y || return "${E_ERROR}"
    elif utils::has dnf; then
        system::packages::__run "Packages upgraded with DNF" dnf upgrade -y || return "${E_ERROR}"
    elif utils::has pacman; then
        system::packages::__run "Packages upgraded with Pacman" pacman -Syu --noconfirm || return "${E_ERROR}"
    elif utils::has zypper; then
        system::packages::__run "Packages upgraded with Zypper" zypper update -y || return "${E_ERROR}"
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
    local search_term="${1:-}"
    
    if is::empty "${search_term}"; then
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
    local repo="${1:-}"
    
    if is::empty "${repo}"; then
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
    local repo="${1:-}"
    
    if is::empty "${repo}"; then
        log::warn "Repository specification not provided"
        return "${E_ERROR}"
    fi
    
    # Detect package manager / Определить менеджер пакетов
    if utils::has apt; then
        if [[ "${repo}" == ppa:* ]]; then
            utils::quiet_err apt-add-repository -r -y "${repo}"
        else
            # Remove from sources.list / Удалить из sources.list
            # Точное совпадение подстроки, не regex: "." и "*" в адресе
            # репозитория не должны удалять чужие строки
            # Fixed-string match, not a regex: "." and "*" in a repository
            # address must not delete foreign lines
            local sources_tmp
            sources_tmp="$(mktemp)" || return "${E_ERROR}"
            if awk -v r="${repo}" 'index($0, r) == 0' /etc/apt/sources.list > "${sources_tmp}" \
                && cat -- "${sources_tmp}" > /etc/apt/sources.list; then
                :
            else
                utils::ignore rm -f -- "${sources_tmp}"
                log::error "Failed to update /etc/apt/sources.list"
                return "${E_ERROR}"
            fi
            utils::ignore rm -f -- "${sources_tmp}"
        fi
        log::info "Repository removed for APT: ${repo}"
    elif utils::has yum; then
        # For YUM, we need to find and remove the repo file / Для YUM нужно найти и
        # удалить файл репозитория
        system::packages::__remove_repo_files "${repo}" "YUM"
    elif utils::has dnf; then
        # For DNF, we need to find and remove the repo file / Для DNF нужно найти и
        # удалить файл репозитория
        system::packages::__remove_repo_files "${repo}" "DNF"
    else
        log::warn "Repository management not implemented for this package manager"
        return "${E_ERROR}"
    fi
}