#!/usr/bin/env bs
# shellcheck shell=bash
# lib/system/pointers.sh — pointing devices driver (touchpad / trackball /
# Lenovo TrackPoint): detect, catalogue, live get/set via xinput (X11) or
# gsettings (Wayland/GNOME), TrackPoint sensitivity via sysfs
# lib/system/pointers.sh — драйвер указательных устройств (тачпад / трекбол /
# трекпоинт Lenovo): детект, каталог, живые get/set через xinput (X11) или
# gsettings (Wayland/GNOME), чувствительность трекпоинта через sysfs
#
# Используется движком lib/system/devicectl.sh через контракт driver::<name>::.*
# Used by lib/system/devicectl.sh through the driver::<name>::.* contract.
#
# @depends core/lang, core/const, core/logger, core/utils, lib/system/devicectl
# @tier core
# @shell bash4 — нужны конструкции bash: double-bracket [[ ]], arithmetic command (( )), array, local/declare flags / needs bash constructs: double-bracket [[ ]], arithmetic command (( )), array, local/declare flags

# Source Guard / Защита от повторной загрузки
bs::guard "LIB_SYSTEM_POINTERS" || return 0

# Dependencies / Зависимости
bs::source_relative "../../core/lang.sh" "../../core/const.sh" \
    "../../core/logger.sh" "../../core/utils.sh" "./devdriver.sh"

# @global DRIVER_POINTERS_XINPUT — Hook: xinput binary or test shim (category: hook)
# @global DRIVER_POINTERS_XINPUT — Хук: бинарь xinput или шим для тестов (категория: hook)
: "${DRIVER_POINTERS_XINPUT:=xinput}"
# @global DRIVER_POINTERS_SENS_PATH — Hook: TrackPoint sensitivity sysfs file (category: hook)
# @global DRIVER_POINTERS_SENS_PATH — Хук: файл чувствительности трекпоинта в sysfs (категория: hook)
: "${DRIVER_POINTERS_SENS_PATH:=}"

# @private Бэкенд: x11 | wayland | none (device::backend, если движок подключён).
driver::pointers::__backend() {
    if is::function device::backend; then
        DEVICECTL_BACKEND="$(device::backend)"
    fi
    printf '%s' "${DEVICECTL_BACKEND:-none}"
}

# @private Классифицировать имя устройства / classify a device name.
# @param $1 Имя устройства / device name
driver::pointers::__kind() {
    local -r n="$(printf '%s' "${1}" | tr '[:upper:]' '[:lower:]')"
    case "${n}" in
        *trackpoint*|*stick*|*tpps*|*eraser*) printf 'trackpoint' ;;
        *trackball*) printf 'trackball' ;;
        *touchpad*|*glidepoint*|*synaptics*|*tactile*) printf 'touchpad' ;;
        *) printf 'pointer' ;;
    esac
}

# @description Список указательных устройств / list pointing devices.
# @stdout TSV handle<TAB>label<TAB>kind
driver::pointers::detect() {
    local handle kind
    if is::command "${DRIVER_POINTERS_XINPUT}"; then
        local line
        while IFS= read -r line; do
            [[ -n "${line}" ]] || continue
            handle="${line}"
            kind="$(driver::pointers::__kind "${handle}")"
            case "${kind}" in
                touchpad|trackball|trackpoint) ;;
                *) kind="pointer" ;;
            esac
            printf '%s\t%s\t%s\n' "${handle}" "${handle}" "${kind}"
        done < <("${DRIVER_POINTERS_XINPUT}" list --name-only 2>/dev/null)
        return 0
    fi
    if is::file "/proc/bus/input/devices"; then
        while IFS= read -r line; do
            case "${line}" in
                N:*) handle="${line#N: Name=\"}"; handle="${handle%\"}" ;;
                *) continue ;;
            esac
            kind="$(driver::pointers::__kind "${handle}")"
            case "${kind}" in
                touchpad|trackball|trackpoint) ;;
                *) kind="pointer" ;;
            esac
            printf '%s\t%s\t%s\n' "${handle}" "${handle}" "${kind}"
        done < "/proc/bus/input/devices"
        return 0
    fi
    log::warn "pointers: no input device source (xinput or /proc)"
    return "${LIB_ERROR_DEPENDENCY_MISSING}"
}

# @private Каталог параметров для вида устройства / parameter catalogue per kind.
# @param $1 kind
# @stdout TSV param<TAB>type<TAB>default<TAB>choices<TAB>tip
driver::pointers::__catalog() {
    local -r kind="$1"
    printf 'speed\trange:-1.0:1.0:0.05\t0.0\t\tspeed / скорость (libinput Accel Speed)\n'
    case "${kind}" in
        touchpad)
            printf 'tap_to_click\tbool\t1\t\ttap to click / касание — щелчок\n'
            printf 'natural_scroll\tbool\t0\t\tnatural scroll / естественная прокрутка\n'
            printf 'profile\tenum:flat,adaptive\tadaptive\tflat,adaptive\taccel profile / профиль ускорения\n'
            ;;
        trackball)
            printf 'natural_scroll\tbool\t0\t\tnatural scroll / естественная прокрутка\n'
            printf 'profile\tenum:flat,adaptive\tadaptive\tflat,adaptive\taccel profile / профиль ускорения\n'
            ;;
        trackpoint)
            printf 'sens\tint\t128\t\tTrackPoint sensitivity (0-255) / чувствительность (0-255)\n'
            printf 'natural_scroll\tbool\t0\t\tnatural scroll / естественная прокрутка\n'
            ;;
        pointer)
            printf 'natural_scroll\tbool\t0\t\tnatural scroll / естественная прокрутка\n'
            ;;
    esac
}

# @description Параметры устройства / device parameters.
# @param $1 handle
# @stdout TSV param<TAB>type<TAB>current<TAB>default<TAB>choices<TAB>tip
driver::pointers::params() {
    local -r handle="$1"
    local -r kind="$(driver::pointers::__kind "${handle}")"
    devdriver::params pointers "${handle}" "unknown" "${kind}"
}

# @private Сопоставить имя libinput-свойства по параметру / libinput property per param.
# @param $1 param
driver::pointers::__xprop() {
    case "${1}" in
        speed)          printf 'libinput Accel Speed' ;;
        profile)        printf 'libinput Accel Profile Enabled' ;;
        natural_scroll) printf 'libinput Natural Scrolling Enabled' ;;
        tap_to_click)   printf 'libinput Tapping Enabled' ;;
        *)              printf '' ;;
    esac
}

# @private Нормализовать bool-значение в 0/1 / normalise a bool value to 0/1.
driver::pointers::__bool() {
    case "${1}" in
        1|true|yes|on)  printf '1' ;;
        0|false|no|off) printf '0' ;;
        *)              printf '' ;;
    esac
}

# @private Файл чувствительности трекпоинта / TrackPoint sensitivity file.
driver::pointers::__sens_path() {
    if [[ -n "${DRIVER_POINTERS_SENS_PATH}" ]]; then
        printf '%s' "${DRIVER_POINTERS_SENS_PATH}"
        return 0
    fi
    local f
    for f in /sys/devices/platform/i8042/serio*/sensitivity; do
        [[ -e "${f}" ]] || continue
        printf '%s' "${f}"
        return 0
    done
    printf ''
}

# @description Текущее значение параметра / current value.
# @param $1 handle; $2 param
# @stdout значение (или unknown) / value (or unknown)
driver::pointers::get() {
    local -r handle="$1" param="$2"
    local -r backend="$(driver::pointers::__backend)"
    case "${param}" in
        sens)
            [[ "$(driver::pointers::__kind "${handle}")" == "trackpoint" ]] || return "${E_INVALID}"
            local -r sp="$(driver::pointers::__sens_path)"
            [[ -n "${sp}" && -r "${sp}" ]] || { printf 'unknown'; return 0; }
            cat -- "${sp}" 2>/dev/null || printf 'unknown'
            return 0
            ;;
    esac
    local -r prop="$(driver::pointers::__xprop "${param}")"
    [[ -n "${prop}" ]] || return "${E_INVALID}"
    case "${backend}" in
        x11)
            "${DRIVER_POINTERS_XINPUT}" list-props "${handle}" 2>/dev/null \
                | awk -v p="${prop}" 'index($0, p) { s=$0; sub(/^[ \t]*[^:]*:[ \t]*/, "", s); printf "%s", s; exit }' \
                | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
            return 0
            ;;
        wayland)
            local -r gs="$(driver::pointers::__gsettings_path "${handle}" "${param}")"
            [[ -n "${gs}" ]] || { printf 'unknown'; return 0; }
            gsettings get "${gs}" 2>/dev/null || { printf 'unknown'; return 0; }
            return 0
            ;;
        *)
            printf 'unknown'
            return 0
            ;;
    esac
}

# @private gsettings schema.key для параметра (GNOME) / gsettings schema.key per param (GNOME).
driver::pointers::__gsettings_path() {
    local -r handle="$1" param="$2"
    local -r kind="$(driver::pointers::__kind "${handle}")"
    case "${param}" in
        natural_scroll)
            case "${kind}" in
                touchpad) printf 'org.gnome.desktop.peripherals.touchpad natural-scroll' ;;
                *)        printf 'org.gnome.desktop.peripherals.mouse natural-scroll' ;;
            esac ;;
        tap_to_click)
            [[ "${kind}" == "touchpad" ]] && printf 'org.gnome.desktop.peripherals.touchpad tap-to-click' || printf '' ;;
        *) printf '' ;;
    esac
}

# @description Живое применение значения / live apply.
# @param $1 handle; $2 param; $3 value
# @return 0 применено; LIB_ERROR_DEPENDENCY / PLATFORM_UNSUPPORTED при деградации
driver::pointers::set() {
    local -r handle="$1" param="$2" value="$3"
    local -r kind="$(driver::pointers::__kind "${handle}")"
    local -r backend="$(driver::pointers::__backend)"
    local rc=0

    case "${param}" in
        sens)
            [[ "${kind}" == "trackpoint" ]] || return "${E_INVALID}"
            [[ "${value}" =~ ^[0-9]+$ ]] && (( value >= 0 && value <= 255 )) || return "${E_INVALID}"
            local -r sp="$(driver::pointers::__sens_path)"
            if [[ -n "${sp}" ]]; then
                if [[ -w "${sp}" ]]; then
                    printf '%s\n' "${value}" > "${sp}" 2>/dev/null || return "${LIB_ERROR_PERMISSION_DENIED}"
                    return 0
                fi
                printf 'pointers: трекпоинт: нужен root для %s (sudo tee / sysfs) / sets TrackPoint via %s\n' "${sp}" "${sp}" >&2
            fi
            return "${LIB_ERROR_PLATFORM_UNSUPPORTED}"
            ;;
    esac

    local -r prop="$(driver::pointers::__xprop "${param}")"
    [[ -n "${prop}" ]] || return "${E_INVALID}"

    case "${backend}" in
        x11)
            local v
            case "${param}" in
                speed)
                    [[ "${value}" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] || return "${E_INVALID}"
                    v="${value}"
                    ;;
                profile)
                    case "${value}" in flat) v="1" ;; adaptive) v="0" ;; *) v="" ;; esac
                    ;;
                *)
                    v="$(driver::pointers::__bool "${value}")"
                    ;;
            esac
            [[ -n "${v}" ]] || return "${E_INVALID}"
            "${DRIVER_POINTERS_XINPUT}" set-prop "${handle}" "${prop}" "${v}" 2>/dev/null && rc=0 || rc="$?"
            if (( rc != 0 )); then
                log::warn "pointers: xinput не применил ${param} к ${handle} / could not set ${param}"
                return "${rc}"
            fi
            return 0
            ;;
        wayland)
            local -r gs="$(driver::pointers::__gsettings_path "${handle}" "${param}")"
            if [[ -n "${gs}" ]] && is::command gsettings; then
                local gv="$value"
                [[ "$(driver::pointers::__bool "${value}")" == "1" ]] && gv="true"
                [[ "$(driver::pointers::__bool "${value}")" == "0" ]] && gv="false"
                # слова schema и key передаются раздельно намеренно / schema+key split on word boundaries by design
                # shellcheck disable=SC2086
                if gsettings set ${gs} "${gv}" 2>/dev/null; then
                    return 0
                fi
            fi
            printf 'pointers: %s: настройте через libinput-конфиг или композитор / not supported here; use the compositor or a libinput config\n' "${param}" >&2
            return "${LIB_ERROR_PLATFORM_UNSUPPORTED}"
            ;;
        *)
            printf 'pointers: нет дисплей-бэкенда настройки %s / no display backend for %s\n' "${param}" "${param}" >&2
            return "${LIB_ERROR_PLATFORM_UNSUPPORTED}"
            ;;
    esac
}

# @description Снимок всех параметров устройства / snapshot of all params.
# @param $1 handle
# @stdout TSV param<TAB>value
driver::pointers::snapshot() {
    local -r handle="$1"
    local -r kind="$(driver::pointers::__kind "${handle}")"
    devdriver::snapshot pointers "${handle}" "unknown" "${kind}"
}
