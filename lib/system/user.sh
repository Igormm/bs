#!/usr/bin/env bs
# shellcheck shell=bash
# lib/system/user.sh — restricted system user provisioning: create, lock the
# password, add groups, write resource limits and verified sudoers files
# lib/system/user.sh — провижининг ограниченного системного пользователя:
# создание, блокировка пароля, группы, лимиты ресурсов и проверенные sudoers
#
# The sudoers and limits dirs are overridable for tests:
# BS_SUDOERS_DIR (default /etc/sudoers.d), BS_LIMITS_DIR
# (default /etc/security/limits.d).
# Каталоги sudoers и лимитов переопределяются для тестов: BS_SUDOERS_DIR
# (по умолчанию /etc/sudoers.d), BS_LIMITS_DIR (/etc/security/limits.d).
#
# Usage / Использование:
#   load "lib/system/user"
#   user::exists demo
#   user::create demo && user::lock_password demo
#   user::add_group demo systemd-journal
#   user::write_limits demo 128 4096
#   user::write_sudoers demo "systemctl start demo.service" "firewall-cmd *"
#
# @depends core/logger, core/utils

# Source Guard / Защита от повторной загрузки
bs::guard "LIB_SYSTEM_USER" || return 0

# Dependencies / Зависимости
bs::source_relative "../../core/logger.sh" "../../core/utils.sh"

# @global BS_SUDOERS_DIR — Hook: sudoers dir override for tests (category: hook)
# @global BS_SUDOERS_DIR — Хук: каталог sudoers для тестов (категория: hook)
declare -g BS_SUDOERS_DIR="/etc/sudoers.d"
# @global BS_LIMITS_DIR — Hook: limits dir override for tests (category: hook)
# @global BS_LIMITS_DIR — Хук: каталог лимитов для тестов (категория: hook)
declare -g BS_LIMITS_DIR="/etc/security/limits.d"

# @description User exists / Пользователь существует
# @param $1 User name / Имя пользователя
user::exists() { id "${1:?user name required}" >/dev/null 2>&1; }

# @description Create a system user: home dir, no login shell.
# @description Создать системного пользователя: домашний каталог, без шелла.
# @param $1 User name / Имя пользователя
user::create() { useradd -m -s /usr/sbin/nologin "${1:?user name required}"; }

# @description Lock the password (login by password is forbidden).
# @description Заблокировать пароль (вход по паролю запрещён).
# @param $1 User name / Имя пользователя
user::lock_password() { passwd -l "${1:?user name required}"; }

# @description Add the user to a supplementary group.
# @description Добавить пользователя в дополнительную группу.
# @param $1 User name / Имя пользователя
# @param $2 Group / Группа
user::add_group() {
    local -r name="${1:?user name required}" group="${2:?group required}"
    usermod -aG "${group}" "${name}"
}

# @description Write the resource limits file (nproc, nofile, core=0).
# @description Записать файл лимитов ресурсов (nproc, nofile, core=0).
# @param $1 User name / Имя пользователя
# @param $2 nproc limit / лимит nproc
# @param $3 nofile limit / лимит nofile
# @stdout path / путь
user::write_limits() {
    local -r name="${1:?user name required}" nproc="$2" nofile="$3"
    local -r path="${BS_LIMITS_DIR}/${name}.conf"
    cat > "${path}" <<EOF
# Managed by ai_user_wizard / создано визардом
${name} soft nproc ${nproc}
${name} hard nproc ${nproc}
${name} soft nofile ${nofile}
${name} hard nofile ${nofile}
${name} hard core 0
${name} soft core 0
EOF
    printf '%s\n' "${path}"
}

# @description Write and verify a sudoers file (chmod 440 + visudo -c);
# on verification failure the file is removed and 1 is returned.
# @description Записать и проверить файл sudoers (chmod 440 + visudo -c);
# при неудаче проверки файл удаляется и возвращается 1.
# @param $1 User name / Имя пользователя
# @param $@ Sudo rule lines / Строки правил sudo
# @return 0 written and verified, 1 verification failed / 0 записан и проверен,
# 1 проверка не прошла
user::write_sudoers() {
    local -r name="${1:?user name required}"
    shift
    local -r path="${BS_SUDOERS_DIR}/${name}"
    {
        printf '# Managed by ai_user_wizard / создано визардом\n'
        local line
        for line in "$@"; do
            printf '%s ALL=(root) NOPASSWD: %s\n' "${name}" "${line}"
        done
    } > "${path}"
    chmod 440 "${path}"
    if ! visudo -c -f "${path}" >/dev/null 2>&1; then
        rm -f "${path}"
        log::error "user::write_sudoers: visudo -c не прошёл / failed — файл откачен / reverted: ${path}"
        return 1
    fi
    return 0
}