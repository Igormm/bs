#!/usr/bin/env bs
# shellcheck shell=bash
# @shell bash4,zsh — bounded worker pools with zero-based arrays
# examples/parallel_demo.sh — io::parallel in bash and zsh
# examples/parallel_demo.sh — io::parallel в bash и zsh
#
# Run / Запуск:
#   ./bs run examples/parallel_demo.sh
#   zsh examples/parallel_demo.sh

if [[ -z "${BS_INITIALIZED:-}" ]]; then
    source "$(cd "$(dirname "$0")/.." && pwd)/bootstrap/init.sh"
fi

load "lib/io/parallel"
strict::enable

demo_worker() {
    printf 'item=%s pid=%s\n' "$1" "$$"
    printf 'diagnostic=%s\n' "$1" >&2
}

results="$(mktemp -d)"
trap 'rm -rf "$results"' EXIT

io::parallel::map --jobs 3 --out-dir "$results" -- \
    demo_worker alpha beta gamma delta

printf 'results: %s\n' "$results"
for rc_file in "$results"/*.rc; do
    printf '%s: rc=%s\n' "${rc_file##*/}" "$(cat "$rc_file")"
done
