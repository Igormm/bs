#!/usr/bin/env bs
# shellcheck shell=bash
# tests/perf/bench.sh — startup and command benchmarks for BS / бенчмарки запуска и команд BS
#
# Measures the cold-start commands that matter most: version, env, list, doctor and
# a real `bs run`. Uses hyperfine when installed and falls back to a bash timer.
# Измеряет ключевые команды запуска: version, env, list, doctor и реальный `bs run`.
# Использует hyperfine, если он установлен, иначе — таймер на bash.
#
# Usage / Использование:
#   bash tests/perf/bench.sh
#   bash tests/perf/bench.sh --runs 10 --warmup 3
#   bash tests/perf/bench.sh --json /tmp/bs-bench.json
#   BS_PERF_SHELL=dash bash tests/perf/bench.sh
#
# Exit codes / Коды выхода:
#   0 — the benchmark completed / бенчмарк выполнен
#   2 — bad arguments or a missing timer / неверные аргументы или нет таймера

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
readonly PROJECT_ROOT
readonly BS_BIN="${PROJECT_ROOT}/bs"
cd -- "${PROJECT_ROOT}"

usage() {
    cat <<'USAGE'
Usage: bash tests/perf/bench.sh [options]

Options / Опции:
  --runs N          measured runs per command / замеров на команду (default: 5)
  --warmup N        warmup runs per command / прогревочных запусков (default: 2)
  --json FILE       export hyperfine results to FILE / экспорт результатов hyperfine
  --shell PATH      run bs with this shell (BS_PERF_SHELL) / запускать bs этой оболочкой
  --no-hyperfine    force the bash timer / принудительно таймер на bash
  -h, --help        show this help / показать справку

The harness is a development tool: it is not part of tests/runalltests.sh.
harness — инструмент разработчика, а не часть tests/runalltests.sh.
USAGE
}

runs=5
warmup=2
json_file=""
shell_bin="${BS_PERF_SHELL:-}"
use_hyperfine=1

while (( $# > 0 )); do
    case "$1" in
        --runs)
            [[ $# -ge 2 ]] || { usage >&2; exit 2; }
            runs="$2"
            shift 2
            ;;
        --runs=*)
            runs="${1#*=}"
            shift
            ;;
        --warmup)
            [[ $# -ge 2 ]] || { usage >&2; exit 2; }
            warmup="$2"
            shift 2
            ;;
        --warmup=*)
            warmup="${1#*=}"
            shift
            ;;
        --json)
            [[ $# -ge 2 ]] || { usage >&2; exit 2; }
            json_file="$2"
            shift 2
            ;;
        --json=*)
            json_file="${1#*=}"
            shift
            ;;
        --shell)
            [[ $# -ge 2 ]] || { usage >&2; exit 2; }
            shell_bin="$2"
            shift 2
            ;;
        --shell=*)
            shell_bin="${1#*=}"
            shift
            ;;
        --no-hyperfine)
            use_hyperfine=0
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'bench: unknown option: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

[[ "${runs}" =~ ^[1-9][0-9]*$ ]] || { printf 'bench: --runs must be a positive integer\n' >&2; exit 2; }
[[ "${warmup}" =~ ^[0-9]+$ ]] || { printf 'bench: --warmup must be a non-negative integer\n' >&2; exit 2; }

if [[ -n "${shell_bin}" ]] && ! command -v "${shell_bin}" >/dev/null 2>&1; then
    printf 'bench: shell not found: %s\n' "${shell_bin}" >&2
    exit 2
fi

entry_prefix() {
    if [[ -n "${shell_bin}" ]]; then
        printf '%q %q' "${shell_bin}" "${BS_BIN}"
    else
        printf '%q' "${BS_BIN}"
    fi
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
    printf 'bench: bash 5 EPOCHREALTIME or GNU date +%%s%%N is required\n' >&2
    return 1
}

prefix="$(entry_prefix)"
readonly prefix
readonly -a labels=(
    "bs version"
    "bs env"
    "bs list"
    "bs doctor"
    "bs run greet"
)
readonly -a commands=(
    "${prefix} version >/dev/null 2>&1"
    "${prefix} env >/dev/null 2>&1"
    "${prefix} list >/dev/null 2>&1"
    "${prefix} doctor >/dev/null 2>&1"
    "${prefix} run examples/greet.sh hello --name Bob >/dev/null 2>&1"
)

printf 'BS benchmark / Бенчмарк BS\n'
printf 'Entry / Точка входа: %s\n' "${prefix}"
printf 'Runs / Замеров: %d, warmup / прогрев: %d\n\n' "${runs}" "${warmup}"

if (( use_hyperfine )) && command -v hyperfine >/dev/null 2>&1; then
    printf 'Timer / Таймер: hyperfine\n\n'
    declare -a hf_args=(--warmup "${warmup}" --runs "${runs}")
    if [[ -n "${json_file}" ]]; then
        mkdir -p -- "$(dirname -- "${json_file}")"
        hf_args+=(--export-json "${json_file}")
    fi
    for i in "${!commands[@]}"; do
        hf_args+=(-n "${labels[$i]}" "${commands[$i]}")
    done
    hyperfine "${hf_args[@]}"
else
    printf 'Timer / Таймер: bash fallback (install hyperfine for better numbers / установите hyperfine)\n'
    [[ -z "${json_file}" ]] || printf 'bench: --json is ignored without hyperfine / --json игнорируется без hyperfine\n'
    printf '\n'

    for i in "${!commands[@]}"; do
        for ((w = 0; w < warmup; w++)); do
            eval "${commands[$i]}"
        done
        local_sum=0
        local_min=-1
        local_max=0
        for ((r = 0; r < runs; r++)); do
            start="$(now_us)"
            eval "${commands[$i]}"
            end="$(now_us)"
            delta=$((end - start))
            local_sum=$((local_sum + delta))
            ((local_min < 0 || delta < local_min)) && local_min="${delta}"
            ((delta > local_max)) && local_max="${delta}"
        done
        LC_ALL=C awk -v label="${labels[$i]}" -v sum="${local_sum}" -v n="${runs}" \
            -v min="${local_min}" -v max="${local_max}" \
            'BEGIN { printf "%-20s mean %8.1f ms  min %8.1f ms  max %8.1f ms\n", label, sum / n / 1000, min / 1000, max / 1000 }'
    done
fi
