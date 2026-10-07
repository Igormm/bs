#!/usr/bin/env bash
# shellcheck shell=bash
# .agents/skills/handoff/scripts/artifact_deduplicator.sh — detect content in a handoff draft that should be referenced, not duplicated
# .agents/skills/handoff/scripts/artifact_deduplicator.sh — найти в черновике handoff контент, который надо не дублировать, а ссылаться

# Bash port of the former artifact_deduplicator.py (this repo is Python-free).
# Pure pattern matching, no LLM calls. Detection signals:
# Баш-порт прежнего artifact_deduplicator.py. Чистый паттерн-матчинг.
#   - PRD/plan headers ("Problem statement", "Solution", ...)
#   - ADR template fields ("Decision", "Consequences", "Status: Accepted")
#   - Commit-message style (Conventional Commit prefix at line start)
#   - Issue-style fields ("Steps to reproduce", "Expected behavior", ...)
#   - Long code blocks (>20 lines) that look like checked-in code
#
# Usage / Использование:
#   bash artifact_deduplicator.sh                              # embedded sample / встроенный пример
#   bash artifact_deduplicator.sh path/to/handoff-draft.md
#   bash artifact_deduplicator.sh handoff.md --output json
#
# Exit code / Код возврата: 0 when CLEAN, 1 when findings exist (WARN/FAIL).

set -euo pipefail

# BS bootstrap: repo root is resolved from this script's location
# BS-бутстрап: корень репозитория вычисляется из расположения скрипта
export BS_SILENT=1
__script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck disable=SC1091
source "${__script_dir}/../../../../bootstrap/init.sh"

readonly CODE_BLOCK_THRESHOLD=20

readonly PRD_HEADERS=("problem statement" "solution" "success metrics" "out of scope" "user stories" "acceptance criteria")
readonly ADR_FIELDS=("status:" "decision:" "consequences:" "context:" "alternatives considered")
readonly ISSUE_FIELDS=("steps to reproduce" "expected behavior" "actual behavior" "environment:" "labels:")
readonly COMMIT_PREFIXES=("feat:" "fix:" "docs:" "chore:" "refactor:" "test:" "ci:" "build:" "perf:")

# Suggestion texts are literal documentation strings (backticks/$ are data, not expansions)
# Тексты советов — литеральные строки документации (бэктики/$ — данные, не подстановки)
# shellcheck disable=SC2016
{
readonly PRD_SUGGESTION='Replace this section with a link to the canonical PRD file (e.g., `[Full PRD](path/to/prd.md)`).'
readonly ADR_SUGGESTION='Replace with a link to the ADR file (e.g., `[ADR-NNNN](docs/adr/NNNN.md)`).'
readonly ISSUE_SUGGESTION='Replace with issue reference (e.g., `#NNN` or full URL).'
readonly COMMIT_SUGGESTION='Replace with commit SHA + URL (e.g., `[abc1234](https://github.com/.../commit/abc1234)`).'
readonly LONG_CODE_SUGGESTION='Long code blocks usually duplicate checked-in code. Replace with file path + commit SHA (e.g., `[src/foo.py:42-80](https://github.com/.../blob/SHA/src/foo.py#L42-L80)`).'
}

# Field separator for packed finding records / Разделитель полей упакованных записей
readonly FS=$'\x1f'

# Finding records, packed with FS: line, kind, trigger, context, suggestion
# Записи находок, упакованные через FS: строка, тип, триггер, контекст, совет
declare -ga FINDINGS=()

usage() {
    cat <<'HELP'
usage: artifact_deduplicator.sh [-h] [--output {text,json}] [path]

Detect duplicated artifact content in a handoff draft.

positional arguments:
  path                   Path to handoff markdown (uses embedded sample if omitted)

options:
  -h, --help             show this help message and exit
  --output {text,json}   Output format (default: text)
HELP
}

die() {
    log::error "${1}"
    exit 2
}

# Escape a string for JSON output / Экранировать строку для JSON-вывода
json_escape() {
    local s="${1}"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\t'/\\t}"
    s="${s//$'\r'/\\r}"
    printf '%s' "${s}"
}

# Strip leading and trailing whitespace / Срезать пробелы с обоих концов
strip_ws() {
    local s="${1}"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "${s}"
}

# Append a finding record: line, kind, trigger, context (<=120 chars), suggestion
# Добавить запись находки: строка, тип, триггер, контекст (<=120 символов), совет
add_finding() {
    local -r line_no="${1}" kind="${2}" trigger="${3}" context="${4}" suggestion="${5}"
    FINDINGS+=("${line_no}${FS}${kind}${FS}${trigger}${FS}${context:0:120}${FS}${suggestion}")
}

# Scan for PRD/plan headers / Сканировать на заголовки PRD/плана
find_prd_content() {
    local -n lines_ref="${1}"
    local line line_lower header
    local -i line_no=0
    for line in "${lines_ref[@]}"; do
        line_no+=1
        # Header requires markdown '#' or ':' on the line (as in the Python original)
        # Заголовок требует markdown '#' или ':' в строке (как в Python-оригинале)
        [[ "${line}" == *#* || "${line}" == *:* ]] || continue
        line_lower="${line,,}"
        for header in "${PRD_HEADERS[@]}"; do
            if [[ "${line_lower}" == *"${header}"* ]]; then
                add_finding "${line_no}" "prd_content" "${header}" "$(strip_ws "${line}")" "${PRD_SUGGESTION}"
                break
            fi
        done
    done
}

# Scan for ADR template fields / Сканировать на поля шаблона ADR
find_adr_content() {
    local -n lines_ref="${1}"
    local line line_lower field
    local -i line_no=0
    for line in "${lines_ref[@]}"; do
        line_no+=1
        line_lower="${line,,}"
        for field in "${ADR_FIELDS[@]}"; do
            if [[ "${line_lower}" == *"${field}"* ]]; then
                add_finding "${line_no}" "adr_content" "${field}" "$(strip_ws "${line}")" "${ADR_SUGGESTION}"
                break
            fi
        done
    done
}

# Scan for issue-style fields / Сканировать на поля в стиле issue
find_issue_content() {
    local -n lines_ref="${1}"
    local line line_lower field
    local -i line_no=0
    for line in "${lines_ref[@]}"; do
        line_no+=1
        line_lower="${line,,}"
        for field in "${ISSUE_FIELDS[@]}"; do
            if [[ "${line_lower}" == *"${field}"* ]]; then
                add_finding "${line_no}" "issue_content" "${field}" "$(strip_ws "${line}")" "${ISSUE_SUGGESTION}"
                break
            fi
        done
    done
}

# Scan for Conventional Commit style lines / Сканировать на строки в стиле Conventional Commit
find_commit_style() {
    local -n lines_ref="${1}"
    local line stripped prefix
    local -i line_no=0
    for line in "${lines_ref[@]}"; do
        line_no+=1
        stripped="$(strip_ws "${line}")"
        stripped="${stripped,,}"
        for prefix in "${COMMIT_PREFIXES[@]}"; do
            if [[ "${stripped}" == "${prefix}"* ]]; then
                add_finding "${line_no}" "commit_style" "${prefix}" "$(strip_ws "${line}")" "${COMMIT_SUGGESTION}"
                break
            fi
        done
    done
}

# Scan for fenced code blocks longer than CODE_BLOCK_THRESHOLD
# Сканировать на fenced-блоки кода длиннее CODE_BLOCK_THRESHOLD
find_long_code_blocks() {
    local -n lines_ref="${1}"
    local line stripped
    local -i line_no=0 block_start=0 block_lines=0
    local in_block=false
    for line in "${lines_ref[@]}"; do
        line_no+=1
        stripped="$(strip_ws "${line}")"
        if [[ "${stripped}" == '```'* ]]; then
            if [[ "${in_block}" == "true" ]]; then
                if (( block_lines > CODE_BLOCK_THRESHOLD )); then
                    add_finding "${block_start}" "long_code_block" "${block_lines} lines" \
                        "Code block L${block_start}-L${line_no}" "${LONG_CODE_SUGGESTION}"
                fi
                in_block=false
                block_lines=0
            else
                in_block=true
                block_start=${line_no}
                block_lines=0
            fi
        elif [[ "${in_block}" == "true" ]]; then
            block_lines+=1
        fi
    done
}

main() {
    local opt_path="" opt_output="text"

    while [[ $# -gt 0 ]]; do
        case "${1}" in
            -h|--help)
                usage
                exit 0
                ;;
            --output)   [[ $# -ge 2 ]] || { log::error "argument --output: expected one argument"; exit 2; }; opt_output="${2}"; shift 2 ;;
            --output=*) opt_output="${1#*=}"; shift ;;
            -*)
                log::error "unrecognized argument: ${1}"
                exit 2
                ;;
            *)
                if [[ -z "${opt_path}" ]]; then
                    opt_path="${1}"
                else
                    log::error "unrecognized argument: ${1}"
                    exit 2
                fi
                shift
                ;;
        esac
    done

    [[ "${opt_output}" == "text" || "${opt_output}" == "json" ]] \
        || die "argument --output: invalid choice: '${opt_output}' (choose from 'text', 'json')"

    local -a lines=()
    if [[ -n "${opt_path}" ]]; then
        if [[ ! -f "${opt_path}" ]]; then
            printf 'error: %s: No such file or directory\n' "${opt_path}" >&2
            exit 1
        fi
        local line
        # IFS= keeps leading whitespace; the trailing '|| [[ -n ]]' keeps a
        # final line without newline / сохранить последнюю строку без перевода
        while IFS= read -r line || [[ -n "${line}" ]]; do
            lines+=("${line}")
        done < "${opt_path}"
    else
        # Embedded sample (a BAD handoff on purpose); literal text with $/backticks
        # Встроенный пример (нарочно ПЛОХОЙ handoff); литеральный текст с $/бэктиками
        # shellcheck disable=SC2016
        local sample='# Handoff

## Problem statement
Users complain about slow auth. We need to make it fast.

## Solution
Implement OAuth2 with refresh tokens.

## Status: Accepted

Decision: Use Auth0 over Okta.
Consequences: $200/month cost; faster integration.

## Steps to reproduce the bug
1. Login
2. Wait 10 seconds
3. Re-login

feat: add OAuth2 support
This change adds OAuth2 to the auth middleware.
- Added refresh token handling
- Added expiry check
'
        local line
        while IFS= read -r line || [[ -n "${line}" ]]; do
            lines+=("${line}")
        done <<< "${sample}"
    fi

    # FINDINGS is populated by add_finding / FINDINGS заполняется через add_finding
    FINDINGS=()
    find_prd_content lines
    find_adr_content lines
    find_issue_content lines
    find_commit_style lines
    find_long_code_blocks lines

    # by_kind counts in first-encounter order (Python dict behaviour)
    # счётчики по типам в порядке первого появления (поведение dict в Python)
    local -A by_kind=()
    local -a kind_order=()
    local record kind
    for record in "${FINDINGS[@]}"; do
        kind="${record#*"${FS}"}"
        kind="${kind%%"${FS}"*}"
        if [[ -z "${by_kind[${kind}]:-}" ]]; then
            kind_order+=("${kind}")
            by_kind["${kind}"]=1
        else
            by_kind["${kind}"]=$(( by_kind["${kind}"] + 1 ))
        fi
    done

    local -i total=${#FINDINGS[@]}
    local verdict="CLEAN"
    if (( total > 3 )); then
        verdict="FAIL"
    elif (( total > 0 )); then
        verdict="WARN"
    fi

    if [[ "${opt_output}" == "json" ]]; then
        printf '{\n  "total_findings": %s,\n' "${total}"
        local -i i
        if [[ ${#kind_order[@]} -gt 0 ]]; then
            printf '  "by_kind": {'
            for ((i = 0; i < ${#kind_order[@]}; i++)); do
                (( i > 0 )) && printf ','
                printf '\n    "%s": %s' "${kind_order[${i}]}" "${by_kind[${kind_order[${i}]}]}"
            done
            printf '\n  },\n'
        else
            printf '  "by_kind": {},\n'
        fi
        printf '  "findings": ['
        local f_line f_kind f_trigger f_context f_suggestion rest
        for ((i = 0; i < total; i++)); do
            (( i > 0 )) && printf ','
            record="${FINDINGS[${i}]}"
            f_line="${record%%"${FS}"*}"; rest="${record#*"${FS}"}"
            f_kind="${rest%%"${FS}"*}"; rest="${rest#*"${FS}"}"
            f_trigger="${rest%%"${FS}"*}"; rest="${rest#*"${FS}"}"
            f_context="${rest%%"${FS}"*}"; f_suggestion="${rest#*"${FS}"}"
            printf '\n    {\n'
            printf '      "line": %s,\n' "${f_line}"
            printf '      "kind": "%s",\n' "$(json_escape "${f_kind}")"
            printf '      "trigger": "%s",\n' "$(json_escape "${f_trigger}")"
            printf '      "context": "%s",\n' "$(json_escape "${f_context}")"
            printf '      "suggestion": "%s"\n' "$(json_escape "${f_suggestion}")"
            printf '    }'
        done
        if (( total > 0 )); then
            printf '\n  ],\n'
        else
            printf '],\n'
        fi
        printf '  "verdict": "%s"\n}\n' "${verdict}"
    else
        printf '%0.s=' {1..72}; printf '\n'
        printf 'HANDOFF ARTIFACT DEDUPLICATOR (per Matt Pocock'"'"'s no-duplication rule)\n'
        printf '%0.s=' {1..72}; printf '\n\n'
        printf 'Total findings: %s\n' "${total}"
        local by_kind_text="{}"
        if [[ ${#kind_order[@]} -gt 0 ]]; then
            local -a pairs=()
            local -i i
            for ((i = 0; i < ${#kind_order[@]}; i++)); do
                pairs+=("$(printf "'%s': %s" "${kind_order[${i}]}" "${by_kind[${kind_order[${i}]}]}")")
            done
            local joined
            joined="$(printf '%s, ' "${pairs[@]}")"
            by_kind_text="{${joined%, }}"
        fi
        printf 'By kind: %s\n\n' "${by_kind_text}"
        printf '%0.s-' {1..72}; printf '\n'
        if (( total == 0 )); then
            printf 'No duplicated artifact content detected. Good handoff hygiene.\n'
        else
            local f_line f_kind f_trigger f_context f_suggestion rest
            for record in "${FINDINGS[@]}"; do
                f_line="${record%%"${FS}"*}"; rest="${record#*"${FS}"}"
                f_kind="${rest%%"${FS}"*}"; rest="${rest#*"${FS}"}"
                f_trigger="${rest%%"${FS}"*}"; rest="${rest#*"${FS}"}"
                f_context="${rest%%"${FS}"*}"; f_suggestion="${rest#*"${FS}"}"
                printf "  L%4d [%-18s] '%s'\n" "${f_line}" "${f_kind}" "${f_trigger}"
                printf '        Context: %s\n' "${f_context}"
                printf '        Suggestion: %s\n\n' "${f_suggestion}"
            done
        fi
        printf '%0.s-' {1..72}; printf '\n'
        printf 'Verdict: %s\n' "${verdict}"
    fi

    [[ "${verdict}" == "CLEAN" ]]
}

main "$@"
