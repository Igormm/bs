#!/usr/bin/env bs
# shellcheck shell=bash
# lib/system/devicectl.sh — device configurator engine: driver registry, device
# list and live get/set dispatch over a uniform driver contract
# lib/system/devicectl.sh — движок конфигуратора устройств: реестр драйверов,
# список устройств и живой диспетч get/set поверх единого контракта драйверов
#
# Каждый драйвер — модуль lib/system/<name>.sh с пространством имён
# driver::<name>:: и интерфейсом:
#   driver::<name>::detect   -> TSV handle<TAB>label<TAB>kind
#   driver::<name>::params <handle> -> TSV param<TAB>type<TAB>current<TAB>default<TAB>choices<TAB>tip
#   driver::<name>::get <handle> <param>    -> текущее значение
#   driver::<name>::set <handle> <param> <value> -> живое применение (0 / код ошибки)
#   driver::<name>::snapshot <handle> -> TSV param<TAB>value
# Коды возврата: 0 успех; E_INVALID неизвестный handle/param/драйвер;
# LIB_ERROR_DEPENDENCY_MISSING нет нужной утилиты; LIB_ERROR_PLATFORM_UNSUPPORTED
# бэкенд не поддерживает операцию (деградация).
# Each driver is a lib/system/<name>.sh module with the driver::<name>:: namespace
# and the interface above. Return codes: 0 ok; E_INVALID unknown handle/param/driver;
# LIB_ERROR_DEPENDENCY_MISSING a required tool is absent; LIB_ERROR_PLATFORM_UNSUPPORTED
# the backend cannot do this (degradation).
#
# @depends core/lang, core/const, core/logger, core/utils
# @tier core
# @shell bash4 — нужны конструкции bash: double-bracket [[ ]], arithmetic command (( )), array, local/declare flags, nameref / needs bash constructs: double-bracket [[ ]], arithmetic command (( )), array, local/declare flags, nameref

# Source Guard / Защита от повторной загрузки
bs::guard "LIB_SYSTEM_DEVICECTL" || return 0

# Dependencies / Зависимости
bs::source_relative "../../core/lang.sh" "../../core/const.sh" \
    "../../core/logger.sh" "../../core/utils.sh"

# @global DEVICECTL_DRIVERS — Driver registry: source names (category: state)
# @global DEVICECTL_DRIVERS — Реестр драйверов: имена для загрузки (категория: state)
declare -ga DEVICECTL_DRIVERS=(pointers keyboard locale)
# @global DEVICECTL_BACKEND — Detected display backend x11|wayland|none (category: hook)
# @global DEVICECTL_BACKEND — Обнаруженный бэкенд x11|wayland|none (категория: hook)
: "${DEVICECTL_BACKEND:=}"
# @global DEVICECTL_DRIVER_EXT — Driver file extension (category: hook)
# @global DEVICECTL_DRIVER_EXT — Расширение файла драйвера (категория: hook)
: "${DEVICECTL_DRIVER_EXT:=sh}"

# @description Определить (и закэшировать) бэкенд дисплея: x11 | wayland | none.
# @description Detect (and cache) the display backend: x11 | wayland | none.
# @stdout x11 / wayland / none
device::backend() {
    if [[ -n "${DEVICECTL_BACKEND}" ]]; then
        printf '%s' "${DEVICECTL_BACKEND}"
        return 0
    fi
    local -r session="${XDG_SESSION_TYPE:-}"
    case "${session}" in
        wayland) DEVICECTL_BACKEND="wayland" ;;
        x11)     DEVICECTL_BACKEND="x11" ;;
    esac
    if [[ -z "${DEVICECTL_BACKEND}" && -n "${WAYLAND_DISPLAY:-}" ]]; then
        DEVICECTL_BACKEND="wayland"
    fi
    if [[ -z "${DEVICECTL_BACKEND}" && -n "${DISPLAY:-}" ]]; then
        DEVICECTL_BACKEND="x11"
    fi
    if [[ -z "${DEVICECTL_BACKEND}" ]] && is::command loginctl; then
        local -r s="$(loginctl show-session 2>/dev/null | sed -n 's/^Type=//p')"
        case "${s}" in
            wayland) DEVICECTL_BACKEND="wayland" ;;
            x11)     DEVICECTL_BACKEND="x11" ;;
        esac
    fi
    [[ -n "${DEVICECTL_BACKEND}" ]] || DEVICECTL_BACKEND="none"
    printf '%s' "${DEVICECTL_BACKEND}"
}

# @description Зарегистрировать драйверы (без дублей, источник не грузится сразу).
# @description Register drivers (no duplicates; nothing is sourced yet).
# @param $@ Имена драйверов / driver names
device::registry() {
    local name
    for name in "$@"; do
        [[ -n "${name}" ]] || continue
        local -i seen=0
        local d
        for d in "${DEVICECTL_DRIVERS[@]:-}"; do
            [[ "${d}" == "${name}" ]] && { seen=1; break; }
        done
        (( seen == 0 )) && DEVICECTL_DRIVERS+=("${name}")
    done
    return 0
}

# @description Загрузить модуль драйвера (идемпотентно: по наличию detect).
# @description Load a driver module (idempotent: checked via its detect hook).
# @param $1 Имя драйвера / driver name
# @return 0 загружен, E_INVALID имя драйвера пусто/некорректно
device::load() {
    local -r name="${1:?driver name required}"
    if is::function "driver::${name}::detect"; then
        return 0
    fi
    case "${name}" in
        *[!A-Za-z0-9_]*|"") log::warn "devicectl: bad driver name: ${name}"; return "${E_INVALID}" ;;
    esac
    if ! bs::source_relative "${name}.${DEVICECTL_DRIVER_EXT}"; then
        log::warn "devicectl: cannot load driver ${name}"
        return "${E_INVALID}"
    fi
    is::function "driver::${name}::detect" && return 0
    log::warn "devicectl: driver ${name} has no detect hook"
    return "${E_INVALID}"
}

# @private Диспетчер вызова: device::__call <name> <fn> [args...]
device::__call() {
    local -r name="$1" fn="$2"
    shift 2
    device::load "${name}" || return "${E_INVALID}"
    if ! is::function "driver::${name}::${fn}"; then
        log::warn "devicectl: driver ${name} lacks ${fn}"
        return "${E_INVALID}"
    fi
    "driver::${name}::${fn}" "$@"
}

# @description Список устройств всех (или заданных) драйверов.
# @description List devices of all (or given) drivers.
# @param $@ Опциональные имена драйверов / optional driver names
# @stdout TSV driver<TAB>handle<TAB>label<TAB>kind
device::list() {
    local -a names=()
    if (( $# > 0 )); then
        names=("$@")
    else
        names=("${DEVICECTL_DRIVERS[@]:-}")
    fi
    local name
    for name in "${names[@]}"; do
        local block
        block="$(device::__call "${name}" detect || true)"
        [[ -z "${block}" ]] && continue
        local line
        while IFS= read -r line; do
            [[ -z "${line}" ]] && continue
            printf '%s\t%s\n' "${name}" "${line}"
        done <<< "${block}"
    done
    return 0
}

# @description Параметры устройства драйвера / driver's device parameters.
# @param $1 Драйвер / driver; $2 handle
# @stdout TSV param<TAB>type<TAB>current<TAB>default<TAB>choices<TAB>tip
device::params() {
    device::__call "$1" params "$2"
}

# @description Текущее значение параметра / current parameter value.
# @param $1 Драйвер / driver; $2 handle; $3 param
device::get() {
    device::__call "$1" get "$2" "$3"
}

# @description Живое применение значения / live apply of a value.
# @param $1 Драйвер / driver; $2 handle; $3 param; $4 value
device::set() {
    device::__call "$1" set "$2" "$3" "$4"
}

# @description Снимок всех параметров устройства / all params snapshot.
# @param $1 Драйвер / driver; $2 handle
# @stdout TSV param<TAB>value
device::snapshot() {
    device::__call "$1" snapshot "$2"
}
