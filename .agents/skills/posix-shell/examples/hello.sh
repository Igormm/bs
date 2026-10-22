#!/bin/sh
# hello.sh - Example POSIX-compliant script
set -eu

usage() {
  printf '%s\n' "Usage: $0 [name]"
  exit 1
}

name="${1:-}"
[ -z "$name" ] && usage

printf '%s\n' "Hello, $name!"
