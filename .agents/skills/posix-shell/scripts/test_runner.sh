#!/bin/sh
# test_runner.sh - Test shell scripts across locally available shells
# Usage:
#   test_runner.sh <script.sh>
#   test_runner.sh <dir>
#   test_runner.sh <dir> <entrypoint.sh>

set -eu

if [ $# -eq 0 ]; then
  echo "Usage: $0 <script.sh> | $0 <dir> [entrypoint.sh]"
  exit 1
fi

target="$1"
entrypoint="${2:-}"

found_shell=0

run_shell() {
  sh_name="$1"
  sh_file="$2"
  if command -v "$sh_name" >/dev/null 2>&1; then
    found_shell=$((found_shell + 1))
    if "$sh_name" "$sh_file"; then
      echo "$sh_name: PASS"
    else
      echo "$sh_name: FAIL ($?)"
    fi
  else
    echo "$sh_name: SKIP (not found)"
  fi
}

if [ -n "$entrypoint" ]; then
  cd "$target"
  for sh in dash bash zsh ksh mksh; do
    run_shell "$sh" "$entrypoint"
  done
elif [ -f "$target" ]; then
  cd "$(dirname "$target")"
  for sh in dash bash zsh ksh mksh; do
    run_shell "$sh" "./$(basename "$target")"
  done
else
  cd "$target"
  for f in *.sh; do
    [ -f "$f" ] || continue
    echo "=== Testing: $f ==="
    for sh in dash bash zsh ksh mksh; do
      run_shell "$sh" "$f"
    done
  done
fi

if [ "$found_shell" -eq 0 ]; then
  echo "WARNING: No test shells found (dash/bash/zsh/ksh/mksh)." >&2
  echo "Install shells or use docker_test.sh for container-based testing." >&2
  exit 1
fi
