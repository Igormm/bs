#!/usr/bin/env bs
#
# core/args.sh — модуль объявления и валидации параметров скриптов BS
# core/args.sh — script parameter declaration and validation module for BS
#
# Позволяет объявить дерево допустимых параметров один раз, а валидацию,
# сообщения об ошибках и help получить автоматически — из того же дерева.
# Declare the tree of allowed parameters once, and get validation,
# error messages and help automatically — from the same tree.
#
# Использование / Usage:
#   load "core/args"
#
#   # Линейная цепочка: myscript first middle last
#   # Linear chain: myscript first middle last
#   args::define first middle last
#
#   # Ветвление: на уровне 1 можно start ИЛИ stop
#   # Branching: level 1 accepts start OR stop
#   args::level 1 start stop
#
#   args::describe first "First stage of the pipeline"
#
#   args::parse "$@" || exit $?
#   stage="$(args::get 1)"
#
# Поведение args::parse:
#   - неизвестный параметр → ошибка + help, код возврата E_INVALID
#   - параметр есть в дереве, но не на этом уровне → ошибка + help, E_INVALID
#   - параметров больше, чем уровней в дереве → ошибка + help, E_INVALID
#   - -h/--help → help в stdout, код 0, ARGS_HELP_REQUESTED=1
# args::parse behaviour:
#   - unknown parameter → error + help, return code E_INVALID
#   - parameter exists in the tree but at another level → error + help, E_INVALID
#   - more parameters than tree levels → error + help, E_INVALID
#   - -h/--help → help to stdout, code 0, ARGS_HELP_REQUESTED=1
#
# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points

# Source Guard / Защита от повторной загрузки
[[ -n "${__ARGS_SOURCED:-}" ]] && return 0
readonly __ARGS_SOURCED=1

# Подключаем core, если логгер ещё не загружен
# Source core if the logger is not loaded yet
if ! declare -F log::info >/dev/null 2>&1; then
    if [[ -n "${BS_HOME:-}" ]]; then
        source "${BS_HOME}/core/const.sh"
        source "${BS_HOME}/core/logger.sh"
    elif [[ -n "${BS_ROOT:-}" ]]; then
        source "${BS_ROOT}/core/const.sh"
        source "${BS_ROOT}/core/logger.sh"
    fi
fi

# Версия модуля / Module version
declare -g ARGS_VERSION="1.0.0"

# ==========================================
# Состояние модуля / Module state
# ==========================================

# Дерево параметров: уровень (1-based) → список допустимых имён через пробел
# Parameter tree: level (1-based) → space-separated list of allowed names
declare -g -A __ARGS_TREE=()

# Описания параметров для help: имя → текст
# Parameter descriptions for help: name → text
declare -g -A __ARGS_DESCRIPTIONS=()

# Провалидированные параметры после args::parse
# Validated parameters after args::parse
declare -g -a ARGS_PARAMS=()

# Флаг запроса help (-h/--help) / Help request flag (-h/--help)
declare -g ARGS_HELP_REQUESTED=0

# Объявленные флаги: имя (без --) → тип ("bool" или "value")
# Declared flags: name (without --) → type ("bool" or "value")
declare -g -A __ARGS_FLAGS=()

# Описания флагов для help: имя → текст
# Flag descriptions for help: name → text
declare -g -A __ARGS_FLAG_DESCRIPTIONS=()

# Провалидированные флаги после args::parse: имя → значение ("1" для bool)
# Validated flags after args::parse: name → value ("1" for bool)
declare -g -A ARGS_FLAGS=()

# ==========================================
# Приватные вспомогательные функции / Private helper functions
# ==========================================

# @private
# @description Найти уровень параметра в дереве
# @description Find the level of a parameter in the tree
# @param $1 Parameter name / Имя параметра
# @return Prints level number or empty string / Выводит номер уровня или пустую строку
args::__level_of() {
    local name="${1}"
    local level

    for level in "${!__ARGS_TREE[@]}"; do
        local item
        # Список разбираем по пробелам независимо от IFS вызывающего
        # Split the list on spaces regardless of the caller's IFS
        local IFS=' '
        for item in ${__ARGS_TREE["${level}"]}; do
            if [[ "${item}" == "${name}" ]]; then
                printf '%s\n' "${level}"
                return "${E_SUCCESS:-0}"
            fi
        done
    done
    printf '\n'
}

# @private
# @description Проверить, допустимо ли имя на данном уровне
# @description Check if a name is allowed at the given level
# @param $1 Level number / Номер уровня
# @param $2 Parameter name / Имя параметра
# @return 0 if allowed, 1 otherwise / 0 если допустимо, иначе 1
args::__is_allowed_at() {
    local level="${1}"
    local name="${2}"

    [[ -z "${__ARGS_TREE["${level}"]:-}" ]] && return "${E_ERROR:-1}"

    local item
    local IFS=' '
    for item in ${__ARGS_TREE["${level}"]}; do
        [[ "${item}" == "${name}" ]] && return "${E_SUCCESS:-0}"
    done
    return "${E_ERROR:-1}"
}

# ==========================================
# Объявление дерева / Tree declaration
# ==========================================

# @description Сбросить дерево параметров и описания (для повторного объявления)
# @description Reset the parameter tree and descriptions (for re-declaration)
# @example
#   args::reset
args::reset() {
    __ARGS_TREE=()
    __ARGS_DESCRIPTIONS=()
    __ARGS_FLAGS=()
    __ARGS_FLAG_DESCRIPTIONS=()
    ARGS_PARAMS=()
    ARGS_FLAGS=()
    ARGS_HELP_REQUESTED=0
}

# @description Объявить линейную цепочку параметров:
#   первое имя — уровень 1, второе — уровень 2 и т.д.
#   Аналог parameters("first", "middle", "last")
# @description Declare a linear parameter chain:
#   first name — level 1, second — level 2, etc.
#   Equivalent of parameters("first", "middle", "last")
# @param $@ Parameter names in order / Имена параметров по порядку
# @example
#   args::define first middle last
args::define() {
    if [[ $# -eq 0 ]]; then
        log::warn "args::define: at least one parameter name is required"
        return "${E_ERROR:-1}"
    fi

    local level=1
    local name
    for name in "$@"; do
        args::level "${level}" "${name}" || return "${E_ERROR:-1}"
        ((++level))
    done
}

# @description Объявить допустимые значения уровня (ветвление дерева):
#   на одном уровне может быть несколько альтернатив
# @description Declare allowed values for a level (tree branching):
#   one level may hold several alternatives
# @param $1 Level number (1-based) / Номер уровня (с 1)
# @param $@ Parameter names allowed at this level / Имена, допустимые на уровне
# @example
#   args::level 1 start stop status
args::level() {
    local level="${1:-}"
    shift $(( $# > 0 ? 1 : 0 ))

    if [[ -z "${level}" ]] || ! [[ "${level}" =~ ^[0-9]+$ ]] || [[ "${level}" -eq 0 ]]; then
        log::warn "args::level: level must be a positive integer, got: ${level}"
        return "${E_ERROR:-1}"
    fi
    if [[ $# -eq 0 ]]; then
        log::warn "args::level: at least one parameter name is required"
        return "${E_ERROR:-1}"
    fi

    local name
    for name in "$@"; do
        if [[ -z "${name}" ]]; then
            log::warn "args::level: empty parameter name at level ${level}"
            return "${E_ERROR:-1}"
        fi
        if args::__is_allowed_at "${level}" "${name}"; then
            continue  # Уже объявлен / Already declared
        fi
        if [[ -n "${__ARGS_TREE["${level}"]:-}" ]]; then
            __ARGS_TREE["${level}"]+=" ${name}"
        else
            __ARGS_TREE["${level}"]="${name}"
        fi
    done
}

# @description Задать описание параметра для help-сообщения
# @description Set a parameter description for the help message
# @param $1 Parameter name / Имя параметра
# @param $2 Description text / Текст описания
# @example
#   args::describe start "Start the service immediately"
args::describe() {
    # Параметры могут быть не переданы: значения по умолчанию для set -u
    # Parameters may be omitted: defaults for set -u
    local name="${1:-}"
    local text="${2:-}"

    if [[ -z "${name}" ]]; then
        log::warn "args::describe: parameter name not specified"
        return "${E_ERROR:-1}"
    fi
    __ARGS_DESCRIPTIONS["${name}"]="${text}"
}

# ==========================================
# Флаги (--key value) / Flags (--key value)
# ==========================================

# @description Объявить флаг командной строки
#   bool-флаг не требует значения (--verbose), value-флаг требует (--output file)
#   Флаги не занимают позиционные уровни дерева
# @description Declare a command line flag
#   A bool flag takes no value (--verbose), a value flag requires one (--output file)
#   Flags do not occupy positional tree levels
# @param $1 Flag name (with or without --) / Имя флага (с -- или без)
# @param $2 [optional] Type: "bool" (default) or "value" / [опционально] Тип: "bool" (по умолчанию) или "value"
# @example
#   args::flag verbose
#   args::flag output value
args::flag() {
    local name="${1:-}"
    local type="${2:-bool}"

    # Убираем префикс --, если передан / Strip the -- prefix if given
    name="${name#--}"

    if [[ -z "${name}" ]]; then
        log::warn "args::flag: flag name not specified"
        return "${E_ERROR:-1}"
    fi
    if [[ "${type}" != "bool" ]] && [[ "${type}" != "value" ]]; then
        log::warn "args::flag: type must be 'bool' or 'value', got: ${type}"
        return "${E_ERROR:-1}"
    fi

    __ARGS_FLAGS["${name}"]="${type}"
}

# @description Задать описание флага для help-сообщения
# @description Set a flag description for the help message
# @param $1 Flag name (with or without --) / Имя флага (с -- или без)
# @param $2 Description text / Текст описания
# @example
#   args::flag_describe output "Write the report to this file"
args::flag_describe() {
    local name="${1:-}"
    local text="${2:-}"

    name="${name#--}"

    if [[ -z "${name}" ]]; then
        log::warn "args::flag_describe: flag name not specified"
        return "${E_ERROR:-1}"
    fi
    __ARGS_FLAG_DESCRIPTIONS["${name}"]="${text}"
}

# @description Получить значение флага после args::parse
# @description Get a flag value after args::parse
# @param $1 Flag name (with or without --) / Имя флага (с -- или без)
# @return Prints the value; 1 if flag not set / Выводит значение; 1 если флаг не задан
# @example
#   report_file="$(args::flag_get output)"
args::flag_get() {
    local name="${1:-}"

    name="${name#--}"

    local value="${ARGS_FLAGS["${name}"]:-}"
    if [[ -z "${value}" ]]; then
        return "${E_ERROR:-1}"
    fi
    printf '%s\n' "${value}"
}

# ==========================================
# Help / Справка
# ==========================================

# @description Вывести help, сгенерированный из дерева параметров
#   Help никогда не расходится с валидацией — это тот же источник данных
# @description Print help generated from the parameter tree
#   Help never diverges from validation — it is the same data source
# @param $1 [optional] Program name (default: $0 basename) / [опционально] Имя программы
# @example
#   args::help "deploy.sh"
args::help() {
    local prog="${1:-${0##*/}}"

    if [[ ${#__ARGS_TREE[@]} -eq 0 ]] && [[ ${#__ARGS_FLAGS[@]} -eq 0 ]]; then
        printf 'Usage: %s\n' "${prog}"
        printf '(no parameters declared / параметры не объявлены)\n'
        return "${E_SUCCESS:-0}"
    fi

    # Собираем usage-строку по уровням / Build the usage line by levels
    local usage="Usage: ${prog}"

    # Флаги в usage-строке / Flags in the usage line
    if [[ ${#__ARGS_FLAGS[@]} -gt 0 ]]; then
        usage+=" [flags]"
    fi

    local level
    local max_level=0
    for level in "${!__ARGS_TREE[@]}"; do
        [[ "${level}" -gt "${max_level}" ]] && max_level="${level}"
    done

    local item
    for ((level = 1; level <= max_level; level++)); do
        if [[ -n "${__ARGS_TREE["${level}"]:-}" ]]; then
            local IFS=' '
            local choices=""
            for item in ${__ARGS_TREE["${level}"]}; do
                if [[ -n "${choices}" ]]; then
                    choices+="|${item}"
                else
                    choices="${item}"
                fi
            done
            usage+=" [${choices}]"
        fi
    done
    printf '%s\n' "${usage}"

    if [[ ${#__ARGS_TREE[@]} -gt 0 ]]; then
        printf '\nParameters / Параметры:\n'

        for ((level = 1; level <= max_level; level++)); do
            [[ -z "${__ARGS_TREE["${level}"]:-}" ]] && continue
            printf '  level %d: %s\n' "${level}" "${__ARGS_TREE[${level}]// / | }"
            local IFS=' '
            for item in ${__ARGS_TREE["${level}"]}; do
                if [[ -n "${__ARGS_DESCRIPTIONS["${item}"]:-}" ]]; then
                    printf '    %-16s — %s\n' "${item}" "${__ARGS_DESCRIPTIONS["${item}"]}"
                fi
            done
        done
    fi

    # Секция флагов / Flags section
    if [[ ${#__ARGS_FLAGS[@]} -gt 0 ]]; then
        printf '\nFlags / Флаги:\n'
        local flag_name
        # Итерация по отсортированным именам через read:
        # word splitting $() сломался бы при IFS=' ' из цикла уровней выше
        # Iterating sorted names via read:
        # $() word splitting would break under IFS=' ' from the level loop above
        while IFS= read -r flag_name; do
            local flag_label="--${flag_name}"
            if [[ "${__ARGS_FLAGS["${flag_name}"]:-}" == "value" ]]; then
                flag_label="--${flag_name} <value>"
            fi
            if [[ -n "${__ARGS_FLAG_DESCRIPTIONS["${flag_name}"]:-}" ]]; then
                printf '    %-22s — %s\n' "${flag_label}" "${__ARGS_FLAG_DESCRIPTIONS["${flag_name}"]}"
            else
                printf '    %s\n' "${flag_label}"
            fi
        done < <(printf '%s\n' "${!__ARGS_FLAGS[@]}" | sort)
        printf '    %-22s — %s\n' "--help" "Show this help and exit"
    fi
}

# ==========================================
# Валидация / Validation
# ==========================================

# @description Проверить входные параметры скрипта по дереву
#   Успех: заполняет массив ARGS_PARAMS, возвращает 0
#   Ошибка: печатает причину и help в stderr, возвращает E_INVALID
# @description Validate the script input parameters against the tree
#   Success: fills the ARGS_PARAMS array, returns 0
#   Error: prints the reason and help to stderr, returns E_INVALID
# @param $@ Script parameters (обычно "$@") / Script parameters (usually "$@")
# @return 0 on success, E_INVALID on validation error / 0 при успехе, E_INVALID при ошибке
# @example
#   args::parse "$@" || exit $?
args::parse() {
    ARGS_PARAMS=()
    ARGS_FLAGS=()
    ARGS_HELP_REQUESTED=0

    # Запрос help / Help request
    if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
        ARGS_HELP_REQUESTED=1
        args::help
        return "${E_SUCCESS:-0}"
    fi

    if [[ ${#__ARGS_TREE[@]} -eq 0 ]] && [[ ${#__ARGS_FLAGS[@]} -eq 0 ]]; then
        log::error "args::parse: parameter tree is empty, call args::define, args::level or args::flag first" >&2
        return "${E_ERROR:-1}"
    fi

    local max_level=0
    local level
    for level in "${!__ARGS_TREE[@]}"; do
        [[ "${level}" -gt "${max_level}" ]] && max_level="${level}"
    done

    local -a argv=("$@")
    local argc=${#argv[@]}
    local position=0
    local i=0

    while [[ ${i} -lt ${argc} ]]; do
        local param="${argv[i]}"

        # Флаги: --name, --name value, --name=value
        # Flags: --name, --name value, --name=value
        if [[ "${param}" == --* ]]; then
            local flag_spec="${param#--}"
            local flag_name="${flag_spec%%=*}"
            local inline_value=""
            local has_inline="false"
            if [[ "${flag_spec}" == *=* ]]; then
                inline_value="${flag_spec#*=}"
                has_inline="true"
            fi

            # Неизвестный флаг / Unknown flag
            if [[ -z "${__ARGS_FLAGS["${flag_name}"]:-}" ]]; then
                printf 'ERROR: unknown flag: "--%s"\n' "${flag_name}" >&2
                args::help >&2
                return "${E_INVALID:-2}"
            fi

            if [[ "${__ARGS_FLAGS["${flag_name}"]}" == "value" ]]; then
                # Флаг со значением: --name=value или --name value
                # Value flag: --name=value or --name value
                if [[ "${has_inline}" == "true" ]]; then
                    ARGS_FLAGS["${flag_name}"]="${inline_value}"
                else
                    ((++i))
                    if [[ ${i} -ge ${argc} ]]; then
                        printf 'ERROR: flag "--%s" requires a value\n' "${flag_name}" >&2
                        args::help >&2
                        return "${E_INVALID:-2}"
                    fi
                    ARGS_FLAGS["${flag_name}"]="${argv[i]}"
                fi
            else
                # bool-флаг не принимает значение / bool flag takes no value
                if [[ "${has_inline}" == "true" ]]; then
                    printf 'ERROR: flag "--%s" does not take a value\n' "${flag_name}" >&2
                    args::help >&2
                    return "${E_INVALID:-2}"
                fi
                ARGS_FLAGS["${flag_name}"]=1
            fi

            ((++i))
            continue
        fi

        # Позиционный параметр / Positional parameter
        ((++position))

        # Параметров больше, чем уровней в дереве
        # More parameters than tree levels
        if [[ "${position}" -gt "${max_level}" ]]; then
            printf 'ERROR: too many parameters: "%s" is beyond level %d\n' \
                "${param}" "${max_level}" >&2
            args::help >&2
            return "${E_INVALID:-2}"
        fi

        # Параметр допустим на этом уровне / Parameter allowed at this level
        if args::__is_allowed_at "${position}" "${param}"; then
            ARGS_PARAMS+=("${param}")
            ((++i))
            continue
        fi

        # Параметр есть в дереве, но на другом уровне
        # Parameter exists in the tree but at another level
        local real_level
        real_level="$(args::__level_of "${param}")"
        if [[ -n "${real_level}" ]]; then
            printf 'ERROR: parameter "%s" belongs to level %s, but was used at level %d\n' \
                "${param}" "${real_level}" "${position}" >&2
        else
            printf 'ERROR: unknown parameter: "%s"\n' "${param}" >&2
        fi
        args::help >&2
        return "${E_INVALID:-2}"
    done

    return "${E_SUCCESS:-0}"
}

# @description Получить провалидированный параметр по позиции (1-based)
# @description Get a validated parameter by position (1-based)
# @param $1 Position / Позиция
# @return Prints the value; 1 if position not set / Выводит значение; 1 если позиция пуста
# @example
#   stage="$(args::get 1)"
args::get() {
    local position="${1:-}"

    if [[ -z "${position}" ]] || ! [[ "${position}" =~ ^[0-9]+$ ]] || [[ "${position}" -eq 0 ]]; then
        log::warn "args::get: position must be a positive integer, got: ${position}"
        return "${E_ERROR:-1}"
    fi

    local value="${ARGS_PARAMS[$((position - 1))]:-}"
    if [[ -z "${value}" ]]; then
        return "${E_ERROR:-1}"
    fi
    printf '%s\n' "${value}"
}

# ==========================================
# Bash completion / Автодополнение Bash
# ==========================================

# @description Сгенерировать bash-completion функцию из дерева параметров и флагов
#   Вывод можно сохранить в файл и подключить через source или ~/.bashrc
# @description Generate a bash completion function from the parameter tree and flags
#   The output can be saved to a file and loaded via source or ~/.bashrc
# @param $1 [optional] Program name (default: $0 basename) / [опционально] Имя программы
# @example
#   args::completion "deploy.sh" > /etc/bash_completion.d/deploy.sh
#   source <(args::completion "deploy.sh")
args::completion() {
    local prog="${1:-${0##*/}}"

    if [[ ${#__ARGS_TREE[@]} -eq 0 ]] && [[ ${#__ARGS_FLAGS[@]} -eq 0 ]]; then
        log::warn "args::completion: nothing declared, call args::define, args::level or args::flag first"
        return "${E_ERROR:-1}"
    fi

    # Имя функции: только [a-zA-Z0-9_] / Function name: [a-zA-Z0-9_] only
    local func_name
    func_name="_$(printf '%s' "${prog}" | tr -c 'a-zA-Z0-9_' '_')_completion"

    # Список всех флагов для дополнения / All flags for completion
    # Итерация через read: $() word splitting зависит от IFS вызывающего
    # Iterating via read: $() word splitting depends on the caller's IFS
    local flag_words="--help"
    local flag_name
    while IFS= read -r flag_name; do
        flag_words+=" --${flag_name}"
    done < <(printf '%s\n' "${!__ARGS_FLAGS[@]}" | sort)

    # Список value-флагов (после них значение не дополняется)
    # Value flags list (their values are not completed)
    local value_flags=""
    while IFS= read -r flag_name; do
        if [[ "${__ARGS_FLAGS["${flag_name}"]:-}" == "value" ]]; then
            value_flags+=" --${flag_name}"
        fi
    done < <(printf '%s\n' "${!__ARGS_FLAGS[@]}" | sort)

    # Уровни дерева / Tree levels
    local max_level=0
    local level
    for level in "${!__ARGS_TREE[@]}"; do
        [[ "${level}" -gt "${max_level}" ]] && max_level="${level}"
    done

    cat <<EOF
# Bash completion for ${prog} — generated by core/args.sh (args::completion)
# Автодополнение Bash для ${prog} — сгенерировано core/args.sh (args::completion)
${func_name}() {
    local cur prev word positional i
    COMPREPLY=()
    cur="\${COMP_WORDS[COMP_CWORD]}"
    prev="\${COMP_WORDS[COMP_CWORD-1]}"
EOF

    # После value-флага значение не дополняем / Do not complete after a value flag
    if [[ -n "${value_flags}" ]]; then
        local IFS=' '
        local vf_patterns=""
        local vf
        for vf in ${value_flags}; do
            if [[ -n "${vf_patterns}" ]]; then
                vf_patterns+="|${vf}"
            else
                vf_patterns="${vf}"
            fi
        done
        cat <<EOF

    # value-флаги: значение не дополняется / value flags: value is not completed
    case "\${prev}" in
        ${vf_patterns}) return 0 ;;
    esac
EOF
    fi

    cat <<EOF

    # Дополнение флагов / Flag completion
    if [[ "\${cur}" == --* ]]; then
        COMPREPLY=( \$(compgen -W "${flag_words}" -- "\${cur}") )
        return 0
    fi

    # Считаем уже введённые позиционные параметры (флаги уровней не занимают)
    # Count positionals already entered (flags do not occupy levels)
    positional=0
    for ((i = 1; i < COMP_CWORD; i++)); do
        word="\${COMP_WORDS[i]}"
        case "\${word}" in
EOF

    if [[ -n "${value_flags}" ]]; then
        cat <<EOF
            ${vf_patterns}) ((++i)) ;;   # пропускаем значение value-флага / skip value flag value
EOF
    fi

    cat <<EOF
            --*) ;;                      # bool-флаг / bool flag
            *) ((++positional)) ;;
        esac
    done

    # Выбираем варианты по уровню / Choices by level
    local choices=""
    case \$((positional + 1)) in
EOF

    local item
    for ((level = 1; level <= max_level; level++)); do
        if [[ -n "${__ARGS_TREE["${level}"]:-}" ]]; then
            printf '        %d) choices="%s" ;;\n' "${level}" "${__ARGS_TREE[${level}]}"
        fi
    done

    cat <<EOF
    esac

    COMPREPLY=( \$(compgen -W "\${choices} ${flag_words}" -- "\${cur}") )
    return 0
}
complete -F ${func_name} ${prog}
EOF
}

# ==========================================
# Инициализация модуля / Module initialization
# ==========================================

# Отмечаем модуль как загруженный / Mark module as loaded
declare -g ARGS_LOADED="1"

log::debug "Args module initialized, version: ${ARGS_VERSION}" 2>/dev/null || true
