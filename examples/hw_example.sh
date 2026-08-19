#!/usr/bin/env bs
# shellcheck shell=bash
# examples/hw_example.sh — Hardware information module demo
# examples/hw_example.sh — Демонстрация модуля информации об оборудовании

set -euo pipefail

load "lib/system/hw"

main() {
    system::hw::info

    printf '\n--- CPU ---\n'
    system::hw::cpu

    printf '\n--- Memory ---\n'
    system::hw::memory

    printf '\n--- Block devices ---\n'
    utils::attempt system::hw::block

    printf '\n--- GPU ---\n'
    utils::attempt system::hw::gpu

    printf '\nLogical cores: %s, total RAM: %s MiB\n' \
        "$(system::hw::cpu_threads)" "$(system::hw::mem_total)"

    printf '\nRun the full report with: system::hw::summary\n'
}

main "$@"
