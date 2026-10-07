#!/usr/bin/env bash
# shellcheck shell=bash
# .agents/skills/handoff/scripts/skill_recommender.sh — recommend which skills the next session should use
# .agents/skills/handoff/scripts/skill_recommender.sh — порекомендовать навыки для следующей сессии

# Bash port of the former skill_recommender.py (this repo is Python-free).
# Scans a handoff document for content signals and matches them to
# skills, ranked by signal strength. No LLM calls — pattern matching only.
# Баш-порт прежнего skill_recommender.py. Сканирует handoff-документ на
# сигналы и сопоставляет их навыкам, ранжируя по силе сигнала.
#
# Simplifications vs the Python original / Упрощения относительно Python-оригинала:
# - ERE patterns are evaluated by GNU grep (-o -i -E) instead of `re`; \b word
#   boundaries and [[:space:]] classes are used, matching is line-oriented, so
#   the input is pre-flattened (newlines -> spaces) to keep \s+ semantics.
# - "matched_keywords" previews full matched strings; Python previewed regex
#   capture groups (e.g. "write a" instead of "write a skill").
#
# Usage / Использование:
#   bash skill_recommender.sh                          # embedded sample / встроенный пример
#   bash skill_recommender.sh path/to/handoff.md
#   bash skill_recommender.sh handoff.md --output json

set -euo pipefail

# BS bootstrap: repo root is resolved from this script's location
# BS-бутстрап: корень репозитория вычисляется из расположения скрипта
export BS_SILENT=1
__script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck disable=SC1091
source "${__script_dir}/../../../../bootstrap/init.sh"

usage() {
    cat <<'HELP'
usage: skill_recommender.sh [-h] [--output {text,json}] [path]

Recommend skills for the next session based on handoff content.

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
    # ensure_ascii parity for the fixed non-ASCII chars of the rationales: × ÷
    # Байт-паритет ensure_ascii для фиксированных не-ASCII символов обоснований: × ÷
    s="${s//×/\\u00d7}"
    s="${s//÷/\\u00f7}"
    printf '%s' "${s}"
}

# Signal table (parallel arrays): ERE pattern -> skill + rationale
# Таблица сигналов (параллельные массивы): ERE-паттерн -> навык + обоснование
readonly SKILL_PATTERNS=(
    '\b(write|create|author|build)[[:space:]]+(a[[:space:]]+)?skill\b'
    '\b(caveman|less[[:space:]]+tokens|be[[:space:]]+brief|compress)\b'
    '\b(grill|stress[-[:space:]]?test|interrog|decision[[:space:]]+tree)\b'
    '\b(TDD|unit[[:space:]]+test|test[[:space:]]+driven)\b'
    '\b(RICE|prioritiz|feature[[:space:]]+score)\b'
    '\b(user[[:space:]]+stor|INVEST)\b'
    '\b(karpathy|complexity|refactor|code[[:space:]]+quality)\b'
    '\b(ship[[:space:]]+gate|pre[-[:space:]]?flight|production[[:space:]]+ready)\b'
    '\b(ISO[[:space:]]+13485|ISO[[:space:]]+27001|GDPR|HIPAA|MDR|FDA|compliance|audit)\b'
    '\b(SLO|error[[:space:]]+budget|burn[[:space:]]+rate)\b'
    '\b(feature[[:space:]]+flag|kill[[:space:]]+switch|gradual[[:space:]]+rollout|canary)\b'
    '\b(incident|postmortem|outage|root[[:space:]]+cause)\b'
    '\b(AI[[:space:]]+security|prompt[[:space:]]+inject|threat[[:space:]]+model|OWASP)\b'
    '\b(research|citation|authoritative[[:space:]]+source|deep[[:space:]]+research)\b'
    '\b(handoff|next[[:space:]]+session|continue[[:space:]]+the[[:space:]]+work)\b'
)
readonly SKILL_NAMES=(
    "write-a-skill"
    "caveman"
    "grill-me"
    "tdd-guide"
    "rice-prioritizer"
    "user-story-writer"
    "karpathy-coder"
    "ship-gate"
    "compliance-os"
    "slo-architect"
    "feature-flags-architect"
    "incident-response"
    "ai-security"
    "autoresearch-agent"
    "handoff"
)
readonly SKILL_RATIONALES=(
    "Next session involves authoring a new skill; the write-a-skill skill applies Matt Pocock's 3-phase workflow + validates against the 6-item checklist."
    "Next session benefits from token-compressed responses; caveman applies Matt's compression rules deterministically."
    "Next session involves stress-testing a plan; grill-me walks decision branches one-at-a-time with forcing questions."
    "Next session involves testing; tdd-guide enforces test-first discipline."
    "Next session involves feature prioritization; rice-prioritizer computes Reach × Impact × Confidence ÷ Effort."
    "Next session involves user stories; user-story-writer applies INVEST + Gherkin acceptance criteria."
    "Next session involves code-quality discipline; karpathy-coder runs complexity_checker + assumption_linter + diff_surgeon."
    "Next session involves pre-production audit; ship-gate runs 89 checks across 8 categories."
    "Next session involves regulatory/compliance work; compliance-os covers 12 frameworks with mock audit scenarios."
    "Next session involves SLO/SLI/error-budget work; slo-architect applies Google SRE Workbook discipline."
    "Next session involves feature-flag work; feature-flags-architect scans flag debt + rollout plans."
    "Next session involves incident response or postmortem; incident-response provides templates + analysis tools."
    "Next session involves AI security or threat work; ai-security covers prompt injection + model threats."
    "Next session needs citation-backed research; autoresearch-agent produces deep-research reports."
    "Next session may need to be handed off again; handoff produces continuity docs."
)

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

    local text
    if [[ -n "${opt_path}" ]]; then
        if [[ ! -f "${opt_path}" ]]; then
            printf 'error: %s: No such file or directory\n' "${opt_path}" >&2
            exit 1
        fi
        text="$(cat -- "${opt_path}")" || { printf 'error: cannot read %s\n' "${opt_path}" >&2; exit 1; }
    else
        # Embedded sample / Встроенный пример
        text='# Handoff — ship Matt Pocock skills batch

## Goal of next session
Open PR for caveman + grill-me + handoff skills. Validate against the karpathy-coder
gate (complexity checker + assumption linter) and the write-a-skill 6-item checklist.
Investigate any CI failures.

## State of play
Done: write-a-skill plugin shipped + merged.
In progress: 3 sibling skills built locally, need PR.
Blocking: nothing.

## Open decisions
- Should we caveman the PR description?
- Re-grill the plan before opening PR?

## Artifacts
- Branch: feature/pocock-productivity-batch
- Issues: none
- PRD: documentation/implementation/pocock-derived-skills-plan.md'
    fi

    # Flatten newlines so multi-word signals match across line breaks (re \s+)
    # Схлопнуть переводы строк, чтобы многословные сигналы матчились через переносы
    local flat="${text//$'\n'/ }"

    # Accumulate per-signal hits: hits<TAB>order<TAB>signal_idx<TAB>kw1<US>kw2<US>kw3
    # Накопить попадания: hits<TAB>порядок<TAB>индекс_сигнала<TAB>ключи через US
    # (only the first 3 matched keywords are kept, as in the Python original /
    # хранятся только первые 3 совпавших ключа, как в Python-оригинале)
    local -a hits_rows=()
    local -i i order=0 hits
    local pattern matches kw_field
    local -a kws
    for ((i = 0; i < ${#SKILL_PATTERNS[@]}; i++)); do
        pattern="${SKILL_PATTERNS[${i}]}"
        matches="$(printf '%s' "${flat}" | grep -o -i -E "${pattern}" || true)"
        [[ -n "${matches}" ]] || continue
        hits="$(printf '%s\n' "${matches}" | wc -l)"
        order+=1
        mapfile -t kws < <(printf '%s\n' "${matches}" | head -n 3)
        kw_field="$(printf '%s\x1f' "${kws[@]}")"
        kw_field="${kw_field%$'\x1f'}"
        hits_rows+=("${hits}"$'\t'"${order}"$'\t'"${i}"$'\t'"${kw_field}")
    done

    # Rank by hits desc, stable by signal order (Python sorted() is stable)
    # Ранжировать по числу попаданий, стабильно по порядку сигналов (sorted() стабилен)
    local -a ranked=()
    if [[ ${#hits_rows[@]} -gt 0 ]]; then
        mapfile -t ranked < <(printf '%s\n' "${hits_rows[@]}" | sort -t $'\t' -k1,1nr -k2,2n)
    fi

    if [[ "${opt_output}" == "json" ]]; then
        printf '{\n  "total_skills_recommended": %s,\n  "recommendations": [' "${#ranked[@]}"
        local row hits_n idx
        local -a kws
        for ((i = 0; i < ${#ranked[@]}; i++)); do
            row="${ranked[${i}]}"
            hits_n="${row%%$'\t'*}"; row="${row#*$'\t'}"
            row="${row#*$'\t'}"  # skip order column / пропустить колонку порядка
            idx="${row%%$'\t'*}"; row="${row#*$'\t'}"
            IFS=$'\x1f' read -r -a kws <<< "${row}"
            (( i > 0 )) && printf ','
            printf '\n    {\n'
            printf '      "skill": "%s",\n' "$(json_escape "${SKILL_NAMES[${idx}]}")"
            printf '      "rationale": "%s",\n' "$(json_escape "${SKILL_RATIONALES[${idx}]}")"
            printf '      "hits": %s,\n' "${hits_n}"
            if [[ ${#kws[@]} -gt 0 ]]; then
                printf '      "matched_keywords": ['
                local -i k
                for ((k = 0; k < ${#kws[@]}; k++)); do
                    (( k > 0 )) && printf ','
                    printf '\n        "%s"' "$(json_escape "${kws[${k}]}")"
                done
                printf '\n      ]\n'
            else
                printf '      "matched_keywords": []\n'
            fi
            printf '    }'
        done
        if [[ ${#ranked[@]} -gt 0 ]]; then
            printf '\n  ]\n}\n'
        else
            printf ']\n}\n'
        fi
    else
        printf '%0.s=' {1..72}; printf '\n'
        printf 'SKILL RECOMMENDER FOR NEXT SESSION\n'
        printf '%0.s=' {1..72}; printf '\n\n'
        printf 'Skills recommended: %s\n\n' "${#ranked[@]}"
        if [[ ${#ranked[@]} -eq 0 ]]; then
            printf 'No skill signals detected. Next session may not need a specific skill.\n'
        else
            local row hits_n idx kw_preview
            local -a kws
            for ((i = 0; i < ${#ranked[@]}; i++)); do
                row="${ranked[${i}]}"
                hits_n="${row%%$'\t'*}"; row="${row#*$'\t'}"
                row="${row#*$'\t'}"
                idx="${row%%$'\t'*}"; row="${row#*$'\t'}"
                IFS=$'\x1f' read -r -a kws <<< "${row}"
                kw_preview="$(printf '%s, ' "${kws[@]}")"
                kw_preview="${kw_preview%, }"
                printf '  [%s] %-30s (matched %sx: %s)\n' \
                    "$((i + 1))" "${SKILL_NAMES[${idx}]}" "${hits_n}" "${kw_preview}"
                printf '      %s\n\n' "${SKILL_RATIONALES[${idx}]}"
            done
        fi
    fi
}

main "$@"
