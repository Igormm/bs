#!/usr/bin/env bs
# shellcheck shell=bash
# examples/gpu_diag.sh — GPU diagnostic and stress CLI
# examples/gpu_diag.sh — диагностика и нагрузочный тест видеокарты
#
# Попробуйте / Try it:
#   bs run examples/gpu_diag.sh
#   bs run examples/gpu_diag.sh --list
#   bs run examples/gpu_diag.sh --check
#   bs run examples/gpu_diag.sh --stress 30

load "core/args"
load "lib/io/streams"
load "lib/system/gpu"

main() {
    args::flag list
    args::flag check
    args::flag stress value
    args::flag_describe list "List detected GPUs (vendor<TAB>name)"
    args::flag_describe check "Run full diagnostics report"
    args::flag_describe stress "Stress test for N seconds (needs glmark2/vkcube/glxgears/gpu-burn)"

    args::require "$@"

    if args::flag_is_set list; then
        gpu::detect || return $?
        return 0
    fi

    if args::flag_is_set check; then
        gpu::check
        return $?
    fi

    if args::flag_is_set stress; then
        local secs
        secs="$(args::flag_get stress)"
        gpu::stress "${secs}"
        return $?
    fi

    if ! gpu::info; then
        io::streams::eprint "GPU не найдена (lspci: нет VGA/3D/Display) / no GPU found"
        return "${LIB_ERROR_FILE_NOT_FOUND}"
    fi
    io::streams::print "Полная диагностика: --check; нагрузочный тест: --stress N"
    io::streams::print "Full diagnostics: --check; stress test: --stress N"
}

main "$@"