#!/bin/sh
# docker_test_cross.sh - Test scripts across Alpine, Debian, and Fedora
# Runs docker_test.sh with each image and aggregates results.
# Usage:
#   docker_test_cross.sh [--verbose] <script.sh>
#   docker_test_cross.sh [--verbose] <dir>
#   docker_test_cross.sh [--verbose] <dir> <entrypoint>
#
# Images are pinned for reproducibility: alpine:3.21, debian:12-slim, fedora:41

set -eu

script_dir=$(dirname "$0")
verbose_flag=""
[ "${1:-}" = "--verbose" ] && verbose_flag="--verbose" && shift

target="$1"
entrypoint="${2:-}"

images="alpine:3.21 debian:12-slim fedora:41"
total=0
passed=0
failed=0

for image in $images; do
  echo "=== Image: $image ==="
  set +e
  DOCKER_TEST_IMAGE="$image" sh "${script_dir}/docker_test.sh" $verbose_flag "$target" $entrypoint
  result=$?
  set -e
  total=$((total + 1))
  if [ "$result" -eq 0 ]; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
  fi
  echo ""
done

echo "=== Cross-Distro Summary ==="
echo "Total: $total  Passed: $passed  Failed: $failed"
if [ "$failed" -gt 0 ]; then
  echo "Result: SOME IMAGES FAILED"
  exit 1
fi
echo "Result: ALL IMAGES PASSED"
exit 0
