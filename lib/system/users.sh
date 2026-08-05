#!/usr/bin/env bs
# shellcheck shell=bash
# users.sh — User and group management for system setup / Управление пользователями и
# группами для настройки системы
# @depends core/const, core/logger, core/utils

# Source Guard / Защита от повторной загрузки
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/prereq.sh"
bs::guard "SYSTEM_USERS" || return 0

# Зависимости / Dependencies
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh"

# @description Create a new system user / Создать нового системного пользователя
# @param $1 Username / Имя пользователя
# @param $2 [optional] Home directory / [опционально] Домашняя директория
# @param $3 [optional] Shell / [опционально] Оболочка
# @example
#   system::users::create "newuser"
#   system::users::create "newuser" "/home/newuser" "/bin/bash"
system::users::create() {
    local username="${1}"
    local home_dir="${2:-/home/${username}}"
    local shell="${3:-/bin/bash}"
    
    if [[ -z "${username}" ]]; then
        log::warn "Username not specified"
        return 1
    fi
    
    # Check if user already exists / Проверить, существует ли пользователь
    if utils::quiet id "${username}"; then
        log::warn "User ${username} already exists"
        return 1
    fi
    
    # Try useradd (most common) / Попробовать useradd (наиболее распространенный)
    if utils::has useradd; then
        if utils::quiet_err useradd -m -d "${home_dir}" -s "${shell}" "${username}"; then
            log::info "User ${username} created successfully"
            return 0
        else
            log::error "Failed to create user ${username}"
            return 1
        fi
    # Fallback to adduser (some Debian-based systems) / Резервный вариант adduser
    # (некоторые Debian-системы)
    elif utils::has adduser; then
        if utils::quiet_err adduser --home "${home_dir}" --shell "${shell}" --disabled-password --gecos "" "${username}"; then
            log::info "User ${username} created successfully"
            return 0
        else
            log::error "Failed to create user ${username}"
            return 1
        fi
    else
        log::error "No suitable command found to create user (useradd/adduser)"
        return 1
    fi
}

# @description Delete a system user / Удалить системного пользователя
# @param $1 Username / Имя пользователя
# @param $2 [optional] Remove home directory ("yes" to remove) / [опционально] Удалить
# домашнюю директорию ("yes" для удаления)
# @example
#   system::users::delete "olduser"
#   system::users::delete "olduser" "yes"
system::users::delete() {
    local username="${1}"
    local remove_home="${2:-no}"
    
    if [[ -z "${username}" ]]; then
        log::warn "Username not specified"
        return 1
    fi
    
    # Check if user exists / Проверить, существует ли пользователь
    if ! utils::quiet id "${username}"; then
        log::warn "User ${username} does not exist"
        return 1
    fi
    
    local remove_flag=""
    if [[ "${remove_home}" == "yes" ]]; then
        remove_flag="-r"
    fi
    
    if utils::has userdel; then
        if utils::quiet_err userdel ${remove_flag} "${username}"; then
            log::info "User ${username} deleted successfully"
            return 0
        else
            log::error "Failed to delete user ${username}"
            return 1
        fi
    else
        log::error "userdel command not found"
        return 1
    fi
}

# @description Set password for a user / Установить пароль для пользователя
# @param $1 Username / Имя пользователя
# @param $2 [optional] Password (if not provided, will prompt) / [опционально] Пароль
# (если не указан, будет запрошен)
# @warning Passing the password as an argument exposes it in plain text: it is visible
# in the process list and shell history. Prefer interactive mode (omit $2).
# @warning Передача пароля аргументом раскрывает его открытым текстом: он виден в
# списке процессов и истории shell. Предпочтительнее интерактивный режим (без $2).
# @example
#   system::users::set_password "username" "newpassword"
system::users::set_password() {
    local username="${1}"
    local password="${2:-}"
    
    if [[ -z "${username}" ]]; then
        log::warn "Username not specified"
        return 1
    fi
    
    if ! utils::quiet id "${username}"; then
        log::warn "User ${username} does not exist"
        return 1
    fi
    
    if utils::has chpasswd; then
        if [[ -n "${password}" ]]; then
            echo "${username}:${password}" | utils::quiet_err chpasswd
            if [[ $? -eq 0 ]]; then
                log::info "Password for ${username} changed successfully"
                return 0
            else
                log::error "Failed to change password for ${username}"
                return 1
            fi
        else
            # Interactive password change / Интерактивное изменение пароля
            if utils::quiet_err passwd "${username}"; then
                log::info "Password for ${username} changed successfully"
                return 0
            else
                log::error "Failed to change password for ${username}"
                return 1
            fi
        fi
    elif utils::has passwd; then
        if [[ -n "${password}" ]]; then
            echo "${username}:${password}" | utils::quiet_err passwd --stdin "${username}" || {
                log::warn "passwd --stdin not supported, using interactive mode"
                log::warn "passwd --stdin не поддерживается, используется интерактивный режим"
                utils::quiet_err passwd "${username}"
            }
        else
            utils::quiet_err passwd "${username}"
        fi
        if [[ $? -eq 0 ]]; then
            log::info "Password for ${username} changed successfully"
            return 0
        else
            log::error "Failed to change password for ${username}"
            return 1
        fi
    else
        log::error "No suitable command found to change password (chpasswd/passwd)"
        return 1
    fi
}

# @description Add user to a group / Добавить пользователя в группу
# @param $1 Username / Имя пользователя
# @param $2 Group name / Имя группы
# @example
#   system::users::add_to_group "username" "sudo"
system::users::add_to_group() {
    local username="${1}"
    local group="${2}"
    
    if [[ -z "${username}" ]] || [[ -z "${group}" ]]; then
        log::warn "Username and group must be specified"
        return 1
    fi
    
    if ! utils::quiet id "${username}"; then
        log::warn "User ${username} does not exist"
        return 1
    fi
    
    if ! utils::quiet getent group "${group}"; then
        log::warn "Group ${group} does not exist"
        return 1
    fi
    
    if utils::has usermod; then
        if utils::quiet_err usermod -a -G "${group}" "${username}"; then
            log::info "User ${username} added to group ${group}"
            return 0
        else
            log::error "Failed to add ${username} to group ${group}"
            return 1
        fi
    elif utils::has gpasswd; then
        if utils::quiet_err gpasswd -a "${username}" "${group}"; then
            log::info "User ${username} added to group ${group}"
            return 0
        else
            log::error "Failed to add ${username} to group ${group}"
            return 1
        fi
    else
        log::error "No suitable command found (usermod/gpasswd)"
        return 1
    fi
}

# @description List all system users / Показать всех системных пользователей
# @example
#   system::users::list
system::users::list() {
    if utils::has getent; then
        getent passwd | cut -d: -f1 | sort
    elif [[ -f /etc/passwd ]]; then
        cut -d: -f1 /etc/passwd | sort
    else
        log::error "Cannot list users (getent or /etc/passwd not available)"
        return 1
    fi
}

# @description Get information about a user / Получить информацию о пользователе
# @param $1 Username / Имя пользователя
# @example
#   system::users::info "username"
system::users::info() {
    local username="${1}"
    
    if [[ -z "${username}" ]]; then
        log::warn "Username not specified"
        return 1
    fi
    
    if ! utils::quiet id "${username}"; then
        log::warn "User ${username} does not exist"
        return 1
    fi
    
    local info
    info=$(utils::quiet_err id "${username}")
    log::info "User info for ${username}: ${info}"
    
    # Additional info / Дополнительная информация
    if utils::has getent; then
        local passwd_info
        passwd_info=$(utils::quiet_err getent passwd "${username}")
        if [[ -n "${passwd_info}" ]]; then
            echo "  Full name: $(echo "${passwd_info}" | cut -d: -f5)"
            echo "  Home: $(echo "${passwd_info}" | cut -d: -f6)"
            echo "  Shell: $(echo "${passwd_info}" | cut -d: -f7)"
        fi
        
        local groups
        groups=$(utils::quiet_err groups "${username}" | cut -d: -f2)
        if [[ -n "${groups}" ]]; then
            echo "  Groups:${groups}"
        fi
    fi
}

# @description Lock a user account / Заблокировать учетную запись пользователя
# @param $1 Username / Имя пользователя
# @example
#   system::users::lock "username"
system::users::lock() {
    local username="${1}"
    
    if [[ -z "${username}" ]]; then
        log::warn "Username not specified"
        return 1
    fi
    
    if ! utils::quiet id "${username}"; then
        log::warn "User ${username} does not exist"
        return 1
    fi
    
    if utils::has usermod; then
        if utils::quiet_err usermod -L "${username}"; then
            log::info "User ${username} locked"
            return 0
        else
            log::error "Failed to lock user ${username}"
            return 1
        fi
    elif utils::has passwd; then
        if utils::quiet_err passwd -l "${username}"; then
            log::info "User ${username} locked"
            return 0
        else
            log::error "Failed to lock user ${username}"
            return 1
        fi
    else
        log::error "No suitable command found to lock user"
        return 1
    fi
}

# @description Unlock a user account / Разблокировать учетную запись пользователя
# @param $1 Username / Имя пользователя
# @example
#   system::users::unlock "username"
system::users::unlock() {
    local username="${1}"
    
    if [[ -z "${username}" ]]; then
        log::warn "Username not specified"
        return 1
    fi
    
    if ! utils::quiet id "${username}"; then
        log::warn "User ${username} does not exist"
        return 1
    fi
    
    if utils::has usermod; then
        if utils::quiet_err usermod -U "${username}"; then
            log::info "User ${username} unlocked"
            return 0
        else
            log::error "Failed to unlock user ${username}"
            return 1
        fi
    elif utils::has passwd; then
        if utils::quiet_err passwd -u "${username}"; then
            log::info "User ${username} unlocked"
            return 0
        else
            log::error "Failed to unlock user ${username}"
            return 1
        fi
    else
        log::error "No suitable command found to unlock user"
        return 1
    fi
}

# @description Create a new group / Создать новую группу
# @param $1 Group name / Имя группы
# @example
#   system::users::group_create "developers"
system::users::group_create() {
    local groupname="${1}"
    
    if [[ -z "${groupname}" ]]; then
        log::warn "Group name not specified"
        return 1
    fi
    
    if utils::quiet getent group "${groupname}"; then
        log::warn "Group ${groupname} already exists"
        return 1
    fi
    
    if utils::has groupadd; then
        if utils::quiet_err groupadd "${groupname}"; then
            log::info "Group ${groupname} created successfully"
            return 0
        else
            log::error "Failed to create group ${groupname}"
            return 1
        fi
    else
        log::error "groupadd command not found"
        return 1
    fi
}

# @description Delete a group / Удалить группу
# @param $1 Group name / Имя группы
# @example
#   system::users::group_delete "oldgroup"
system::users::group_delete() {
    local groupname="${1}"
    
    if [[ -z "${groupname}" ]]; then
        log::warn "Group name not specified"
        return 1
    fi
    
    if ! utils::quiet getent group "${groupname}"; then
        log::warn "Group ${groupname} does not exist"
        return 1
    fi
    
    if utils::has groupdel; then
        if utils::quiet_err groupdel "${groupname}"; then
            log::info "Group ${groupname} deleted successfully"
            return 0
        else
            log::error "Failed to delete group ${groupname}"
            return 1
        fi
    else
        log::error "groupdel command not found"
        return 1
    fi
}

# @description List all system groups / Показать все системные группы
# @example
#   system::users::group_list
system::users::group_list() {
    if utils::has getent; then
        getent group | cut -d: -f1 | sort
    elif [[ -f /etc/group ]]; then
        cut -d: -f1 /etc/group | sort
    else
        log::error "Cannot list groups (getent or /etc/group not available)"
        return 1
    fi
}

