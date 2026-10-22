#!/bin/sh
# tempfile.sh - Safe temp file usage with trap cleanup
# Usage: tempfile.sh [--dir DIR]
set -eu

usage() {
  cat <<EOF
Usage: $0 [--dir DIR]

Demonstrates safe temp file creation with automatic cleanup.
  --dir DIR    Working directory (default: /tmp)
  --help       Show this help
EOF
  exit 0
}

work_dir="/tmp"

for arg; do
  case "$arg" in
    --help) usage ;;
  esac
done

while [ $# -gt 0 ]; do
  case "$1" in
    --dir) work_dir="$2"; shift 2 ;;
    *) echo "Error: unknown option: $1" >&2; exit 1 ;;
  esac
done

tmpfile=$(mktemp "${work_dir}/tempfile-XXXXXX") || {
  echo "Error: could not create temp file" >&2
  exit 1
}

trap 'rm -f "$tmpfile"' EXIT INT TERM

printf '%s\n' "Created temp file: $tmpfile"
printf '%s\n' "PID: $$" > "$tmpfile"
printf '%s\n' "Date: $(date)" >> "$tmpfile"
printf '%s\n' "Temp file contents:"
cat "$tmpfile"

printf '%s\n' "Temp file will be removed on script exit (trap EXIT)."
