#!/usr/bin/env bs
# shellcheck shell=bash
# lib/system/devprofile.sh — device settings profiles: save, list, load, apply,
# remove; INI with managed markers under ~/.config/bs/profiles/devices
# lib/system/devprofile.sh — профили настроек устройств: сохранить, список,
# загрузить, применить, удалить; INI с управляемыми маркерами в
# ~/.config/bs/profiles/devices
#
# Формат / Format:
#   # Managed by BS / Сгенерировано BS
#   # BEGIN bs-devices
#   [pointers:tp-lenovo-trackpoint]
#   sens=160
#   natural_scroll=0
#   # END bs-devices
#
# @depends core/lang, core/const, core/logger, core/utils, lib/system/devicectl
# @tier core
# @shell bash4 — нужны конструкции bash: double-bracket [[ ]], arithmetic command (( )), array, local/declare flags, nameref / needs bash constructs: double-bracket [[ ]], arithmetic command (( )), array, local/declare flags, nameref

# Source Guard / Защита от повторной загрузки
bs::guard "LIB_SYSTEM_DEVPROFILE" || return 0

# Dependencies / Зависимости
bs::source_relative "../../core/lang.sh" "../../core/const.sh" \
    "../../core/logger.sh" "../../core/utils.sh" "devicectl.sh"

# @global BS_PROFILE_DIR — Profiles root (category: hook)
# @global BS_PROFILE_DIR — Корень профилей (категория: hook)
: "${BS_PROFILE_DIR:=${XDG_CONFIG_HOME:-${HOME:-}/.config}/bs/profiles/devices}"
# @global BS_DEVPROFILE_MARK_BEGIN — Managed block begin marker (category: constant)
# @global BS_DEVPROFILE_MARK_BEGIN — Маркер начала управляемого блока (категория: constant)
readonly BS_DEVPROFILE_MARK_BEGIN="# BEGIN bs-devices"
# @global BS_DEVPROFILE_MARK_END — Managed block end marker (category: constant)
# @global BS_DEVPROFILE_MARK_END — Маркер конца управляемого блока (категория: constant)
readonly BS_DEVPROFILE_MARK_END="# END bs-devices"

# @description Путь файла профиля (с проверкой имени). / Profile file path (name-checked).
# @param $1 Имя профиля / profile name
# @stdout путь / path
devprofile::__path() {
    local -r name="$1"
    case "${name}" in
        ""|*/*|*..*) printf '' ; return "${LIB_ERROR_INVALID_ARGS}" ;;
    esac
    printf '%s/%s.conf' "${BS_PROFILE_DIR}" "${name}"
}

# @private Пометить профиль последним использованным / mark a profile as last accessed
# @param $1 Имя профиля / profile name (empty clears)
devprofile::__set_active() {
    local -r name="$1"
    if [[ -n "${name}" ]]; then
        mkdir -p -- "${BS_PROFILE_DIR}" 2>/dev/null || return "${LIB_ERROR_PERMISSION_DENIED}"
        printf '%s\n' "${name}" > "${BS_PROFILE_DIR}/.active" 2>/dev/null || return "${LIB_ERROR_FILE_OPERATION}"
    elif [[ -f "${BS_PROFILE_DIR}/.active" ]]; then
        rm -f -- "${BS_PROFILE_DIR}/.active" || return "${LIB_ERROR_FILE_OPERATION}"
    fi
    return 0
}

# @description Сохранить профиль из TSV на stdin: driver<TAB>handle<TAB>param<TAB>value.
# @description Save a profile from TSV on stdin: driver<TAB>handle<TAB>param<TAB>value.
# @param $1 Имя профиля / profile name
# @return 0 сохранён / saved
devprofile::save() {
    local -r name="$1"
    local -r path="$(devprofile::__path "${name}")" || return "${LIB_ERROR_INVALID_ARGS}"
    [[ -n "${path}" ]] || return "${LIB_ERROR_INVALID_ARGS}"

    if ! mkdir -p -- "${BS_PROFILE_DIR}" 2>/dev/null; then
        log::error "devprofile: cannot create ${BS_PROFILE_DIR}"
        return "${LIB_ERROR_PERMISSION_DENIED}"
    fi

    local -r tmp="${path}.tmp.$$"
    local drv handle param value sec s
    {
        printf '# Managed by BS / Сгенерировано BS\n'
        printf '%s\n' "${BS_DEVPROFILE_MARK_BEGIN}"
        local -a order=()
        local -A body=()
        while IFS=$'\t' read -r drv handle param value; do
            [[ -n "${drv:-}" && -n "${handle:-}" && -n "${param:-}" ]] || continue
            [[ -n "${value:-}" ]] || continue
            sec="${drv}:${handle}"
            if [[ -z "${body[${sec}]+x}" ]]; then
                order+=("${sec}")
                body[${sec}]=""
            fi
            body[${sec}]+="${param}=${value}"$'\n'
        done
        for s in "${order[@]}"; do
            printf '[%s]\n' "${s}"
            printf '%s' "${body[${s}]}"
        done
        printf '%s\n' "${BS_DEVPROFILE_MARK_END}"
    } > "${tmp}" || { rm -f -- "${tmp}"; return "${LIB_ERROR_FILE_OPERATION}"; }

    if ! mv -f -- "${tmp}" "${path}" 2>/dev/null; then
        rm -f -- "${tmp}"
        log::error "devprofile: cannot write ${path}"
        return "${LIB_ERROR_FILE_OPERATION}"
    fi
    devprofile::__set_active "${name}" || true
    log::info "devprofile: saved ${name}"
    return 0
}

# @description Имена сохранённых профилей / saved profile names.
# @stdout по одному в строке / one per line
devprofile::list() {
    [[ -d "${BS_PROFILE_DIR}" ]] || return 0
    local f
    for f in "${BS_PROFILE_DIR}"/*.conf; do
        [[ -e "${f}" ]] || continue
        printf '%s\n' "$(basename -- "${f}" .conf)"
    done
    return 0
}

# @description Загрузить профиль как TSV driver<TAB>handle<TAB>param<TAB>value.
# @description Load a profile as TSV driver<TAB>handle<TAB>param<TAB>value.
# @param $1 Имя профиля / profile name
devprofile::load() {
    local -r name="$1"
    local -r path="$(devprofile::__path "${name}")" || return "${LIB_ERROR_INVALID_ARGS}"
    [[ -n "${path}" && -f "${path}" ]] || return "${LIB_ERROR_FILE_NOT_FOUND}"

    local sec="" line drv handle value
    local -i managed=0
    while IFS= read -r line; do
        case "${line}" in
            "${BS_DEVPROFILE_MARK_BEGIN}") managed=1 ;;
            "${BS_DEVPROFILE_MARK_END}"*) break ;;
        esac
        (( managed == 1 )) || continue
        case "${line}" in
            "["*) sec="${line#\[}"; sec="${sec%\]}" ;;
            *=*)
                [[ -n "${sec}" ]] || continue
                value="${line#*=}"
                [[ -n "${value}" ]] || continue
                IFS=: read -r drv handle <<< "${sec}"
                [[ -n "${drv:-}" && -n "${handle:-}" ]] || continue
                printf '%s\t%s\t%s\t%s\n' "${drv}" "${handle}" "${line%%=*}" "${value}"
                ;;
        esac
    done < "${path}"
    devprofile::__set_active "${name}" || true
    return 0
}

# @description Имя последнего использованного профиля (или пусто). / last used profile name (or empty).
devprofile::active() {
    [[ -f "${BS_PROFILE_DIR}/.active" ]] || return 0
    local name
    IFS= read -r name < "${BS_PROFILE_DIR}/.active" 2>/dev/null || true
    printf '%s' "${name:-}"
    return 0
}

# @description Применить профиль: реплей value через device::set с отчётом о деградации.
# @description Apply a profile: replay values through device::set, report degradation.
# @param $1 Имя профиля / profile name
# @return 0 всё применено, 1 часть не применилась / 0 ok, 1 partial
devprofile::apply() {
    local -r name="$1"
    local -r ts="$(devprofile::load "${name}")" || return "$?"
    local -i failed=0
    local line drv handle param value
    while IFS= read -r line; do
        [[ -z "${line}" ]] && continue
        IFS=$'\t' read -r drv handle param value <<< "${line}"
        if ! device::set "${drv}" "${handle}" "${param}" "${value}"; then
            failed=$(( failed + 1 ))
            printf 'devprofile: не применено / not applied: %s:%s %s=%s\n' "${drv}" "${handle}" "${param}" "${value}" >&2
        fi
    done <<< "${ts}"
    if (( failed > 0 )); then
        log::warn "devprofile: ${failed} параметров не применились / parameters not applied"
        return 1
    fi
    devprofile::__set_active "${name}" || true
    log::info "devprofile: applied ${name}"
    return 0
}

# @description Удалить профиль (и, если он активен, очистить). / remove a profile (and clear active if match).
# @param $1 Имя профиля / profile name
devprofile::remove() {
    local -r name="$1"
    local -r path="$(devprofile::__path "${name}")" || return "${LIB_ERROR_INVALID_ARGS}"
    [[ -n "${path}" && -f "${path}" ]] || return "${LIB_ERROR_FILE_NOT_FOUND}"
    if [[ "$(devprofile::active)" == "${name}" ]]; then
        devprofile::__set_active "" || true
    fi
    rm -f -- "${path}" || return "${LIB_ERROR_FILE_OPERATION}"
    log::info "devprofile: removed ${name}"
    return 0
}
