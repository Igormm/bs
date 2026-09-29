#!/usr/bin/env bash
# shellcheck shell=bash
# .agents/skills/bs-check-ansi/scripts/check_ansi.sh — verify ANSI escape usage across the project
# .agents/skills/bs-check-ansi/scripts/check_ansi.sh — проверить использование ANSI-escape по всему проекту

# Scans core/, lib/, bs, install/, bootstrap/, examples/ for ANSI escape
# patterns and classifies each hit. Exits 1 when a CRITICAL (broken output)
# pattern is found.
# Сканирует core/, lib/, bs, install/, bootstrap/, examples/ на паттерны
# ANSI-escape и классифицирует каждое совпадение. Exit 1 при CRITICAL
# (сломанный вывод).

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
readonly SCOPE="${1:-core lib bs install bootstrap examples}"
readonly GREEN=$'\033[32m' RED=$'\033[31m' YELLOW=$'\033[33m' CYAN=$'\033[36m' RESET=$'\033[0m'

crit=0
warn=0
ok=0

report() {
    local level="$1" color="$2" msg="$3"
    printf '%s%s%s %s\n' "${color}" "${level}" "${RESET}" "${msg}"
    case "${level}" in
        CRITICAL) (( crit += 1 )) ;;
        WARN)     (( warn += 1 )) ;;
        OK)       (( ok += 1 )) ;;
    esac
}

# A1. Single-quoted '\033 — printf %s prints it literally (broken colors)
# A1. '\033 в одинарных кавычках — printf %s печатает буквально (сломанные цвета)
#    Correct form: $'\033[...' (ANSI-C quoting) or printf '\033' (format string).
#    Правильно: $'\033[...' (ANSI-C quoting) или printf '\033' (format-строка).
#    printf '\033' in a FORMAT string is fine (C1) — exclude it here.
#    printf '\033' в FORMAT-строке — корректно (C1) — исключаем здесь.
mapfile -t a1 < <(rg -n "'\\\\033" ${SCOPE} --glob '*.sh' -g 'bs' 2>/dev/null | rg -v "\\\$'\\\\033|printf [\"']\\\\033" || true)
if [[ ${#a1[@]} -eq 0 ]]; then
    report OK "${GREEN}" "A1 single-quoted '\033 literal escapes: none"
else
    for hit in "${a1[@]}"; do
        report CRITICAL "${RED}" "A1 ${hit%%:*} :${hit#*:} — '\033 in plain quotes; printf '%s' prints literal \\033 text (use \$'\033[...')"
    done
fi

# A2. printf with %s receiving a single-quoted \033 argument
# A2. printf с %s, получающим '\033 аргумент в одинарных кавычках
mapfile -t a2 < <(rg -n "printf [\"'][^\"']*%s[^\"']*[\"'] *'\\\\033|printf [\"']%s[\"'] *'\\\\033" ${SCOPE} --glob '*.sh' -g 'bs' 2>/dev/null | rg -v "\\\$'\\\\033" || true)
if [[ ${#a2[@]} -eq 0 ]]; then
    report OK "${GREEN}" "A2 printf %s with single-quoted escape: none"
else
    for hit in "${a2[@]}"; do
        report CRITICAL "${RED}" "A2 ${hit%%:*} :${hit#*:} — printf %s + '\033 argument prints the literal text"
    done
fi

# B1. echo -e with single-quoted escapes — works but fragile (xpg_echo)
# B1. echo -e с '\033 — работает, но хрупко (зависит от xpg_echo)
mapfile -t b1 < <(rg -n "echo -e.*'\\\\033|echo -e.*\\\$'\\\\033" ${SCOPE} --glob '*.sh' -g 'bs' 2>/dev/null || true)
if [[ ${#b1[@]} -eq 0 ]]; then
    report OK "${GREEN}" "B1 echo -e with escapes: none"
else
    for hit in "${b1[@]}"; do
        report WARN "${YELLOW}" "B1 ${hit%%:*} :${hit#*:} — echo -e relies on xpg_echo; prefer printf"
    done
fi

# C1. printf format-string escapes — correct, printf interprets them
# C1. Escape в format-строке printf — корректно, printf интерпретирует
mapfile -t c1 < <(rg -n "printf ['\"]\\\\033" ${SCOPE} --glob '*.sh' -g 'bs' 2>/dev/null || true)
if [[ ${#c1[@]} -eq 0 ]]; then
    report OK "${GREEN}" "C1 printf format-string escapes: none (or all via \$')"
else
    for hit in "${c1[@]}"; do
        report OK "${CYAN}" "C1 ${hit%%:*} :${hit#*:} — printf '\033' in format string: correct"
    done
fi

# C2. $'\033' ANSI-C quoting — correct
# C2. $'\033' ANSI-C quoting — корректно
mapfile -t c2 < <(rg -n "\\\$'\\\\033" ${SCOPE} --glob '*.sh' -g 'bs' 2>/dev/null | head -40 || true)
if [[ ${#c2[@]} -eq 0 ]]; then
    report OK "${GREEN}" "C2 \$'\033' ANSI-C quoting: none"
else
    report OK "${CYAN}" "C2 \$'\033' ANSI-C quoting: ${#c2[@]} hit(s) — correct syntax"
    for hit in "${c2[@]}"; do
        printf '      %s\n' "${hit}"
    done
fi

printf '\n'
printf '%-9s %s\n' "CRITICAL" "${crit}"
printf '%-9s %s\n' "WARN" "${warn}"
printf '%-9s %s\n' "OK" "${ok}"
printf '\n'

if (( crit > 0 )); then
    printf '%sANSI CHECK FAIL — broken color output patterns found; fix with \$'\''\\033[...'\'' (ANSI-C quoting)%s\n' "${RED}" "${RESET}" >&2
    exit 1
fi
printf '%sANSI CHECK PASS%s\n' "${GREEN}" "${RESET}"