#!/bin/sh
# test_hello.sh - Tests for hello.sh
set -eu

script_dir=$(dirname "$0")
hello_sh="${script_dir}/hello.sh"

[ -f "$hello_sh" ] || { echo "FAIL: hello.sh not found"; exit 1; }

result=$("$hello_sh" World 2>&1)
[ "$result" = "Hello, World!" ] && echo "PASS: hello World" || echo "FAIL: expected 'Hello, World!' got '$result'"

result=$("$hello_sh" 2>&1) && {
  echo "FAIL: expected non-zero exit"
  exit 1
} || echo "PASS: hello (no args) exits with non-zero"

echo "All tests passed!"
