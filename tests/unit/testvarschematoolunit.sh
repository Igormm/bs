#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testvarschematoolunit.sh — scripts/gen_var_schema.sh and scripts/check_var_contracts.sh
# tests/unit/testvarschematoolunit.sh — scripts/gen_var_schema.sh и scripts/check_var_contracts.sh
#
# The generator turns `# @var`/`# @type`/`# @ops`/… annotations into a POSIX manifest of
# `bs_var_declare` calls; the audit finds direct `$NAME` accesses. Both are dev tools.
# Генератор превращает аннотации `# @var`/`# @type`/`# @ops`/… в POSIX-манифест из вызовов
# `bs_var_declare`; аудит находит прямые обращения `$ИМЯ`. Оба — инструменты разработчика.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly GEN="${BS_PROJECT_ROOT}/scripts/gen_var_schema.sh"
readonly AUDIT="${BS_PROJECT_ROOT}/scripts/check_var_contracts.sh"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

T=""
FIX=""

eq() { testframework::assert_equal "$1" "$2" "$3" || true; }
has() {
    local needle="$1" haystack="$2" name="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        testframework::assert_true "true" "$name" || true
    else
        testframework::assert_true "false" "$name" || true
    fi
}

# Скрипты POSIX: разбор / The scripts are POSIX: they parse
test_parse() {
    testframework::assert_command "sh -n '${GEN}'" "gen_var_schema.sh parses" || true
    testframework::assert_command "sh -n '${AUDIT}'" "check_var_contracts.sh parses" || true
    testframework::assert_command "grep -q '^# @shell posix' '${GEN}' && grep -q '^# @shell posix' '${AUDIT}'" "both scripts are @shell posix" || true
}

test_generate() {
    local out spec
    spec=$'CACHE_TTL\ttype=int;ops=read,write;default=60;range=0..3600;unit=seconds'
    eq "${spec}" "$(sh "${GEN}" --list "${FIX}/ok.sh" 2>&1)" "gen --list prints name<TAB>spec"

    testframework::assert_command "sh '${GEN}' --out '${T}/var-schema.sh' '${FIX}/ok.sh'" "gen --out writes the manifest" || true
    has "bs_var_declare CACHE_TTL 'type=int;ops=read,write;default=60;range=0..3600;unit=seconds'" "$(cat "${T}/var-schema.sh")" "the manifest declares the variable"

    testframework::assert_command "sh '${GEN}' --check --out '${T}/var-schema.sh' '${FIX}/ok.sh'" "gen --check accepts an up-to-date manifest" || true
    printf 'bs_var_declare JUNK '\''x'\''\n' >> "${T}/var-schema.sh"
    testframework::assert_false "sh '${GEN}' --check --out '${T}/var-schema.sh' '${FIX}/ok.sh'" "gen --check fails on drift" || true
}

test_generate_rejects() {
    testframework::assert_false "sh '${GEN}' --list '${FIX}/bad-key.sh'" "an unknown annotation key is refused" || true
    testframework::assert_false "sh '${GEN}' --list '${FIX}/semicolon.sh'" "a ';' in an annotation value is refused" || true
    testframework::assert_false "sh '${GEN}' --list '${FIX}/bad-name.sh'" "a bad variable name is refused" || true
    testframework::assert_false "sh '${GEN}' --list '${FIX}/ok.sh' '${FIX}/dup.sh'" "a duplicate @var name is refused" || true
}

test_audit() {
    local out
    out="$(sh "${AUDIT}" --from-scan "${FIX}/ok.sh" 2>&1 || true)"
    has 'no direct accesses' "${out}" "a read of a read-allowed variable is not flagged"

    out="$(sh "${AUDIT}" --from-scan "${FIX}/writeonly.sh" 2>&1 || true)"
    has 'direct read of $TOKEN' "${out}" "a direct read of a write-only variable is flagged"

    out="$(sh "${AUDIT}" --from-scan "${FIX}/readonly.sh" 2>&1 || true)"
    has 'direct write to K' "${out}" "a direct write to a read-only variable is flagged"

    out="$(sh "${AUDIT}" --from-scan "${FIX}/clean.sh" 2>&1 || true)"
    has 'no direct accesses' "${out}" "audit --from-scan passes on clean input"
}

test_manifest_up_to_date() {
    testframework::assert_command "( cd '${BS_PROJECT_ROOT}' && sh scripts/gen_var_schema.sh --check )" "the committed core/var-schema.sh matches the annotations" || true
}

test_repo_audit_clean() {
    testframework::assert_command "( cd '${BS_PROJECT_ROOT}' && sh scripts/check_var_contracts.sh )" "no direct writes to the annotated core variables" || true
}

main() {
    T="$(mktemp -d)"
    FIX="${T}/fixture"
    mkdir -p "${FIX}"

    cat > "${FIX}/ok.sh" <<'EOF'
# @var CACHE_TTL
# @type int
# @ops read,write
# @default 60
# @range 0..3600
# @unit seconds
CACHE_TTL=60
echo "$CACHE_TTL"
EOF

    cat > "${FIX}/clean.sh" <<'EOF'
# @var CACHE_TTL
# @type int
# @ops read,write
# @default 60
CACHE_TTL=60
bs_var_get CACHE_TTL
EOF

    cat > "${FIX}/bad-key.sh" <<'EOF'
# @var A
# @bogus 1
A=1
EOF

    cat > "${FIX}/semicolon.sh" <<'EOF'
# @var A
# @description a;b
A=1
EOF

    cat > "${FIX}/bad-name.sh" <<'EOF'
# @var 1bad
# @type int
1bad=1
EOF

    cat > "${FIX}/dup.sh" <<'EOF'
# @var CACHE_TTL
# @type uint
CACHE_TTL=60
EOF

    cat > "${FIX}/writeonly.sh" <<'EOF'
# @var TOKEN
# @type string
# @ops write
TOKEN=
echo "$TOKEN"
EOF

    cat > "${FIX}/readonly.sh" <<'EOF'
# @var K
# @type int
# @ops read
K=1
K=2
EOF

    testframework::section "Parse / Разбор"; test_parse
    testframework::section "Generate / Генерация"; test_generate
    testframework::section "Reject bad input / Отказ на плохом вводе"; test_generate_rejects
    testframework::section "Audit / Аудит"; test_audit
    testframework::section "Manifest / Манифест"; test_manifest_up_to_date
    testframework::section "Repo audit / Аудит репозитория"; test_repo_audit_clean
    rm -rf "${T:?}"
    testframework::summary
}

main "$@"
