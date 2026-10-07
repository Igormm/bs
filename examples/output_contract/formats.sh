#!/usr/bin/env bs
# shellcheck shell=bash
# examples/output_contract/formats.sh — output contract demo: data formats
# examples/output_contract/formats.sh — демо контракта вывода: форматы данных
#
# Один канонический набор данных, три представления: string/json/xml.
# One canonical dataset, three representations: string/json/xml.
#
# Run / Запуск:
#   bs run examples/output_contract/formats.sh

load "lib/data/format"

main() {
    printf 'Канон / Canonical:\n  iface=eth0\n  ip=192.0.2.10\n  family=inet\n\n'

    local f
    for f in string json xml; do
        printf '%s\n' "--- ${f} ---"
        printf 'iface=eth0\nip=192.0.2.10\nfamily=inet\n' | format::emit "${f}"
        printf '\n'
    done

    printf '%s\n' '--- string (scalar) ---'
    printf 'ip=192.0.2.10\n' | format::emit string
    printf '%s\n' '--- xml (custom root) ---'
    BS_FORMAT_ROOT=interface format::emit xml <<< 'ip=192.0.2.10'
}

main "$@"
