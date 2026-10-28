#!/usr/bin/env bs
# shellcheck shell=bash
# @shell bash4 — нужны конструкции bash: double-bracket [[ ]], regex =~ / needs bash constructs: double-bracket [[ ]], regex =~
# bootloader.sh — GRUB2 / systemd-boot configuration with safety (backup/rollback)
# bootloader.sh — конфигурация GRUB2 / systemd-boot с защитой (бэкап/откат)
# @depends core/const, core/logger, core/utils

# Source Guard / Защита от повторной загрузки
bs::guard "SYSTEM_BOOTLOADER" || return 0

# Зависимости / Dependencies
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh"

# Путь к конфигу GRUB (переопределяется для тестов) / The GRUB config path (overridable for tests)
system::bootloader::grub_config() {
    printf '%s' "${BS_GRUB_CONFIG:-/etc/default/grub}"
    return 0
}

# @description Detect the bootloader / Определить загрузчик
# @stdout grub | systemd-boot | none
system::bootloader::detect() {
    if is::file "$(system::bootloader::grub_config)"; then
        printf 'grub\n'
    elif utils::has bootctl && is::dir /boot/loader; then
        printf 'systemd-boot\n'
    else
        printf 'none\n'
    fi
    return 0
}

# @description Read a GRUB key value (quotes stripped) / Прочитать значение ключа GRUB (кавычки сняты)
# @param $1 Key (e.g. GRUB_TIMEOUT) / Ключ
# @stdout value / значение
system::bootloader::grub_get() {
    local -r key="${1:-}"
    local -r conf="$(system::bootloader::grub_config)"
    [[ "${key}" =~ ^[A-Za-z0-9_]+$ ]] || { log::warn "Invalid GRUB key: ${key}"; return "${E_INVALID}"; }
    is::file "${conf}" || { log::warn "No ${conf}"; return "${E_ERROR}"; }

    local line val
    line="$(grep "^${key}=" "${conf}")" || return 1
    val="${line#*=}"
    val="${val#\"}"; val="${val%\"}"
    printf '%s\n' "${val}"
    return 0
}

# @description Validate a GRUB value (no quotes/newline/control chars) / Проверить значение GRUB
# @param $1 value / значение
# @return 0 ok / 1 invalid
system::bootloader::__value_ok() {
    local -r value="${1-}"
    # кавычка сломает файл, перевод строки добавит строку, управляющие символы — мусор
    # a quote would break the file, a newline would add a line, control chars are garbage
    [[ "${value}" == *'"'* || "${value}" == *$'\n'* || "${value}" == *$'\r'* ]] && return 1
    return 0
}

# @description Set a GRUB key atomically (temp + rename), validated / Атомарно задать ключ GRUB
# @param $1 Key / Ключ
# @param $2 Value (may be empty) / Значение (может быть пустым)
system::bootloader::grub_set() {
    local -r key="${1:-}" value="${2-}"
    local -r conf="$(system::bootloader::grub_config)"
    [[ "${key}" =~ ^[A-Za-z0-9_]+$ ]] || { log::warn "Invalid GRUB key: ${key}"; return "${E_INVALID}"; }
    system::bootloader::__value_ok "${value}" || { log::warn "Invalid GRUB value for ${key}"; return "${E_INVALID}"; }

    case "${key}" in
        GRUB_TIMEOUT) [[ "${value}" =~ ^[0-9]+$ ]] || { log::warn "GRUB_TIMEOUT must be a non-negative integer"; return "${E_INVALID}"; } ;;
        GRUB_TERMINAL_OUTPUT) [[ "${value}" =~ ^[a-zA-Z,]+$ ]] || { log::warn "GRUB_TERMINAL_OUTPUT: letters and commas only"; return "${E_INVALID}"; } ;;
    esac

    is::file "${conf}" || { log::error "No ${conf}"; return "${E_ERROR}"; }

    # атомарно: awk пишет в temp, mv заменяет / atomic: awk writes to temp, mv replaces
    local -r tmp="${conf}.tmp.$$"
    awk -v key="${key}" -v val="${value}" '
        $0 ~ "^" key "=" { print key "=\"" val "\""; replaced=1; next }
        { print }
        END { if (!replaced) print key "=\"" val "\"" }
    ' "${conf}" > "${tmp}" || { rm -f "${tmp}"; log::error "Cannot edit ${conf}"; return "${E_ERROR}"; }
    mv -f -- "${tmp}" "${conf}" || { rm -f "${tmp}"; log::error "Cannot write ${conf}"; return "${E_ERROR}"; }

    log::info "GRUB ${key} set to ${value}"
    return 0
}

# @description Back up the GRUB config / Создать бэкап конфига GRUB
# @stdout path to the backup / путь к бэкапу
system::bootloader::grub_backup() {
    local -r conf="$(system::bootloader::grub_config)"
    is::file "${conf}" || { log::error "No ${conf}"; return "${E_ERROR}"; }
    local -r dest="${conf}.bak.$(date +%Y%m%d%H%M%S)"
    cp -- "${conf}" "${dest}" || { log::error "Cannot back up ${conf}"; return "${E_ERROR}"; }
    printf '%s\n' "${dest}"
    return 0
}

# @description Restore the GRUB config from a backup / Восстановить конфиг GRUB из бэкапа
# @param $1 Backup path / Путь к бэкапу
system::bootloader::grub_restore() {
    local -r backup="${1:-}"
    local -r conf="$(system::bootloader::grub_config)"
    is::file "${backup}" || { log::error "No backup: ${backup}"; return "${E_ERROR}"; }
    cp -- "${backup}" "${conf}" || { log::error "Cannot restore ${conf}"; return "${E_ERROR}"; }
    log::info "Restored ${conf} from ${backup}"
    return 0
}

# @description List GRUB backups (newest last) / Показать бэкапы GRUB
system::bootloader::grub_backups() {
    local -r conf="$(system::bootloader::grub_config)"
    if is::file "${conf}"; then
        find "$(dirname "${conf}")" -maxdepth 1 -name "$(basename "${conf}").bak.*" -type f 2>/dev/null | sort
    fi
    return 0
}

# @description Regenerate the bootloader config / Перегенерировать конфиг загрузчика
system::bootloader::regenerate() {
    if utils::has grub2-mkconfig; then
        utils::quiet grub2-mkconfig -o "${BS_GRUB_CFG:-/boot/grub2/grub.cfg}" \
            || { log::error "grub2-mkconfig failed"; return "${E_ERROR}"; }
    elif utils::has update-grub; then
        utils::quiet update-grub || { log::error "update-grub failed"; return "${E_ERROR}"; }
    else
        log::error "No grub2-mkconfig / update-grub found"
        return "${E_ERROR}"
    fi
    log::info "Bootloader config regenerated"
    return 0
}

# @description systemd-boot status (read-only) / Статус systemd-boot (только чтение)
system::bootloader::bootctl_status() {
    if utils::has bootctl; then
        utils::attempt bootctl status
    else
        log::warn "bootctl not available"
        return "${E_ERROR}"
    fi
}

# @description List EFI boot entries (read-only) / Показать записи EFI (только чтение)
system::bootloader::efi_entries() {
    if utils::has efibootmgr; then
        utils::attempt efibootmgr
    else
        log::warn "efibootmgr not available"
        return "${E_ERROR}"
    fi
}
