#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testpolyglotunit.sh — Unit tests for lib/polyglot (code in other languages inside a script)
# tests/unit/testpolyglotunit.sh — Модульные тесты lib/polyglot (код на других языках внутри скрипта)

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

load "lib/polyglot/run"

# Языки, которые есть на машине / languages present on this machine
have() { polyglot::__tool "$1" >/dev/null 2>&1; }

test_python() {
    testframework::section "Python: argv in, stdout out / аргументы туда, вывод обратно"
    local out="" rc=0
    polyglot::run python --out out -- 21 <<'EOF2'
import sys
print(int(sys.argv[1]) * 2)
EOF2
    testframework::assert_equal "42" "${out}" "argument in, result in a scalar"

    local -a lines=()
    polyglot::run python --lines lines -- a b c <<'EOF2'
import sys
for a in sys.argv[1:]:
    print(a.upper())
EOF2
    testframework::assert_equal "3" "${#lines[@]}" "lines: three elements"
    testframework::assert_equal "B" "${lines[1]}" "lines: second element"

    local -A cfg=()
    polyglot::run python --map cfg --env NAME=bs <<'EOF2'
import os
print("name=" + os.environ["NAME"])
print("path=a=b")
print("not a pair")
EOF2
    testframework::assert_equal "bs" "${cfg[name]}" "map: value from the environment"
    testframework::assert_equal "a=b" "${cfg[path]}" "map: only the first = splits"
    testframework::assert_equal "2" "${#cfg[@]}" "map: a line without = is skipped"

    polyglot::run python --out out --input "hello" <<'EOF2'
import sys
print(len(sys.stdin.read().strip()))
EOF2
    testframework::assert_equal "5" "${out}" "--input reaches the program's stdin"

    local got=""
    polyglot::run python --rc rc --out got <<'EOF2'
import sys
print("bye")
sys.exit(3)
EOF2
    testframework::assert_equal "3" "${rc}" "--rc holds the exit code"
    testframework::assert_equal "bye" "${got}" "stdout is kept when the program fails"

    rc=0
    polyglot::run python >/dev/null 2>&1 <<'EOF2' || rc=$?
import sys
sys.exit(4)
EOF2
    testframework::assert_equal "4" "${rc}" "without --rc the exit code is the return status"

    polyglot::run python --out out -- "x'; echo INJECTED; '" <<'EOF2'
import sys
print(sys.argv[1])
EOF2
    testframework::assert_equal "x'; echo INJECTED; '" "${out}" "an argument is data, never code"

    local lang="" out2=""
    polyglot::run python --out lang --rc out2 <<'EOF2'
print("x")
EOF2
    testframework::assert_equal "x" "${lang}" "a caller variable named like an internal one works"

    polyglot::run py --out out <<'EOF2'
print("alias")
EOF2
    testframework::assert_equal "alias" "${out}" "the alias py"

    rc=0
    polyglot::run python --timeout 1 >/dev/null 2>&1 <<'EOF2' || rc=$?
import time
time.sleep(5)
EOF2
    testframework::assert_equal "${LIB_ERROR_TIMEOUT}" "${rc}" "--timeout kills the program"
}

test_js() {
    testframework::section "JavaScript"
    local out=""
    polyglot::run js --out out -- 6 7 <<'EOF2'
const [a, b] = process.argv.slice(2).map(Number);
console.log(a * b);
EOF2
    testframework::assert_equal "42" "${out}" "node: argv in, result out"
}

test_compiled() {
    testframework::section "Compiled languages / Компилируемые языки"
    local out=""
    if have c; then
        local -A m=()
        polyglot::run c --map m --env NAME=bs <<'EOF2'
#include <stdio.h>
#include <stdlib.h>
int main(void) { printf("name=%s\nlen=2\n", getenv("NAME")); return 0; }
EOF2
        testframework::assert_equal "bs" "${m[name]}" "C: map from the environment"
        polyglot::run c --out out -- 3 4 <<'EOF2'
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv) { printf("%d\n", atoi(argv[1]) * atoi(argv[2])); return 0; }
EOF2
        testframework::assert_equal "12" "${out}" "C: argv"
    else
        echo "  SKIP: no C compiler"
    fi
    if have cpp; then
        polyglot::run cpp --out out -- 7 <<'EOF2'
#include <iostream>
#include <cstdlib>
int main(int, char **v) { int x = std::atoi(v[1]); std::cout << x * x << "\n"; }
EOF2
        testframework::assert_equal "49" "${out}" "C++: argv"
    else
        echo "  SKIP: no C++ compiler"
    fi
    if have go; then
        polyglot::run go --out out -- a b c <<'EOF2'
package main

import (
	"fmt"
	"os"
)

func main() { fmt.Println(len(os.Args) - 1) }
EOF2
        testframework::assert_equal "3" "${out}" "Go: argv"
    else
        echo "  SKIP: no Go"
    fi
    if have rust; then
        polyglot::run rust --out out --input "hello" <<'EOF2'
use std::io::Read;
fn main() { let mut s = String::new(); std::io::stdin().read_to_string(&mut s).unwrap(); println!("{}", s.trim().len()); }
EOF2
        testframework::assert_equal "5" "${out}" "Rust: stdin"
    else
        echo "  SKIP: no Rust"
    fi
}

test_cache() {
    testframework::section "Cache / Кэш"
    have c || { echo "  SKIP: no C compiler"; return 0; }
    local bin1 bin2 m1 m2
    local -a src=('#include <stdio.h>' 'int main(void) { puts("cached"); return 0; }')
    polyglot::run c --no-cache >/dev/null <<<"$(printf '%s\n' "${src[@]}")"
    bin1="$(find "${POLYGLOT_CACHE_DIR}/c" -maxdepth 1 -type f -perm -u+x | head -n 1)"
    m1="$(stat -c %Y "${bin1}")"
    sleep 1
    polyglot::run c >/dev/null <<<"$(printf '%s\n' "${src[@]}")"
    bin2="$(find "${POLYGLOT_CACHE_DIR}/c" -maxdepth 1 -type f -perm -u+x | head -n 1)"
    m2="$(stat -c %Y "${bin2}")"
    testframework::assert_equal "${m1}" "${m2}" "the cached binary is reused, not rebuilt"
    sleep 1
    polyglot::run c --no-cache >/dev/null <<<"$(printf '%s\n' "${src[@]}")"
    m2="$(stat -c %Y "${bin1}")"
    testframework::assert_true "${m2} -gt ${m1}" "--no-cache rebuilds"
}

test_errors() {
    testframework::section "Errors / Ошибки"
    local rc=0
    polyglot::run cobol >/dev/null 2>&1 <<<"x" || rc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_ARGS}" "${rc}" "unknown language"
    rc=0
    polyglot::run python --bogus >/dev/null 2>&1 <<<"x" || rc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_ARGS}" "${rc}" "unknown option"
    rc=0
    polyglot::run python --out '1bad' >/dev/null 2>&1 <<<"x" || rc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_ARGS}" "${rc}" "invalid variable name"
    rc=0
    polyglot::run python --env 'NOEQUALS' >/dev/null 2>&1 <<<"x" || rc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_ARGS}" "${rc}" "--env without ="
    rc=0
    polyglot::run python --timeout abc >/dev/null 2>&1 <<<"x" || rc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_ARGS}" "${rc}" "--timeout not a number"
    rc=0
    local plain=()
    polyglot::run python --map plain >/dev/null 2>&1 <<<"x" || rc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_ARGS}" "${rc}" "--map needs an associative array"
    rc=0
    polyglot::run python >/dev/null 2>&1 </dev/null || rc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_ARGS}" "${rc}" "empty source"
    rc=0
    POLYGLOT_PYTHON_TOOLS="no-such-python" polyglot::run python >/dev/null 2>&1 <<<"print(1)" || rc=$?
    testframework::assert_equal "${LIB_ERROR_DEPENDENCY_MISSING}" "${rc}" "no tool: dependency missing"
    if have c; then
        rc=0
        polyglot::run c >/dev/null 2>&1 <<<"this is not C" || rc=$?
        testframework::assert_equal "${LIB_ERROR_DEPENDENCY}" "${rc}" "a compile error is reported"
    fi
}

main() {
    print_header "Polyglot Unit Tests / Модульные тесты polyglot"

    testframework::init
    export POLYGLOT_CACHE_DIR
    POLYGLOT_CACHE_DIR="$(mktemp -d)/bs-polyglot-cache"

    testframework::section "Languages / Языки"
    local table
    table="$(polyglot::languages)"
    local listed=false
    [[ "${table}" == *rust* && "${table}" == *python* ]] && listed=true
    testframework::assert_equal "true" "${listed}" "polyglot::languages lists the languages"
    testframework::assert_equal "6" "$(printf '%s\n' "${table}" | wc -l)" "six languages"

    if have python; then test_python; else echo "  SKIP: no Python"; fi
    if have js; then test_js; else echo "  SKIP: no node"; fi
    test_compiled
    test_cache
    test_errors

    rm -rf "${POLYGLOT_CACHE_DIR%/*}"
    testframework::summary
}

main "$@"
