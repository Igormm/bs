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
    args::flag tools
    args::flag run value
    args::flag deps value
    args::flag_describe list "List detected GPUs (vendor<TAB>name)"
    args::flag_describe check "Run full diagnostics report"
    args::flag_describe stress "Stress test for N seconds (needs glmark2/vkcube/glxgears/gpu-burn)"
    args::flag_describe tools "List tools catalog with availability (tier<TAB>tool<TAB>package)"
    args::flag_describe run "Run a catalog tool, e.g. --run glxinfo"
    args::flag_describe deps "Check tool presence by tier, e.g. --deps 1 (default: all)"

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

    if args::flag_is_set tools; then
        local tier tool pkg desc mark
        while IFS=$'\t' read -r tier tool pkg desc; do
            if is::command "${tool}"; then
                mark="[OK]"
            else
                mark="[MISS]"
            fi
            printf 'tier=%s %-16s %s %s (%s)\n' "${tier}" "${tool}" "${mark}" "${pkg}" "${desc}"
        done < <(gpu::tools)
        return 0
    fi

    if args::flag_is_set run; then
        local tool
        tool="$(args::flag_get run)"
        gpu::run "${tool}"
        return $?
    fi

    if args::flag_is_set deps; then
        local tier
        tier="$(args::flag_get deps)"
        gpu::check_dependencies "${tier}"
        return $?
    fi

    if ! gpu::info; then
        io::streams::eprint "GPU не найдена (lspci: нет VGA/3D/Display) / no GPU found"
        return "${LIB_ERROR_FILE_NOT_FOUND}"
    fi
    io::streams::print "Полная диагностика: --check; нагрузочный тест: --stress N; инструменты: --tools"
    io::streams::print "Full diagnostics: --check; stress test: --stress N; tools: --tools"
}

main "$@"