#!/usr/bin/env bs
# shellcheck shell=bash
# examples/sensor_diag.sh — Sensor diagnostic CLI / Диагностика сенсорных устройств
#
# Попробуйте / Try it:
#   bs run examples/sensor_diag.sh
#   bs run examples/sensor_diag.sh --list
#   bs run examples/sensor_diag.sh --device event5 --window 5

set -euo pipefail

load "core/args"
load "lib/io/streams"
load "lib/system/sensor"

main() {
    args::flag device value
    args::flag list
    args::flag window value
    args::flag_describe device "Sensor device: eventN (default: first EV_ABS device)"
    args::flag_describe list "List touch-capable devices"
    args::flag_describe window "Live observation window, seconds (default: 3)"

    args::require "$@"

    if args::flag_is_set list; then
        io::streams::print "Sensor-устройства / sensor-capable devices:"
        local ev name
        while IFS=$'\t' read -r ev name; do
            local abs
            abs="$(utils::quiet_err cat "/sys/class/input/${ev}/device/capabilities/abs" 2>/dev/null)"
            is::not_empty "${abs}" && [[ "${abs}" != "0" ]] && \
                io::streams::print "  ${ev}  ${name}  abs=${abs}"
        done < <(sensor::devices)
        return 0
    fi

    local dev
    if args::flag_is_set device; then
        dev="$(args::flag_get device)"
    else
        dev=""
        local ev name abs
        while IFS=$'\t' read -r ev name; do
            abs="$(utils::quiet_err cat "${SENSOR_INPUT_DIR}/${ev}/device/capabilities/abs" 2>/dev/null)"
            if is::not_empty "${abs}" && [[ "${abs}" != "0" ]]; then
                dev="${ev}"
                break
            fi
        done < <(sensor::devices)
        if is::empty "${dev}"; then
            io::streams::eprint "Сенсор-устройств (EV_ABS) не найдено / no EV_ABS devices found"
            return "${LIB_ERROR_FILE_NOT_FOUND}"
        fi
    fi

    local win="3"
    args::flag_is_set window && win="$(args::flag_get window)"
    sensor::diagnose "${dev}" "${win}"
}

main "$@"
