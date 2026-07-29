#!/usr/bin/env bs
# permissions.sh — File permissions management for system setup / Управление правами
# доступа к файлам для настройки системы

# @description Change file permissions / Изменить права доступа к файлу
# @param $1 File or directory path / Путь к файлу или директории
# @param $2 Permissions (octal like "755" or symbolic like "u+x") / Права доступа
# (восьмеричные как "755" или символьные как "u+x")
# @example
#   system::permissions::chmod "/path/to/file" "755"
#   system::permissions::chmod "/path/to/file" "u+x"
system::permissions::chmod() {
    local target="${1}"
    local permissions="${2}"
    
    if [[ -z "${target}" ]] || [[ -z "${permissions}" ]]; then
        log::warn "File path and permissions must be specified"
        return 1
    fi
    
    if [[ ! -e "${target}" ]]; then
        log::warn "File or directory '${target}' does not exist"
        return 1
    fi
    
    if utils::quiet_err chmod "${permissions}" "${target}"; then
        log::info "Permissions changed to ${permissions} for ${target}"
        return 0
    else
        log::error "Failed to change permissions for ${target}"
        return 1
    fi
}

# @description Change file owner and group / Изменить владельца и группу файла
# @param $1 File or directory path / Путь к файлу или директории
# @param $2 Owner (format: "user" or "user:group") / Владелец (формат: "user" или
# "user:group")
# @example
#   system::permissions::chown "/path/to/file" "username"
#   system::permissions::chown "/path/to/file" "username:groupname"
system::permissions::chown() {
    local target="${1}"
    local owner="${2}"
    
    if [[ -z "${target}" ]] || [[ -z "${owner}" ]]; then
        log::warn "File path and owner must be specified"
        return 1
    fi
    
    if [[ ! -e "${target}" ]]; then
        log::warn "File or directory '${target}' does not exist"
        return 1
    fi
    
    if utils::quiet_err chown "${owner}" "${target}"; then
        log::info "Owner changed to ${owner} for ${target}"
        return 0
    else
        log::error "Failed to change owner for ${target}"
        return 1
    fi
}

# @description Make a file readable / Сделать файл читаемым
# @param $1 File path / Путь к файлу
# @example
#   system::permissions::readable "/path/to/file"
system::permissions::readable() {
    local target="${1}"
    
    if [[ -z "${target}" ]]; then
        log::warn "File path must be specified"
        return 1
    fi
    
    system::permissions::chmod "${target}" "a+r"
}

# @description Make a file writable / Сделать файл записываемым
# @param $1 File path / Путь к файлу
# @example
#   system::permissions::writable "/path/to/file"
system::permissions::writable() {
    local target="${1}"
    
    if [[ -z "${target}" ]]; then
        log::warn "File path must be specified"
        return 1
    fi
    
    system::permissions::chmod "${target}" "a+w"
}

# @description Make a file executable / Сделать файл исполняемым
# @param $1 File path / Путь к файлу
# @example
#   system::permissions::executable "/path/to/script.sh"
system::permissions::executable() {
    local target="${1}"
    
    if [[ -z "${target}" ]]; then
        log::warn "File path must be specified"
        return 1
    fi
    
    if system::permissions::chmod "${target}" "a+x"; then
        log::info "File ${target} is now executable"
        return 0
    else
        return 1
    fi
}

# @description View permissions of a file or directory
# @param $1 File or directory path
# @example
#   system::permissions::view "/path/to/file"
system::permissions::view() {
    local target="${1}"
    
    if [[ -z "${target}" ]]; then
        log::warn "File path must be specified"
        return 1
    fi
    
    if [[ ! -e "${target}" ]]; then
        log::warn "File or directory '${target}' does not exist"
        return 1
    fi
    
    echo "=== Permissions for ${target} ==="
    
    # Use ls -l for detailed view / Использовать ls -l для детального просмотра
    if utils::has ls; then
        utils::quiet_err ls -ld "${target}"
        
        # Parse and explain permissions / Разобрать и объяснить права доступа
        local perms
        perms=$(utils::quiet_err ls -ld "${target}" | awk '{print $1}')
        
        if [[ -n "${perms}" ]]; then
            echo ""
            echo "Permission breakdown:"
            echo "  Type: ${perms:0:1}"
            echo "  Owner: ${perms:1:3} (read=${perms:1:1} write=${perms:2:1} execute=${perms:3:1})"
            echo "  Group: ${perms:4:3} (read=${perms:4:1} write=${perms:5:1} execute=${perms:6:1})"
            echo "  Other: ${perms:7:3} (read=${perms:7:1} write=${perms:8:1} execute=${perms:9:1})"
        fi
        
        # Show numeric permissions / Показать числовые права доступа
        local numeric
        numeric=$(utils::quiet_err stat -c "%a" "${target}" || utils::quiet_err stat -f "%OLp" "${target}")
        if [[ -n "${numeric}" ]]; then
            echo "  Numeric: ${numeric}"
        fi
        
        # Show owner and group / Показать владельца и группу
        local owner_info
        owner_info=$(utils::quiet_err ls -ld "${target}" | awk '{print $3":"$4}')
        if [[ -n "${owner_info}" ]]; then
            echo "  Owner:Group: ${owner_info}"
        fi
    else
        log::error "ls command not found"
        return 1
    fi
}

# @description Recursively change permissions
# @param $1 Directory path
# @param $2 Permissions (octal like "755")
# @example
#   system::permissions::recursive "/path/to/dir" "755"
system::permissions::recursive() {
    local target="${1}"
    local permissions="${2}"
    
    if [[ -z "${target}" ]] || [[ -z "${permissions}" ]]; then
        log::warn "Directory path and permissions must be specified"
        return 1
    fi
    
    if [[ ! -d "${target}" ]]; then
        log::warn "Directory '${target}' does not exist"
        return 1
    fi
    
    if utils::quiet_err chmod -R "${permissions}" "${target}"; then
        log::info "Permissions changed recursively to ${permissions} for ${target}"
        return 0
    else
        log::error "Failed to change permissions recursively for ${target}"
        return 1
    fi
}

# @description Set default permissions (umask-like behavior)
# @param $1 Permissions (octal, default: "022")
# @example
#   system::permissions::default "022"
system::permissions::default() {
    local umask_value="${1:-022}"
    
    # Convert permissions to umask (invert) / Преобразовать права доступа в umask
    # (инвертировать)
    local umask_octal
    case "${umask_value}" in
        755) umask_octal="022" ;;
        750) umask_octal="027" ;;
        700) umask_octal="077" ;;
        644) umask_octal="022" ;;
        600) umask_octal="077" ;;
        *)
            # Assume it's already a umask value / Предположить, что это уже значение umask
            umask_octal="${umask_value}"
            ;;
    esac
    
    if utils::quiet_err umask "${umask_octal}"; then
        log::info "Default umask set to ${umask_octal}"
        return 0
    else
        log::error "Failed to set umask"
        return 1
    fi
}

# @description Set sticky bit on directory
# @param $1 Directory path
# @example
#   system::permissions::sticky "/tmp/shared"
system::permissions::sticky() {
    local target="${1}"
    
    if [[ -z "${target}" ]]; then
        log::warn "Directory path must be specified"
        return 1
    fi
    
    if [[ ! -d "${target}" ]]; then
        log::warn "Directory '${target}' does not exist"
        return 1
    fi
    
    if utils::quiet_err chmod +t "${target}"; then
        log::info "Sticky bit set on ${target}"
        return 0
    else
        log::error "Failed to set sticky bit on ${target}"
        return 1
    fi
}

# @description Set setuid bit on file
# @param $1 File path
# @example
#   system::permissions::setuid "/usr/bin/passwd"
system::permissions::setuid() {
    local target="${1}"
    
    if [[ -z "${target}" ]]; then
        log::warn "File path must be specified"
        return 1
    fi
    
    if [[ ! -f "${target}" ]]; then
        log::warn "File '${target}' does not exist or is not a file"
        return 1
    fi
    
    if utils::quiet_err chmod u+s "${target}"; then
        log::info "Setuid bit set on ${target}"
        log::warn "Setuid files can be security risks. Use with caution!"
        return 0
    else
        log::error "Failed to set setuid bit on ${target}"
        return 1
    fi
}

# @description Set setgid bit on file or directory
# @param $1 File or directory path
# @example
#   system::permissions::setgid "/usr/bin/wall"
system::permissions::setgid() {
    local target="${1}"
    
    if [[ -z "${target}" ]]; then
        log::warn "File or directory path must be specified"
        return 1
    fi
    
    if [[ ! -e "${target}" ]]; then
        log::warn "File or directory '${target}' does not exist"
        return 1
    fi
    
    if utils::quiet_err chmod g+s "${target}"; then
        log::info "Setgid bit set on ${target}"
        return 0
    else
        log::error "Failed to set setgid bit on ${target}"
        return 1
    fi
}

