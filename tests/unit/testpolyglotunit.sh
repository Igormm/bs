#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testpolyglotunit.sh — Unit tests for lib/polyglot (code in other languages inside a script)
# tests/unit/testpolyglotunit.sh — Модульные тесты lib/polyglot (код на других языках внутри скрипта)

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
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

test_dependencies() {
    testframework::section "Dependencies: the manager is checked BEFORE anything runs / Менеджер проверяется ДО запуска"
    local work marker rc
    work="$(mktemp -d)"
    marker="${work}/MARKER"

    # Python есть, pip нет / Python is there, pip is not
    if have python; then
        cat > "${work}/fakepy" <<'EOF2'
#!/bin/sh
case "$*" in
  "-m pip --version") exit 1 ;;
esac
exec python3 "$@"
EOF2
        chmod +x "${work}/fakepy"
        rc=0
        POLYGLOT_PYTHON_TOOLS="${work}/fakepy" polyglot::run python --dep requests >/dev/null 2>&1 <<EOF2 || rc=$?
open("${marker}", "w").write("ran")
EOF2
        testframework::assert_equal "${LIB_ERROR_DEPENDENCY_MISSING}" "${rc}" "no pip: dependency missing"
        testframework::assert_true "! -e ${marker}" "no pip: the code was not executed"
    fi

    # npm / cargo / pkg-config / go отсутствуют / absent
    rc=0
    POLYGLOT_NPM_TOOLS="no-such-npm" polyglot::run js --dep left-pad >/dev/null 2>&1 <<EOF2 || rc=$?
require('fs').writeFileSync("${marker}", 'ran');
EOF2
    testframework::assert_equal "${LIB_ERROR_DEPENDENCY_MISSING}" "${rc}" "no npm: dependency missing"
    testframework::assert_true "! -e ${marker}" "no npm: the code was not executed"

    rc=0
    POLYGLOT_CARGO_TOOLS="no-such-cargo" polyglot::run rust --dep serde >/dev/null 2>&1 <<<"fn main() {}" || rc=$?
    testframework::assert_equal "${LIB_ERROR_DEPENDENCY_MISSING}" "${rc}" "no cargo: dependency missing"

    rc=0
    POLYGLOT_PKGCONFIG_TOOLS="no-such-pkgconfig" polyglot::run c --dep zlib >/dev/null 2>&1 <<<"int main(void) { return 0; }" || rc=$?
    testframework::assert_equal "${LIB_ERROR_DEPENDENCY_MISSING}" "${rc}" "no pkg-config: dependency missing"

    cat > "${work}/fakego" <<'EOF2'
#!/bin/sh
case "$1" in
  env) exit 1 ;;
esac
exit 1
EOF2
    chmod +x "${work}/fakego"
    rc=0
    POLYGLOT_GO_TOOLS="${work}/fakego" polyglot::run go --dep example.com/m@v1.0.0 >/dev/null 2>&1 <<<"package main" || rc=$?
    testframework::assert_equal "${LIB_ERROR_DEPENDENCY_MISSING}" "${rc}" "go without modules support: dependency missing"

    # Безопасность записи зависимости / dependency spec safety
    local spec
    for spec in "-e evil" "a b" ";rm" '$(x)' ""; do
        rc=0
        polyglot::run python --dep "${spec}" >/dev/null 2>&1 <<<"print(1)" || rc=$?
        testframework::assert_equal "${LIB_ERROR_INVALID_ARGS}" "${rc}" "unsafe --dep '${spec}' is refused"
    done

    # Сбой установки: понятная ошибка, код не запускается / install failure: clear error, no run
    cat > "${work}/failgo" <<'EOF2'
#!/bin/sh
case "$1" in
  env) exit 0 ;;
  get) echo "boom"; exit 1 ;;
esac
exit 1
EOF2
    chmod +x "${work}/failgo"
    rc=0
    POLYGLOT_GO_TOOLS="${work}/failgo" polyglot::run go --dep example.com/m@v1.0.0 >/dev/null 2>&1 <<<"package main" || rc=$?
    testframework::assert_equal "${LIB_ERROR_DEPENDENCY}" "${rc}" "go get fails: dependency error"

    # Положительные пути без сети / positive paths without a network
    local out=""
    if have python && python3 -m pip --version >/dev/null 2>&1 && python3 -m venv --help >/dev/null 2>&1; then
        python3 - "${work}" <<'EOF2'
import sys, zipfile
w = sys.argv[1]
with zipfile.ZipFile(w + "/bsdemo-1.0-py3-none-any.whl", "w") as z:
    z.writestr("bsdemo.py", "VALUE = 41\n")
    z.writestr("bsdemo-1.0.dist-info/METADATA", "Metadata-Version: 2.1\nName: bsdemo\nVersion: 1.0\n")
    z.writestr("bsdemo-1.0.dist-info/WHEEL", "Wheel-Version: 1.0\nGenerator: bs\nRoot-Is-Purelib: true\nTag: py3-none-any\n")
    z.writestr("bsdemo-1.0.dist-info/RECORD", "")
EOF2
        polyglot::run python --dep "${work}/bsdemo-1.0-py3-none-any.whl" --out out <<'EOF2'
import bsdemo
print(bsdemo.VALUE + 1)
EOF2
        testframework::assert_equal "42" "${out}" "pip: a local wheel is installed into the cached venv and importable"
    else
        echo "  SKIP: no pip/venv"
    fi
    if have js && utils::has npm; then
        mkdir -p "${work}/bsdemo-js"
        printf '{"name":"bsdemo-js","version":"1.0.0","main":"index.js"}\n' > "${work}/bsdemo-js/package.json"
        printf 'module.exports = { value: 41 };\n' > "${work}/bsdemo-js/index.js"
        polyglot::run js --dep "${work}/bsdemo-js" --out out <<'EOF2'
console.log(require('bsdemo-js').value + 1);
EOF2
        testframework::assert_equal "42" "${out}" "npm: a local package is installed and require()-able"
    else
        echo "  SKIP: no npm"
    fi
    if have c && utils::has pkg-config; then
        printf 'Name: bsdemo\nDescription: demo\nVersion: 1.0\nCflags: -DBSDEMO=41\nLibs:\n' > "${work}/bsdemo.pc"
        PKG_CONFIG_PATH="${work}" polyglot::run c --dep bsdemo --out out <<'EOF2'
#include <stdio.h>
int main(void) { printf("%d\n", BSDEMO + 1); return 0; }
EOF2
        testframework::assert_equal "42" "${out}" "pkg-config: the library flags reach the compiler"
        rc=0
        PKG_CONFIG_PATH="${work}" polyglot::run c --dep no-such-lib >/dev/null 2>&1 <<<"int main(void) { return 0; }" || rc=$?
        testframework::assert_equal "${LIB_ERROR_DEPENDENCY_MISSING}" "${rc}" "pkg-config: a missing library is reported"
    else
        echo "  SKIP: no pkg-config"
    fi

    local report
    report="$(polyglot::doctor)"
    testframework::assert_true "\"${report//$'\n'/;}\" == *pip*" "polyglot::doctor reports pip"
    rm -rf "${work}"
}

test_network_dependencies() {
    testframework::section "Network: real Go and cargo dependencies (POLYGLOT_TEST_NETWORK=1) / Сеть: настоящие зависимости Go и cargo"
    if [[ "${POLYGLOT_TEST_NETWORK:-0}" != "1" ]]; then
        echo "  SKIP: set POLYGLOT_TEST_NETWORK=1 to fetch real packages"
        return 0
    fi
    local out=""
    if have go; then
        polyglot::run go --dep github.com/google/uuid@v1.6.0 --out out <<'EOF2'
package main

import (
	"fmt"

	"github.com/google/uuid"
)

func main() { fmt.Println(len(uuid.New().String())) }
EOF2
        testframework::assert_equal "36" "${out}" "Go: a real module is fetched and linked"
    fi
    if have rust && utils::has cargo; then
        polyglot::run rust --dep itoa@1 --out out <<'EOF2'
fn main() { let mut b = itoa::Buffer::new(); println!("{}", b.format(12345u32)); }
EOF2
        testframework::assert_equal "12345" "${out}" "Rust: a real crate is fetched and linked"
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
    test_dependencies
    test_network_dependencies

    rm -rf "${POLYGLOT_CACHE_DIR%/*}"
    testframework::summary
}

main "$@"
