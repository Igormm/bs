#!/bin/sh
# logrotate.sh - Signal-safe log rotation with dry-run
# Usage: logrotate.sh <logfile> [max_size_kb]
set -eu

usage() {
  cat <<EOF
Usage: $0 <logfile> [max_size_kb]

Rotate a log file when it exceeds max_size_kb.
  logfile       Path to the log file
  max_size_kb   Max size before rotation (default: 1024)
  --dry-run     Show what would be done without doing it
  --help        Show this help
EOF
  exit 0
}

dry_run=0

for arg; do
  case "$arg" in
    --help) usage ;;
    --dry-run) dry_run=1 ;;
  esac
done

[ $# -ge 1 ] || { echo "Error: logfile required" >&2; usage; }
logfile="$1"
max_size_kb="${2:-1024}"

case "$max_size_kb" in
  *[!0-9]*) echo "Error: max_size_kb must be a number" >&2; exit 1 ;;
esac

[ -f "$logfile" ] || { echo "OK: logfile does not exist yet, nothing to rotate"; exit 0; }

size_kb=$(( $(wc -c < "$logfile") / 1024 ))
if [ "$size_kb" -le "$max_size_kb" ]; then
  printf '%s\n' "OK: logfile is ${size_kb}KB (limit: ${max_size_kb}KB), no rotation needed"
  exit 0
fi

timestamp=$(date +%Y%m%d_%H%M%S)
rotated="${logfile}.${timestamp}"

if [ "$dry_run" -eq 1 ]; then
  printf '%s\n' "[DRY RUN] Would rotate: $logfile -> $rotated"
  exit 0
fi

cp "$logfile" "$rotated" && : > "$logfile" && printf '%s\n' "Rotated: $rotated (was ${size_kb}KB)" || {
  echo "Error: rotation failed" >&2
  exit 1
}
