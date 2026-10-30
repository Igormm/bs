#!/usr/bin/env bash
# shellcheck shell=bash
# .agents/skills/bs-version-bump/scripts/version.sh — bump or check the BS framework version
# Usage: version.sh check | version.sh bump X.Y.Z [--codename NAME]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
VERSION_FILE="${ROOT}/core/version.sh"
CHANGELOG="${ROOT}/CHANGELOG.md"
TEST_FILE="${ROOT}/tests/unit/testbsnobashunit.sh"

usage() {
    cat <<'EOF'
Usage / Использование:
  version.sh check
  version.sh bump X.Y.Z [--codename NAME]

check   Verify the single source, runtime, CHANGELOG, en/ru docs and the
        no-bash test. Exit 1 on any drift.
bump    Change BS_VERSION (and optionally BS_CODENAME) in core/version.sh.
        The other places are reported by the following `check`.
EOF
}

die() {
    printf 'bs-version: %s\n' "$*" >&2
    exit 1
}

current_version() {
    sed -n 's/^[[:space:]]*export[[:space:]]\{1,\}BS_VERSION="\([^"]*\)".*/\1/p' "${VERSION_FILE}" | head -n 1
}

current_codename() {
    sed -n 's/^: "${BS_CODENAME:=\([^}]*\)}".*/\1/p' "${VERSION_FILE}" | head -n 1
}

FAILS=0

ok() {
    printf 'ok     %s\n' "$1"
}

fail() {
    printf 'DRIFT  %s\n' "$1"
    FAILS=$((FAILS + 1))
}

expect_eq() {
    local label="$1" want="$2" got="$3"
    if [ "${want}" = "${got}" ]; then
        ok "${label}"
    else
        fail "${label}: expected '${want}', got '${got}'"
    fi
}

expect_fixed() {
    local label="$1" needle="$2" file="$3"
    if grep -Fq -- "${needle}" "${file}"; then
        ok "${label}"
    else
        fail "${label}: '${needle}' not found in ${file#"${ROOT}"/}"
    fi
}

runtime_version() {
    if ! command -v bash >/dev/null 2>&1; then
        return 1
    fi
    env -u BS_VERSION -u BS_INITIALIZED -u BS_ROOT bash "${ROOT}/bs" version 2>/dev/null
}

check() {
    local version codename top sources runtime full

    [ -f "${VERSION_FILE}" ] || die "missing ${VERSION_FILE}"
    version="$(current_version)"
    codename="$(current_codename)"
    [ -n "${version}" ] || die "cannot read BS_VERSION from ${VERSION_FILE}"
    printf 'version: %s  codename: %s\n\n' "${version}" "${codename:-<none>}"

    local count
    count="$(grep -c '^[[:space:]]*export[[:space:]]\{1,\}BS_VERSION="' "${VERSION_FILE}" || true)"
    expect_eq "core/version.sh has one BS_VERSION" "1" "${count}"

    if git -C "${ROOT}" rev-parse --git-dir >/dev/null 2>&1; then
        mapfile -t sources < <(git -C "${ROOT}" grep -l -E 'BS_VERSION="[0-9]' -- . \
            ':(exclude)CHANGELOG.md' ':(exclude)tests' 2>/dev/null || true)
    else
        mapfile -t sources < <(grep -rIl --exclude-dir=.git --exclude-dir=.claude --exclude-dir=.agents \
            --exclude-dir=tests --exclude-dir=.art --exclude=CHANGELOG.md 'BS_VERSION="[0-9]' "${ROOT}" \
            2>/dev/null | sed "s#^${ROOT}/##" || true)
    fi
    if [ "${#sources[@]}" -eq 1 ] && [ "${sources[0]}" = "core/version.sh" ]; then
        ok "BS_VERSION is written only in core/version.sh"
    else
        fail "BS_VERSION is written outside core/version.sh: ${sources[*]:-none}"
    fi

    runtime="$(runtime_version || true)"
    expect_eq "runtime bs version" "BS Framework version: ${version}" "${runtime}"

    full="$(env -u BS_VERSION -u BS_INITIALIZED -u BS_ROOT bash "${ROOT}/bs" version --full 2>/dev/null || true)"
    if [ -n "${codename}" ]; then
        if printf '%s\n' "${full}" | grep -Fq -- "codename:  ${codename}"; then
            ok "runtime codename"
        else
            fail "runtime codename: 'codename:  ${codename}' not found"
        fi
    fi

    top="$(grep -m1 '^## \[' "${CHANGELOG}" || true)"
    if printf '%s' "${top}" | grep -Fq -- "## [${version}]"; then
        ok "CHANGELOG top release is ${version}"
    else
        fail "CHANGELOG top release: expected '## [${version}]', got '${top}'"
    fi
    if [ -n "${codename}" ]; then
        if printf '%s' "${top}" | grep -Fq -- "\"${codename}\""; then
            ok "CHANGELOG code name"
        else
            fail "CHANGELOG top release does not carry \"${codename}\""
        fi
    fi

    expect_fixed "en architecture" "(currently \`${version}\`)" \
        "${ROOT}/documentation/en/02-core-concepts/architecture.md"
    expect_fixed "ru architecture" "(сейчас \`${version}\`)" \
        "${ROOT}/documentation/ru/02-core-concepts/architecture.md"
    expect_fixed "en core-api" "(e.g. \`${version}\`)" \
        "${ROOT}/documentation/en/04-api-reference/core-api.md"
    expect_fixed "ru core-api" "(например, \`${version}\`)" \
        "${ROOT}/documentation/ru/04-api-reference/core-api.md"

    expect_fixed "no-bash test version" "version=BS Framework version: ${version} " "${TEST_FILE}"
    expect_fixed "no-bash test help" "help=BS Framework ${version} " "${TEST_FILE}"

    if [ -n "${codename}" ]; then
        expect_fixed "mtest codename (sh)" "\"${codename}\"" "${ROOT}/mtest/t_const_version.sh"
        expect_fixed "mtest codename (nu)" "\"${codename}\"" "${ROOT}/mtest/t_nu.nu"
    fi

    printf '\n'
    if [ "${FAILS}" -ne 0 ]; then
        printf '%s drift(s) found\n' "${FAILS}" >&2
        exit 1
    fi
    printf 'version is consistent\n'
}

bump() {
    local new="$1" codename=""
    shift
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --codename)
                [ "$#" -ge 2 ] || die "--codename needs a value"
                codename="$2"
                shift 2
                ;;
            --codename=*)
                codename="${1#--codename=}"
                shift
                ;;
            *)
                die "unknown option: $1"
                ;;
        esac
    done

    if ! printf '%s' "${new}" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$'; then
        die "not a SemVer version: ${new}"
    fi
    if [ -n "${codename}" ] && ! printf '%s' "${codename}" | grep -Eq '^[A-Za-z0-9._-]+$'; then
        die "code name may use only letters, digits, dot, underscore and dash: ${codename}"
    fi

    local old
    old="$(current_version)"
    [ "${new}" != "${old}" ] || die "already at ${new}"

    sed -i "s/^\([[:space:]]*export[[:space:]]\{1,\}BS_VERSION=\)\"[^\"]*\"/\1\"${new}\"/" "${VERSION_FILE}"
    if [ -n "${codename}" ]; then
        sed -i "s/^\(: \"\${BS_CODENAME:=\)[^}]*}/\1${codename}}/" "${VERSION_FILE}"
        printf 'bumped %s -> %s "%s" in core/version.sh\n' "${old}" "${new}" "${codename}"
    else
        printf 'bumped %s -> %s in core/version.sh\n' "${old}" "${new}"
    fi
    printf 'next: CHANGELOG heading, en/ru docs, tests/unit/testbsnobashunit.sh, mtest/ codename\n'
    printf 'then: %s check\n' "$0"
}

main() {
    case "${1:-}" in
        check)
            shift
            [ "$#" -eq 0 ] || die "check takes no arguments"
            check
            ;;
        bump)
            shift
            [ "$#" -ge 1 ] || die "bump needs X.Y.Z"
            bump "$@"
            ;;
        -h|--help|help|"")
            usage
            ;;
        *)
            usage >&2
            exit 2
            ;;
    esac
}

main "$@"
