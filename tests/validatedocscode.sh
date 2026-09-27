#!/usr/bin/env bs
# shellcheck shell=bash
# tests/validatedocscode.sh — docs code snippet consistency checker
# tests/validatedocscode.sh — проверка согласованности сниппетов кода в документации
#
# Проверяет bash-сниппеты в README.md, documentation/ и examples/*.md:
#   A. пути `load "..."` существуют (core/X.sh, lib/X/Y.sh)
#   B. каждый вызов module::func существует в загруженных модулях
#   C. в сниппетах `#!/usr/bin/env bs` нет избыточного set -euo pipefail / IFS
#   D. нет прямого source модулей фреймворка вместо load
#   E. сниппет, ссылающийся на examples/X.sh, совпадает с реальным файлом
#      (без учёта комментариев, пустых строк и финального guard-блока)
#
# Checks bash snippets in README.md, documentation/ and examples/*.md:
#   A. `load "..."` paths resolve (core/X.sh, lib/X/Y.sh)
#   B. every module::func call exists in the loaded modules
#   C. `#!/usr/bin/env bs` snippets carry no redundant set -euo pipefail / IFS
#   D. no direct source of framework modules instead of load
#   E. a snippet referencing examples/X.sh matches the real file
#      (ignoring comments, blank lines and the trailing guard block)
#
# Exit codes / Коды выхода:
#   0 — нет находок / no findings
#   1 — есть находки / findings exist

set -euo pipefail

# Корень проекта от расположения скрипта: проверка работает из любого каталога
# Project root from the script location: validation works from any directory
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${BS_PROJECT_ROOT}"
shopt -s globstar

# Общий фреймворк: print_header, цвета и гейт NO_COLOR / TERM=dumb / не-tty
# Shared framework: print_header, colors and the NO_COLOR / TERM=dumb / non-tty gate
source "${SCRIPT_DIR}/testframework.sh"

# Модули, автозагружаемые точкой входа (bootstrap/init.sh)
# Modules auto-loaded by the entry point (bootstrap/init.sh)
readonly AUTO_LOADED=(core/prereq core/lang core/const core/logger core/errorhandler core/version core/utils core/config core/deps)

declare -gA KNOWN_FUNCS=()
declare -gA FULL_FUNCS=()
declare -gi FINDINGS=0
declare -gi BLOCKS=0

# @description Сообщить о находке / Report a finding
report() {
    local -r file="$1" line="$2" sev="$3" msg="$4"
    FINDINGS=$(( FINDINGS + 1 ))
    local color="${YELLOW}"
    [[ "${sev}" == "ERROR" ]] && color="${RED}"
    echo -e "${color}✗ ${file}:${line} [${sev}] ${msg}${NC}"
}

# @description Добавить в KNOWN_FUNCS все определения функций файла
# @description Add every function definition of a file to KNOWN_FUNCS
index_module() {
    local -r file="$1"
    [[ -f "${file}" ]] || return 1
    local name
    while IFS= read -r name; do
        [[ -n "${name}" ]] && KNOWN_FUNCS["${name}"]=1
    done < <(grep -E '^[a-zA-Z_][a-zA-Z0-9_:]*[[:space:]]*\(\s*\)?[[:space:]]*\{' "${file}" | sed -E 's/^([a-zA-Z_][a-zA-Z0-9_:]*).*/\1/')
    return 0
}

# @description Нормализация кода: комментарии, пустые строки, guard-блок
# @description Normalize code: comments, blank lines, guard block
normalize_code() {
    local -r file="$1"
    awk '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*$/ { next }
        /^if \[\[ -n "\$\{BASH_EXECUTION_STRING/ { in_guard=1; next }
        /^if \[\[ -n "\$\{BASH_SOURCE/ { in_guard=1; next }
        in_guard == 1 && /^fi[[:space:]]*$/ { in_guard=0; next }
        in_guard == 1 { next }
        /^main\(\)[[:space:]]*\{/ { next }
        /^main[[:space:]]+"\$@"/ { next }
        /^\}[[:space:]]*$/ { next }
        {
            sub(/^[[:space:]]+/, "")
            sub(/[[:space:]]+$/, "")
            print
        }
    ' "${file}"
}

# @description Проверить один bash-блок кода / Check one bash code block
check_block() {
    local -r file="$1" start="$2" end="$3"
    local block_lines=()
    mapfile -t block_lines < <(sed -n "$((start + 1)),$((end - 1))p" "${file}")

    local block=""
    printf -v block '%s\n' "${block_lines[@]}"

    # Без shebang — фрагмент, проверяем только load и вызовы API
    # No shebang — a fragment; only load and API calls are checked
    local is_bs_shebang=0
    if [[ "${block_lines[0]:-}" == "#!/usr/bin/env bs" ]]; then
        is_bs_shebang=1
    fi

    # Шаблоны тестовых файлов: сами включают строгий режим и source'ят
    # testframework/bootstrap — это точки входа, для них C и D не действуют
    # Test-file templates: they enable strict mode and source testframework/
    # bootstrap themselves — they are entry points, C and D do not apply
    local is_test_template=0
    if printf '%s\n' "${block_lines[@]}" | grep -qE 'source .*(testframework\.sh|bootstrap/init\.sh)'; then
        is_test_template=1
    fi

    # A. Пути load / Load paths
    local load_path
    while IFS= read -r load_path; do
        [[ -z "${load_path}" ]] && continue
        if [[ ! -f "${BS_PROJECT_ROOT}/${load_path}.sh" ]]; then
            report "${file}" "${start}" "ERROR" "load \"${load_path}\" does not resolve to ${load_path}.sh"
        else
            index_module "${BS_PROJECT_ROOT}/${load_path}.sh"
        fi
    done < <(printf '%s\n' "${block_lines[@]}" | sed -nE 's/^[[:space:]]*load "([^"]+)".*/\1/p')

    # Модули, загруженные в REPL-транскрипте / Modules loaded in a REPL transcript
    while IFS= read -r load_path; do
        [[ -z "${load_path}" ]] && continue
        index_module "${BS_PROJECT_ROOT}/${load_path}.sh" || true
    done < <(printf '%s\n' "${block_lines[@]}" | sed -nE 's/^[[:space:]]*:load[[:space:]]+([a-z_/]+).*/\1/p')

    # Справочные списки имён и REPL-транскрипты: это не исполняемый код,
    # проверка вызовов API к ним не применяется
    # Reference name lists and REPL transcripts: not executable code,
    # the API-call check does not apply to them
    local -i name_only_lines=0 total_lines=0
    local is_repl=0 line_no=0
    for line_no in "${!block_lines[@]}"; do
        local l="${block_lines[${line_no}]}"
        if [[ -n "${l}" ]]; then
            total_lines=$(( total_lines + 1 ))
        fi
        if [[ "${l}" =~ ^bs\>|^bs[[:space:]]+repl ]]; then
            is_repl=1
        fi
        if [[ "${l}" =~ ^[a-z_][a-z0-9_]*(::[a-z_][a-z0-9_]*)+([[:space:]]+#.*)?$ ]]; then
            name_only_lines=$(( name_only_lines + 1 ))
        fi
    done
    local is_reference_list=0
    if (( total_lines > 0 )) && (( name_only_lines * 10 >= total_lines * 6 )); then
        is_reference_list=1
    fi

    # B. Функции из source-файлов блока / Functions from files sourced in the block
    local src_file
    while IFS= read -r src_file; do
        [[ -z "${src_file}" ]] && continue
        src_file="${src_file//\$\{TEST_SCRIPT_DIR\}/tests/unit}"
        src_file="${src_file//\$\{BS_PROJECT_ROOT\}/}"
        src_file="${src_file//\$\{BS_ROOT\}/}"
        src_file="$(realpath -m --relative-to="${BS_PROJECT_ROOT}" "${BS_PROJECT_ROOT}/${src_file}" 2>/dev/null || printf '%s' "${src_file}")"
        if [[ "${src_file}" =~ ^tests/ ]] && [[ -f "${BS_PROJECT_ROOT}/${src_file}" ]]; then
            index_module "${BS_PROJECT_ROOT}/${src_file}"
        fi
    done < <(printf '%s\n' "${block_lines[@]}" | sed -nE 's/^[[:space:]]*source "([^"]+)".*/\1/p')

    # C. Избыточный строгий режим / Redundant strict mode
    if (( is_bs_shebang == 1 )) && (( is_test_template == 0 )); then
        local line_no=0
        for line_no in "${!block_lines[@]}"; do
            local l="${block_lines[${line_no}]}"
            [[ "${l}" =~ ^[[:space:]]*# ]] && continue
            if [[ "${l}" == *"set -euo pipefail"* ]] || [[ "${l}" =~ set[[:space:]]+-[euo]+[[:space:]]+pipefail ]]; then
                report "${file}" "$((start + 1 + line_no))" "WARN" "set -euo pipefail is redundant: the bs interpreter enables strict mode before sourcing"
            fi
            if [[ "${l}" =~ ^[[:space:]]*IFS= ]]; then
                report "${file}" "$((start + 1 + line_no))" "WARN" "IFS assignment is redundant: the bs interpreter sets a safe IFS"
            fi
            # D. Прямой source модуля / Direct source of a framework module
            if [[ "${l}" =~ source[[:space:]]+[^[:space:]]*(core|lib|bootstrap)/ ]]; then
                report "${file}" "$((start + 1 + line_no))" "ERROR" "use load instead of sourcing a framework module directly"
            fi
        done
    fi

    # B. Вызовы API / API calls
    local token
    local -A defined_here=()
    local line_no=0
    if (( is_reference_list == 0 )) && (( is_repl == 0 )); then
        for line_no in "${!block_lines[@]}"; do
        local l="${block_lines[${line_no}]}"
        [[ "${l}" =~ ^[[:space:]]*# ]] && continue
        if [[ "${l}" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_:]*)[[:space:]]*\(\) ]]; then
            defined_here["${BASH_REMATCH[1]}"]=1
            continue
        fi
        while IFS= read -r token; do
            [[ -z "${token}" ]] && continue
            if [[ -z "${KNOWN_FUNCS["${token}"]:-}" ]] && [[ -z "${defined_here["${token}"]:-}" ]] && [[ -z "${FULL_FUNCS["${token}"]:-}" ]]; then
                report "${file}" "$((start + 1 + line_no))" "WARN" "unknown function: ${token}"
            fi
        done < <(printf '%s\n' "${l}" | grep -oE '[a-z_][a-z0-9_]*(::[a-z_][a-z0-9_]*)+' || true)
        done
    fi

    # E. Совпадение с реальным файлом examples/ / Match with the real examples/ file
    # Сравниваем только script-блоки (shebang, load или main), не usage-блоки
    # Only script-like blocks are compared (shebang, load or main), not usage blocks
    local ref=""
    if printf '%s\n' "${block_lines[@]}" | grep -qE '^(#!/usr/bin/env (bs|bash)|[[:space:]]*load "[^"]+"|[[:space:]]*main[[:space:]]*\()'; then
        ref="$(sed -n "$((start - 3)),${start}p" "${file}" | grep -oE 'examples/[a-zA-Z0-9_./-]+\.sh' | head -1 || true)"
        [[ -z "${ref}" ]] && ref="$(printf '%s\n' "${block_lines[0]:-}" | grep -oE 'examples/[a-zA-Z0-9_./-]+\.sh' | head -1 || true)"
    fi
    if [[ -n "${ref}" ]] && [[ -f "${BS_PROJECT_ROOT}/${ref}" ]]; then
        local norm_file norm_block
        norm_file="$(normalize_code "${BS_PROJECT_ROOT}/${ref}")"
        norm_block="$(printf '%s\n' "${block_lines[@]}" | normalize_code /dev/stdin)"
        if [[ "${norm_file}" != "${norm_block}" ]]; then
            # Выдержка: строки блока идут в том же порядке, что в файле →
            # допустимо (пропуск строк/комментариев, упрощение)
            # Excerpt: block lines appear in the same order as in the file →
            # acceptable (omitted lines/comments, simplification)
            local -a file_lines=()
            local -a block_lines_norm=()
            mapfile -t file_lines < <(normalize_code "${BS_PROJECT_ROOT}/${ref}")
            mapfile -t block_lines_norm < <(printf '%s\n' "${block_lines[@]}" | normalize_code /dev/stdin)
            local -i pos=0
            local -i ok=1 bl=0
            for (( bl = 0; bl < ${#block_lines_norm[@]}; bl++ )); do
                local -i found=0
                while (( pos < ${#file_lines[@]} )); do
                    if [[ "${file_lines[${pos}]}" == "${block_lines_norm[${bl}]}" ]]; then
                        found=1
                        pos=$(( pos + 1 ))
                        break
                    fi
                    pos=$(( pos + 1 ))
                done
                if (( found == 0 )); then
                    ok=0
                    break
                fi
            done
            if (( ok == 0 )); then
                report "${file}" "${start}" "ERROR" "snippet does not match ${ref} (comments/blank/guard ignored)"
            fi
        fi
    fi
}

# Основная функция
main() {
    print_header "Docs Code Snippet Validation / Проверка сниппетов кода в документации"

    # Индексируем автозагружаемые модули / Index auto-loaded modules
    local m
    for m in "${AUTO_LOADED[@]}"; do
        index_module "${BS_PROJECT_ROOT}/${m}.sh" || true
    done
    index_module "${BS_PROJECT_ROOT}/bootstrap/bs.sh" || true

    # Полный индекс фреймворка: функции модулей, описанных в справочниках
    # Full framework index: functions of modules described in reference docs
    local mod_file
    while IFS= read -r mod_file; do
        local name
        while IFS= read -r name; do
            [[ -n "${name}" ]] && FULL_FUNCS["${name}"]=1
        done < <(grep -E '^[a-zA-Z_][a-zA-Z0-9_:]*[[:space:]]*\(\s*\)?[[:space:]]*\{' "${mod_file}" | sed -E 's/^([a-zA-Z_][a-zA-Z0-9_:]*).*/\1/')
    done < <(find core lib -name '*.sh' -type f | sort)

    local doc
    while IFS= read -r doc; do
        [[ -f "${doc}" ]] || continue
        local fence
        while IFS= read -r fence; do
            local line="${fence%% *}"
            local lang="${fence#* }"
            if [[ "${lang}" != "bash" ]]; then
                continue
            fi
            # Ищем закрывающий fence / Find the closing fence
            local end_line=""
            end_line="$(awk -v n="${line}" 'NR > n && /^```/ { print NR; exit }' "${doc}")"
            [[ -z "${end_line}" ]] && continue
            BLOCKS=$(( BLOCKS + 1 ))
            check_block "${doc}" "${line}" "${end_line}"
        done < <(awk '/^```/{ print NR " " substr($0,4) }' "${doc}")
    done < <(printf '%s\n' README.md documentation/**/*.md examples/*.md 2>/dev/null | sort -u)

    echo
    echo -e "${YELLOW}Blocks checked / Сниппетов проверено: ${BLOCKS}${NC}"
    if (( FINDINGS > 0 )); then
        echo -e "${RED}✗ ${FINDINGS} finding(s) / находок: ${FINDINGS}${NC}"
        return 1
    fi
    echo -e "${GREEN}✓ No findings / Находок нет${NC}"
    return 0
}

main "$@"