#!/bin/sh
# backup.sh - POSIX-compliant backup with rotation
# Usage: backup.sh <source> <dest_dir> [retention]
set -eu

usage() {
  cat <<EOF
Usage: $0 <source> <dest_dir> [retention]

Backup a file or directory to dest_dir with retention count.
  source       File or directory to back up
  dest_dir     Destination directory for backups
  retention    Number of old backups to keep (default: 7)
EOF
  exit 0
}

for arg; do
  case "$arg" in
    --help|-h) usage ;;
  esac
done

[ $# -ge 2 ] || { echo "Error: source and dest_dir required" >&2; usage; }

source="$1"
dest_dir="$2"
retention="${3:-7}"

[ -e "$source" ] || { echo "Error: source not found: $source" >&2; exit 1; }
[ -d "$dest_dir" ] || { echo "Error: dest_dir not found: $dest_dir" >&2; exit 1; }
[ -w "$dest_dir" ] || { echo "Error: dest_dir not writable: $dest_dir" >&2; exit 1; }

case "$retention" in
  *[!0-9]*) echo "Error: retention must be a number" >&2; exit 1 ;;
esac

timestamp=$(date +%Y%m%d_%H%M%S)
backup_file="${dest_dir}/backup-${timestamp}.tar.gz"

tar -czf "$backup_file" "$source" 2>/dev/null || {
  echo "Error: backup failed" >&2
  rm -f "$backup_file"
  exit 1
}

printf '%s\n' "Created: $backup_file"

# Rotate old backups beyond retention count
archive_count=$(ls -1 "${dest_dir}/backup-"*.tar.gz 2>/dev/null | wc -l)
if [ "$archive_count" -gt "$retention" ]; then
  remove_count=$((archive_count - retention))
  ls -1t "${dest_dir}/backup-"*.tar.gz 2>/dev/null | tail -n "$remove_count" | while IFS= read -r old; do
    rm -f "$old"
    printf '%s\n' "Removed: $old"
  done
fi
