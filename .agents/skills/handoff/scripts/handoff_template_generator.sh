#!/usr/bin/env bash
# shellcheck shell=bash
# .agents/skills/handoff/scripts/handoff_template_generator.sh — generate a handoff document scaffold tailored to next-session focus
# .agents/skills/handoff/scripts/handoff_template_generator.sh — сгенерировать скелет handoff-документа под фокус следующей сессии

# Bash port of the former handoff_template_generator.py (this repo is
# Python-free). Outputs a markdown skeleton matching Matt Pocock's handoff
# structure: goal of next session, state of play, open decisions, skills to
# use, artifacts (references only — NO duplication of content).
# Баш-порт прежнего handoff_template_generator.py (репозиторий без Python).
# Выдаёт markdown-скелет в структуре handoff Мэтта Покока.
#
# Usage / Использование:
#   bash handoff_template_generator.sh                                   # embedded sample / встроенный пример
#   bash handoff_template_generator.sh --next-focus "ship PR to dev"
#   bash handoff_template_generator.sh --next-focus "debug auth" --output json
#   bash handoff_template_generator.sh --next-focus "review CI failures" --out /tmp/handoff-XXX.md
#   bash handoff_template_generator.sh --next-focus "ship" --mktemp

set -euo pipefail

# BS bootstrap: repo root is resolved from this script's location
# BS-бутстрап: корень репозитория вычисляется из расположения скрипта
export BS_SILENT=1
__script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck disable=SC1091
source "${__script_dir}/../../../../bootstrap/init.sh"

usage() {
    cat <<'HELP'
usage: handoff_template_generator.sh [-h] [--next-focus NEXT_FOCUS]
                                     [--session-id SESSION_ID] [--out OUT]
                                     [--mktemp] [--output {text,json}]

Generate a handoff document template per Matt Pocock's structure.

options:
  -h, --help               show this help message and exit
  --next-focus NEXT_FOCUS  Description of what the next session will focus on
  --session-id SESSION_ID  Optional session ID for traceability
  --out OUT                Write template to file (default: stdout)
  --mktemp                 Write to a mktemp-style file (handoff-XXXXXX.md)
  --output {text,json}     Output format (default: text)
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
    # ensure_ascii parity for the fixed non-ASCII chars of the template: —
    # Байт-паритет ensure_ascii для фиксированного не-ASCII символа шаблона: —
    s="${s//—/\\u2014}"
    printf '%s' "${s}"
}

# Map a next-focus string to a section emphasis via keyword matching (first
# match wins, same keyword order as the Python original)
# Отобразить фокус следующей сессии на акцент секций по ключевым словам
# (побеждает первое совпадение, порядок ключей — как в Python-оригинале)
detect_emphasis() {
    local -r focus="${1,,}"
    [[ -n "${focus}" ]] || { printf 'default'; return 0; }
    case "${focus}" in
        *ship*|*deploy*|*pr*)            printf 'deployment_emphasis' ;;
        *review*|*audit*)                printf 'review_emphasis' ;;
        *debug*|*fix*|*investigate*)     printf 'debug_emphasis' ;;
        *design*|*plan*|*scope*)         printf 'design_emphasis' ;;
        *test*|*qa*)                     printf 'test_emphasis' ;;
        *)                               printf 'default' ;;
    esac
}

# Print the prompt list for an emphasis / Напечатать список промптов для акцента
section_prompts() {
    case "${1}" in
        deployment_emphasis)
            cat <<'PROMPTS'
What's the exact command to ship? `git push` + `mcp__github__create_pull_request`?
Which checks must be green before merge?
Who needs to approve?
What's the rollback plan if CI catches something?
PROMPTS
            ;;
        review_emphasis)
            cat <<'PROMPTS'
What's the review checklist for this PR?
Which files are sensitive (security/secrets)?
Where are existing similar patterns?
What past PRs reviewed this code path?
PROMPTS
            ;;
        debug_emphasis)
            cat <<'PROMPTS'
What's the exact symptom + reproduction steps?
What's been tried already?
Which logs / traces are most informative?
What's the smallest reproducing case?
PROMPTS
            ;;
        design_emphasis)
            cat <<'PROMPTS'
What's the user-facing outcome the design must achieve?
What's the non-negotiable constraint?
What are the rejected alternatives + why?
What's reversible vs irreversible in this design?
PROMPTS
            ;;
        test_emphasis)
            cat <<'PROMPTS'
What's the test plan?
Which existing tests cover this?
Where are edge cases hiding?
How is success measured?
PROMPTS
            ;;
        *)
            cat <<'PROMPTS'
What's the immediate next action?
What's blocking right now?
Where are the relevant files?
What decisions are still open?
PROMPTS
            ;;
    esac
}

# Build the markdown template on stdout / Собрать markdown-шаблон в stdout
generate_template() {
    local -r next_focus="${1}" session_id="${2}" emphasis="${3}"
    local timestamp session_label title_focus tailor_focus
    timestamp="$(date +%Y-%m-%dT%H:%M:%S)"
    session_label="${session_id:-<session_id>}"
    title_focus="${next_focus:-(general)}"
    tailor_focus="${next_focus:-general}"

    local -a lines=(
        "# Handoff — ${title_focus}"
        ""
        "**Generated:** ${timestamp}"
        "**From session:** ${session_label}"
        "**Next focus:** ${next_focus:-(unspecified — fill in)}"
        ""
        "---"
        ""
        "## Goal of next session"
        ""
        "[Describe what the next session must accomplish. Tailored to: ${tailor_focus}]"
        ""
        "Prompts to answer:"
    )
    local prompt
    while IFS= read -r prompt; do
        lines+=("- ${prompt}")
    done < <(section_prompts "${emphasis}")
    lines+=(
        ""
        "## State of play"
        ""
        "**Done:**"
        "- [list what's complete with paths/refs to artifacts]"
        ""
        "**In progress:**"
        "- [list what's mid-flight + current branch/PR if applicable]"
        ""
        "**Blocking:**"
        "- [list blockers + who/what unblocks each]"
        ""
        "## Open decisions"
        ""
        "- [Decision 1: options + current lean]"
        "- [Decision 2: options + current lean]"
        ""
        "## Skills to use (next session)"
        ""
        "- [Skill 1 — when to invoke]"
        "- [Skill 2 — when to invoke]"
        ""
        "## Artifacts (reference only — do NOT duplicate)"
        ""
        "- **PRD/Plan:** [path or URL]"
        "- **ADRs:** [path]"
        "- **Issues:** [#nnn]"
        "- **Branch:** [name]"
        "- **Open PRs:** [#nnn]"
        "- **Recent commits:** [paths or SHAs]"
        "- **Validators/tests run:** [results]"
        ""
        "---"
        ""
        "**Rule:** This document references existing artifacts. If you find yourself duplicating content from a PRD/plan/issue, replace it with a path/URL instead."
    )
    # Command substitution strips the trailing newline: result equals "\n".join
    # Подстановка команды срезает хвостовой перевод строки: результат равен "\n".join
    printf '%s\n' "${lines[@]}"
}

main() {
    local opt_next_focus="" opt_session_id="" opt_out="" opt_output="text"
    local -i opt_mktemp=0

    while [[ $# -gt 0 ]]; do
        case "${1}" in
            -h|--help)
                usage
                exit 0
                ;;
            --next-focus)   [[ $# -ge 2 ]] || { log::error "argument --next-focus: expected one argument"; exit 2; }; opt_next_focus="${2}"; shift 2 ;;
            --next-focus=*) opt_next_focus="${1#*=}"; shift ;;
            --session-id)   [[ $# -ge 2 ]] || { log::error "argument --session-id: expected one argument"; exit 2; }; opt_session_id="${2}"; shift 2 ;;
            --session-id=*) opt_session_id="${1#*=}"; shift ;;
            --out)          [[ $# -ge 2 ]] || { log::error "argument --out: expected one argument"; exit 2; }; opt_out="${2}"; shift 2 ;;
            --out=*)        opt_out="${1#*=}"; shift ;;
            --mktemp)       opt_mktemp=1; shift ;;
            --output)       [[ $# -ge 2 ]] || { log::error "argument --output: expected one argument"; exit 2; }; opt_output="${2}"; shift 2 ;;
            --output=*)     opt_output="${1#*=}"; shift ;;
            *)
                log::error "unrecognized argument: ${1}"
                exit 2
                ;;
        esac
    done

    [[ "${opt_output}" == "text" || "${opt_output}" == "json" ]] \
        || die "argument --output: invalid choice: '${opt_output}' (choose from 'text', 'json')"

    if [[ -z "${opt_next_focus}" ]]; then
        opt_next_focus="(embedded sample: continue Stream B Matt Pocock skills batch)"
        opt_session_id="${opt_session_id:-sample-session-001}"
    fi

    local emphasis template
    emphasis="$(detect_emphasis "${opt_next_focus}")"
    template="$(generate_template "${opt_next_focus}" "${opt_session_id}" "${emphasis}")"

    local -i length_chars length_lines
    length_chars="${#template}"
    length_lines="$(printf '%s' "${template}" | tr -cd '\n' | wc -c)"
    length_lines+=1

    local written_to=""
    if [[ "${opt_mktemp}" -eq 1 ]]; then
        # Matt's convention: mktemp -t handoff-XXXXXX.md / Конвенция Мэтта
        written_to="$(mktemp "${TMPDIR:-/tmp}/handoff-XXXXXXXX.md")" \
            || die "mktemp failed"
        printf '%s' "${template}" > "${written_to}"
    fi
    if [[ -n "${opt_out}" ]]; then
        printf '%s' "${template}" > "${opt_out}" || die "cannot write: ${opt_out}"
        written_to="${opt_out}"
    fi

    if [[ "${opt_output}" == "json" ]]; then
        printf '{\n'
        printf '  "next_focus": "%s",\n' "$(json_escape "${opt_next_focus}")"
        printf '  "emphasis_detected": "%s",\n' "${emphasis}"
        printf '  "session_id": "%s",\n' "$(json_escape "${opt_session_id}")"
        printf '  "template_length_chars": %s,\n' "${length_chars}"
        printf '  "template_length_lines": %s,\n' "${length_lines}"
        if [[ -n "${written_to}" ]]; then
            printf '  "written_to": "%s",\n' "$(json_escape "${written_to}")"
        fi
        printf '  "template_preview": "%s"\n' "$(json_escape "${template:0:500}")"
        printf '}\n'
    else
        if [[ -n "${written_to}" ]]; then
            printf 'Wrote handoff template to: %s\n' "${written_to}"
            printf '  Focus: %s\n' "${opt_next_focus}"
            printf '  Emphasis: %s\n' "${emphasis}"
            printf '  Length: %s lines\n' "${length_lines}"
        else
            printf '%s\n' "${template}"
        fi
    fi
}

main "$@"
