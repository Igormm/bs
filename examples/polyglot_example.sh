#!/usr/bin/env bs
# shellcheck shell=bash
# examples/polyglot_example.sh — code in other languages inside a bs script
# examples/polyglot_example.sh — код на других языках внутри скрипта bs
#
# Usage / Использование: bs run examples/polyglot_example.sh
# Languages that are not installed are skipped / Не установленные языки пропускаются.

load "lib/polyglot/run"

main() {
    log::header "polyglot: tools / инструменты"
    polyglot::languages

    local answer=""
    if polyglot::run python --out answer -- 21 <<'PY'
import sys
print(int(sys.argv[1]) * 2)
PY
    then
        log::info "python: 21 * 2 = ${answer}"
    fi

    local -a words=()
    if polyglot::run js --lines words -- bs polyglot <<'JS'
for (const w of process.argv.slice(2)) console.log(w.toUpperCase());
JS
    then
        log::info "js: ${#words[@]} words: ${words[*]}"
    fi

    local -A cfg=()
    if polyglot::run c --map cfg --env NAME=bs <<'C'
#include <stdio.h>
#include <stdlib.h>
int main(void) { printf("name=%s\nlen=2\n", getenv("NAME")); return 0; }
C
    then
        log::info "c: name=${cfg[name]} len=${cfg[len]}"
    fi
}

if bs::is_main; then
    main "$@"
fi
