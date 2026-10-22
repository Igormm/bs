#!/bin/sh
# multisource.sh - Entrypoint that sources safelib.sh for utilities
set -eu

script_dir=$(dirname "$0")
. "${script_dir}/safelib.sh"

usage() {
  cat <<EOF
Usage: $0 <file> [output_dir]

Demonstrates sourcing safelib.sh and using its utilities.
  file         File to process
  output_dir   Output directory (default: .)
  --help       Show this help
EOF
  exit 0
}

for arg; do
  case "$arg" in
    --help) usage ;;
  esac
done

[ $# -ge 1 ] || die "Error: file argument required"

input_file="$1"
output_dir="${2:-.}"

require_cmd "wc"
require_cmd "cat"

[ -f "$input_file" ] || die "Error: file not found: $input_file"
[ -d "$output_dir" ] || die "Error: directory not found: $output_dir"

lines=$(wc -l < "$input_file")
size=$(wc -c < "$input_file")

printf '%s\n' "File: $input_file"
printf '%s\n' "Lines: $lines"
printf '%s\n' "Size: $(human_size "$size")"
printf '%s\n' "Output: $output_dir"
