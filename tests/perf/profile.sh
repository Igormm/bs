#!/usr/bin/env bs
# shellcheck shell=bash
# tests/perf/profile.sh — where the time goes in a BS command / куда уходит время в команде BS
#
# For one command it prints wall time, `strace -f -c` syscall totals (fork/exec cost)
# and the largest gaps in a timestamped bash xtrace (which shell line is slow).
# Для одной команды печатает wall time, сводку syscall'ов `strace -f -c` (цена fork/exec)
# и самые большие паузы в xtrace bash с таймстампами (какая строка тормозит).
#
# Usage / Использование:
#   bash tests/perf/profile.sh
#   bash tests/perf/profile.sh list
#   bash tests/perf/profile.sh doctor
#   bash tests/perf/profile.sh --all --top 20
#   bash tests/perf/profile.sh --no-strace --no-xtrace run examples/greet.sh hello --name Bob
#
# `strace` and `bash 5` are optional: a missing tool skips its section honestly.
# `strace` и `bash 5` необязательны: без инструмента его секция честно пропускается.
#
# Exit codes / Коды выхода:
#   0 — the profile completed / профиль выполнен
#   2 — bad arguments / неверные аргументы

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
readonly PROJECT_ROOT
readonly BS_BIN="${PROJECT_ROOT}/bs"
cd -- "${PROJECT_ROOT}"

usage() {
    cat <<'USAGE'
Usage: bash tests/perf/profile.sh [options] [bs command ...]

Options / Опции:
  --all             profile version, env, list, doctor and run greet / профиль пяти команд
  --top N           show N largest xtrace gaps / показать N самых больших пауз (default: 15)
  --no-strace       skip strace / без strace
  --no-xtrace       skip the bash xtrace / без xtrace
  -h, --help        show this help / показать справку

Without a command, `version` is profiled. `bs run` is traced in the outer
process only: the script itself runs in the child bash.
Без команды профилируется `version`. У `bs run` трассируется только внешний
процесс: сам скрипт работает в дочернем bash.
USAGE
}

top=15
do_strace=1
do_xtrace=1
profile_all=0
cmd=()

while (( $# > 0 )); do
    case "$1" in
        --all)
            profile_all=1
            shift
            ;;
        --top)
            [[ $# -ge 2 ]] || { usage >&2; exit 2; }
            top="$2"
            shift 2
            ;;
        --top=*)
            top="${1#*=}"
            shift
            ;;
        --no-strace)
            do_strace=0
            shift
            ;;
        --no-xtrace)
            do_xtrace=0
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            cmd=("$@")
            break
            ;;
        -*)
            printf 'profile: unknown option: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
        *)
            cmd=("$@")
            break
            ;;
    esac
done

[[ "${top}" =~ ^[1-9][0-9]*$ ]] || { printf 'profile: --top must be a positive integer\n' >&2; exit 2; }
(( profile_all == 0 )) || (( ${#cmd[@]} == 0 )) || {
    printf 'profile: --all and an explicit command are mutually exclusive\n' >&2
    exit 2
}

now_us() {
    local raw
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        raw="${EPOCHREALTIME//[.,]/}"
        printf '%s' "$((10#${raw}))"
        return 0
    fi
    raw="$(date +%s%N 2>/dev/null || true)"
    if [[ "${raw}" =~ ^[0-9]+$ ]]; then
        printf '%s' "$((raw / 1000))"
        return 0
    fi
    printf 'profile: bash 5 EPOCHREALTIME or GNU date +%%s%%N is required\n' >&2
    return 1
}

show_strace() {
    local -a args=("$@")
    local trace err
    trace="$(mktemp)"
    err="$(mktemp)"
    if strace -f -c -o "${trace}" "${BS_BIN}" "${args[@]}" >/dev/null 2>"${err}"; then
        printf '  strace -f -c (top):\n'
        sed -n '1,25p' "${trace}" | sed 's/^/    /'
    else
        printf '  strace failed: %s\n' "$(head -n 1 "${err}")"
    fi
    rm -f -- "${trace}" "${err}"
}

show_xtrace() {
    local -a args=("$@")
    local trace
    trace="$(mktemp)"
    if LC_ALL=C PS4='+${EPOCHREALTIME} ' bash -x "${BS_BIN}" "${args[@]}" \
        >/dev/null 2>"${trace}"; then
        printf '  xtrace gaps (seconds, top %d):\n' "${top}"
        awk '
            /^[+]+[0-9]+\.[0-9]+ / {
                line = $0
                sub(/^[+]+/, "", line)
                ts = line
                sub(/ .*/, "", ts)
                sub(/^[0-9]+\.[0-9]+ /, "", line)
                if (prev_ts != "") {
                    d = ts - prev_ts
                    if (d < 0) d = 0
                    printf "%.6f\t%s\n", d, prev_cmd
                }
                prev_ts = ts
                prev_cmd = line
            }
            END {
                if (prev_ts != "") printf "%.6f\t%s\n", 0, prev_cmd
            }
        ' "${trace}" | sort -nr | head -n "${top}" | sed 's/^/    /' || true
    else
        printf '  xtrace failed / xtrace не удался\n'
    fi
    rm -f -- "${trace}"
}

profile_one() {
    local label="$1"
    shift
    local -a args=("$@")
    local start end status=0

    printf '\n=== %s ===\n' "${label}"
    start="$(now_us)"
    if "${BS_BIN}" "${args[@]}" >/dev/null 2>&1; then
        status=0
    else
        status=$?
    fi
    end="$(now_us)"
    awk -v us="$((end - start))" 'BEGIN { printf "  wall: %.1f ms\n", us / 1000 }'
    (( status == 0 )) || printf '  exit status: %d\n' "${status}"

    if (( do_strace )); then
        if command -v strace >/dev/null 2>&1; then
            show_strace "${args[@]}"
        else
            printf '  strace not installed / strace не установлен\n'
        fi
    fi

    if (( do_xtrace )); then
        if command -v bash >/dev/null 2>&1 && [[ -n "${EPOCHREALTIME:-}" ]]; then
            show_xtrace "${args[@]}"
        else
            printf '  xtrace needs bash 5 with EPOCHREALTIME / xtrace нужен bash 5 с EPOCHREALTIME\n'
        fi
    fi
}

if (( profile_all )); then
    profile_one "bs version" version
    profile_one "bs env" env
    profile_one "bs list" list
    profile_one "bs doctor" doctor
    profile_one "bs run greet" run examples/greet.sh hello --name Bob
else
    if (( ${#cmd[@]} == 0 )); then
        cmd=(version)
    fi
    profile_one "bs ${cmd[*]}" "${cmd[@]}"
fi
