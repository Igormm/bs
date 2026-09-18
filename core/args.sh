#!/usr/bin/env bash
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

bs::guard "ARGS" || return 0

# Зависимости / Dependencies
bs::source_relative "const.sh" "logger.sh"

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

# Дефолтные значения флагов: имя → значение
# Default flag values: name → value
declare -g -A __ARGS_FLAG_DEFAULTS=()

# Валидаторы значений флагов: имя → "number" | "enum:a,b,c" | имя функции
# Flag value validators: name → "number" | "enum:a,b,c" | function name
declare -g -A __ARGS_FLAG_VALIDATORS=()

# Минимальное количество позиционных параметров (args::required)
# Minimum positional parameter count (args::required)
declare -g -i __ARGS_REQUIRED=0

# Повторяемый уровень: допустимые имена уровня повторяются без ограничений
# Variadic level: the level's allowed names may repeat unboundedly
declare -g -i __ARGS_VARIADIC_LEVEL=0

# Сырые аргументы после "--" / Raw arguments after "--"
declare -g -a ARGS_REST=()

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

    is::empty "${__ARGS_TREE["${level}"]:-}" && return "${E_ERROR:-1}"

    local item
    local IFS=' '
    for item in ${__ARGS_TREE["${level}"]}; do
        [[ "${item}" == "${name}" ]] && return "${E_SUCCESS:-0}"
    done
    return "${E_ERROR:-1}"
}

# @description Проверить значение value-флага по объявленному валидатору.
# @description Validate a value-flag value against the declared validator.
#   Validators: "number", "enum:a,b,c", or a callback function name.
#   Валидаторы: "number", "enum:a,b,c" или имя функции-колбэка.
# @param $1 Flag name (without --) / Имя флага (без --)
# @param $2 Value to check / Проверяемое значение
# @return 0 valid, 1 invalid or unknown validator
args::__validate_flag_value() {
    local -r flag="${1:-}" value="${2-}"
    local -r validator="${__ARGS_FLAG_VALIDATORS["${flag}"]:-}"
    is::empty "${validator}" && return "${E_SUCCESS:-0}"
    case "${validator}" in
        number)
            is::number "${value}" || return "${E_ERROR:-1}"
            ;;
        enum:*)
            local list="${validator#enum:}"
            local item ok=0
            local IFS=','
            for item in ${list}; do
                [[ "${item}" == "${value}" ]] && ok=1
            done
            (( ok == 1 )) || return "${E_ERROR:-1}"
            ;;
        *)
            if is::function "${validator}"; then
                "${validator}" "${value}" || return "${E_ERROR:-1}"
            else
                return "${E_ERROR:-1}"
            fi
            ;;
    esac
    return "${E_SUCCESS:-0}"
}

# @description Человекочитаемая подсказка валидатора для сообщений и help.
# @description Human-readable validator hint for messages and help.
# @param $1 Flag name (without --) / Имя флага (без --)
# @stdout hint / подсказка
args::__flag_value_hint() {
    local -r flag="${1:-}"
    local -r validator="${__ARGS_FLAG_VALIDATORS["${flag}"]:-}"
    case "${validator}" in
        number) printf 'a number\n' ;;
        enum:*) printf 'one of: %s\n' "${validator#enum:}" ;;
        *)      printf '%s\n' "${validator}" ;;
    esac
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
    __ARGS_FLAG_DEFAULTS=()
    __ARGS_FLAG_VALIDATORS=()
    ARGS_PARAMS=()
    ARGS_FLAGS=()
    ARGS_REST=()
    __ARGS_REQUIRED=0
    __ARGS_VARIADIC_LEVEL=0
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
#   на одном уровне может быть несколько альтернатив. Имя с суффиксом
#   "..." делает уровень повторяемым: допустимые имена повторяются
#   без ограничений (аналог nargs='*' в argparse).
# @description Declare allowed values for a level (tree branching):
#   one level may hold several alternatives. A name with a "..." suffix
#   makes the level variadic: its allowed names may repeat unboundedly
#   (the argparse nargs='*' analog).
# @param $1 Level number (1-based) / Номер уровня (с 1)
# @param $@ Parameter names allowed at this level / Имена, допустимые на уровне
# @example
#   args::level 1 start stop status
#   args::level 3 file...            # повторяемый уровень / variadic level
args::level() {
    local level="${1:-}"
    shift $(( $# > 0 ? 1 : 0 ))

    if is::empty "${level}" || ! [[ "${level}" =~ ^[0-9]+$ ]] || [[ "${level}" -eq 0 ]]; then
        log::warn "args::level: level must be a positive integer, got: ${level}"
        return "${E_ERROR:-1}"
    fi
    if [[ $# -eq 0 ]]; then
        log::warn "args::level: at least one parameter name is required"
        return "${E_ERROR:-1}"
    fi

    local name
    for name in "$@"; do
        if [[ "${name}" == *"..." ]]; then
            # Повторяемый уровень / Variadic level
            __ARGS_VARIADIC_LEVEL="${level}"
            name="${name%...}"
        fi
        if is::empty "${name}"; then
            log::warn "args::level: empty parameter name at level ${level}"
            return "${E_ERROR:-1}"
        fi
        if args::__is_allowed_at "${level}" "${name}"; then
            continue  # Уже объявлен / Already declared
        fi
        if is::not_empty "${__ARGS_TREE["${level}"]:-}"; then
            __ARGS_TREE["${level}"]+=" ${name}"
        else
            __ARGS_TREE["${level}"]="${name}"
        fi
    done
}

# @description Объявить минимальное количество позиционных параметров.
# @description Declare the minimum number of positional parameters.
#   args::parse fails with E_INVALID if fewer are given.
# @param $1 Minimum count, non-negative integer / Минимум, целое число >= 0
# @return 0 ok, 1 invalid count
# @example
#   args::required 2
args::required() {
    local -r count="${1:-}"
    if is::empty "${count}" || ! [[ "${count}" =~ ^[0-9]+$ ]]; then
        log::warn "args::required: count must be a non-negative integer, got: ${count}"
        return "${E_ERROR:-1}"
    fi
    __ARGS_REQUIRED="${count}"
    return "${E_SUCCESS:-0}"
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

    if is::empty "${name}"; then
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
# @param $3 [optional] Default value (value flags; also for --help display)
#        [опционально] Значение по умолчанию (для value-флагов; попадает в help)
# @param $4 [optional] Value validator: "number", "enum:a,b,c", or a callback
#        function name returning 0 for valid values
#        [опционально] Валидатор значения: "number", "enum:a,b,c" или имя
#        функции-колбэка, возвращающей 0 для допустимых значений
# @example
#   args::flag verbose
#   args::flag output value
#   args::flag env value staging "enum:staging,prod"
#   args::flag port value "" number
#   args::flag token value "" "is::not_empty"
args::flag() {
    local name="${1:-}"
    local type="${2:-bool}"
    local default="${3-}"
    local validator="${4-}"

    # Убираем префикс --, если передан / Strip the -- prefix if given
    name="${name#--}"

    if is::empty "${name}"; then
        log::warn "args::flag: flag name not specified"
        return "${E_ERROR:-1}"
    fi
    if [[ "${type}" != "bool" ]] && [[ "${type}" != "value" ]]; then
        log::warn "args::flag: type must be 'bool' or 'value', got: ${type}"
        return "${E_ERROR:-1}"
    fi

    __ARGS_FLAGS["${name}"]="${type}"
    # Пустая строка дефолта означает "дефолта нет" / Empty default = no default
    if (( $# >= 3 )) && is::not_empty "${default}"; then
        __ARGS_FLAG_DEFAULTS["${name}"]="${default}"
    fi
    if (( $# >= 4 )); then
        __ARGS_FLAG_VALIDATORS["${name}"]="${validator}"
    fi
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

    if is::empty "${name}"; then
        log::warn "args::flag_describe: flag name not specified"
        return "${E_ERROR:-1}"
    fi
    __ARGS_FLAG_DESCRIPTIONS["${name}"]="${text}"
}

# @description Получить значение флага после args::parse
#   Если флаг не задан на командной строке, возвращается объявленный
#   дефолт (args::flag NAME value DEFAULT); без дефолта — ошибка.
# @description Get a flag value after args::parse
#   If the flag was not set on the command line, the declared default is
#   returned (args::flag NAME value DEFAULT); without a default — error.
# @param $1 Flag name (with or without --) / Имя флага (с -- или без)
# @return Prints the value; 1 if flag not set and no default declared
#   Выводит значение; 1 если флаг не задан и дефолт не объявлен
# @example
#   report_file="$(args::flag_get output)"
args::flag_get() {
    local name="${1:-}"

    name="${name#--}"

    local value="${ARGS_FLAGS["${name}"]:-}"
    if is::empty "${value}"; then
        # Объявленный дефолт / Declared default
        if [[ -v __ARGS_FLAG_DEFAULTS["${name}"] ]]; then
            printf '%s\n' "${__ARGS_FLAG_DEFAULTS["${name}"]}"
            return "${E_SUCCESS:-0}"
        fi
        return "${E_ERROR:-1}"
    fi
    printf '%s\n' "${value}"
}

# @description Предикат: флаг был задан на командной строке.
# @description Predicate: the flag was set on the command line.
#   False when only the default was declared — use args::flag_get for that.
#   Ложь, если задан только дефолт — для дефолта используйте args::flag_get.
# @param $1 Flag name (with or without --) / Имя флага (с -- или без)
# @return 0 set on the command line, 1 not set
# @example
#   if args::flag_is_set dry-run; then ...
args::flag_is_set() {
    local name="${1:-}"
    name="${name#--}"
    [[ -v ARGS_FLAGS["${name}"] ]]
}

# @description Предикат: позиционный параметр задан (Python: len check).
# @description Predicate: the positional parameter is set.
# @param $1 Position (1-based) / Позиция (с 1)
# @return 0 set, 1 not set or invalid position
# @example
#   if args::has 2; then ...
args::has() {
    local -r position="${1:-}"
    if is::empty "${position}" || ! [[ "${position}" =~ ^[0-9]+$ ]] || [[ "${position}" -eq 0 ]]; then
        return "${E_ERROR:-1}"
    fi
    [[ -n "${ARGS_PARAMS[$((position - 1))]:-}" ]]
}

# @description Сырые аргументы после "--", построчно.
# @description Raw arguments after "--", one per line.
#   The full array is also exposed as ARGS_REST.
# @stdout rest arguments / сырые аргументы
# @example
#   while IFS= read -r raw; do printf '%s\n' "${raw}"; done < <(args::rest)
args::rest() {
    if (( ${#ARGS_REST[@]} > 0 )); then
        printf '%s\n' "${ARGS_REST[@]}"
    fi
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
        if is::not_empty "${__ARGS_TREE["${level}"]:-}"; then
            local IFS=' '
            local choices=""
            for item in ${__ARGS_TREE["${level}"]}; do
                if is::not_empty "${choices}"; then
                    choices+="|${item}"
                else
                    choices="${item}"
                fi
            done
            # Повторяемый уровень: суффикс ... / Variadic level: ... suffix
            if (( __ARGS_VARIADIC_LEVEL == level )); then
                choices+="..."
            fi
            usage+=" [${choices}]"
        fi
    done
    printf '%s\n' "${usage}"

    if [[ ${#__ARGS_TREE[@]} -gt 0 ]]; then
        printf '\nParameters / Параметры:\n'

        for ((level = 1; level <= max_level; level++)); do
            is::empty "${__ARGS_TREE["${level}"]:-}" && continue
            printf '  level %d: %s\n' "${level}" "${__ARGS_TREE[${level}]// / | }"
            local IFS=' '
            for item in ${__ARGS_TREE["${level}"]}; do
                if is::not_empty "${__ARGS_DESCRIPTIONS["${item}"]:-}"; then
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
                # Хинт типа значения: number / enum:a,b / другое
                # Value type hint: number / enum:a,b / other
                local value_hint="value"
                case "${__ARGS_FLAG_VALIDATORS["${flag_name}"]:-}" in
                    number) value_hint="number" ;;
                    enum:*) value_hint="${__ARGS_FLAG_VALIDATORS["${flag_name}"]#enum:}" ;;
                esac
                flag_label="--${flag_name} <${value_hint}>"
            fi
            if is::not_empty "${__ARGS_FLAG_DESCRIPTIONS["${flag_name}"]:-}"; then
                printf '    %-28s — %s' "${flag_label}" "${__ARGS_FLAG_DESCRIPTIONS["${flag_name}"]}"
            else
                printf '    %-28s' "${flag_label}"
            fi
            # Дефолт в help / Default in help
            if [[ -v __ARGS_FLAG_DEFAULTS["${flag_name}"] ]]; then
                printf ' (default: %s)\n' "${__ARGS_FLAG_DEFAULTS["${flag_name}"]}"
            else
                printf '\n'
            fi
        done < <(printf '%s\n' "${!__ARGS_FLAGS[@]}" | sort)
        printf '    %-28s — %s\n' "--help" "Show this help and exit"
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
#   args::require "$@"   # or: args::parse "$@" || bs::exit invalid
args::parse() {
    ARGS_PARAMS=()
    ARGS_FLAGS=()
    ARGS_REST=()
    ARGS_HELP_REQUESTED=0

    # Запрос help: -h/--help в любой позиции, не только argv[0].
    # Объявленные флаги help/h имеют приоритет — их обработает цикл ниже.
    # Help request: -h/--help at any position, not only argv[0].
    # Declared flags named help/h take precedence — the loop below handles them.
    local arg key help_requested="false"
    for arg in "$@"; do
        if [[ "${arg}" == "-h" ]] || [[ "${arg}" == "--help" ]]; then
            key="${arg#--}"
            [[ "${arg}" == "-h" ]] && key="h"
            if is::empty "${__ARGS_FLAGS["${key}"]:-}"; then
                help_requested="true"
            fi
        fi
    done
    if [[ "${help_requested}" == "true" ]]; then
        ARGS_HELP_REQUESTED=1
        args::help
        return "${E_SUCCESS:-0}"
    fi

    if [[ ${#__ARGS_TREE[@]} -eq 0 ]] && [[ ${#__ARGS_FLAGS[@]} -eq 0 ]]; then
        log::error "args::parse: parameter tree is empty, call args::define, args::level or args::flag first"
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

        # Разделитель "--": всё после — сырые аргументы (ARGS_REST)
        # The "--" separator: everything after — raw arguments (ARGS_REST)
        if [[ "${param}" == "--" ]]; then
            ARGS_REST=("${argv[@]:i+1}")
            break
        fi

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
            if is::empty "${__ARGS_FLAGS["${flag_name}"]:-}"; then
                log::error "unknown flag: \"--${flag_name}\""
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
                        log::error "flag \"--${flag_name}\" requires a value"
                        args::help >&2
                        return "${E_INVALID:-2}"
                    fi
                    if [[ "${argv[i]}" == "--" ]]; then
                        # Разделитель "--" не съедаем: значение отсутствует (пустое);
                        # откатываем i назад, чтобы "--" обработала ветка разделителя
                        # Do not eat the "--" separator: the value is missing (empty);
                        # rewind i so the "--" branch handles the separator
                        ARGS_FLAGS["${flag_name}"]=""
                        ((--i))
                    else
                        ARGS_FLAGS["${flag_name}"]="${argv[i]}"
                    fi
                fi
                # Валидация значения / Value validation
                if ! args::__validate_flag_value "${flag_name}" "${ARGS_FLAGS["${flag_name}"]}"; then
                    log::error "flag \"--${flag_name}\" has an invalid value: \"${ARGS_FLAGS["${flag_name}"]}\" (expected $(args::__flag_value_hint "${flag_name}"))"
                    args::help >&2
                    return "${E_INVALID:-2}"
                fi
            else
                # bool-флаг не принимает значение / bool flag takes no value
                if [[ "${has_inline}" == "true" ]]; then
                    log::error "flag \"--${flag_name}\" does not take a value"
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
            # Повторяемый уровень / Variadic level
            if (( __ARGS_VARIADIC_LEVEL > 0 )) && args::__is_allowed_at "${__ARGS_VARIADIC_LEVEL}" "${param}"; then
                ARGS_PARAMS+=("${param}")
                ((++i))
                continue
            fi
            log::error "too many parameters: \"${param}\" is beyond level ${max_level}"
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
        if is::not_empty "${real_level}"; then
            log::error "parameter \"${param}\" belongs to level ${real_level}, but was used at level ${position}"
        else
            log::error "unknown parameter: \"${param}\""
        fi
        args::help >&2
        return "${E_INVALID:-2}"
    done

    # Минимальное количество позиционных параметров / Minimum positional count
    if (( __ARGS_REQUIRED > 0 )) && (( position < __ARGS_REQUIRED )); then
        log::error "at least ${__ARGS_REQUIRED} parameter(s) are required, got ${position}"
        args::help >&2
        return "${E_INVALID:-2}"
    fi

    return "${E_SUCCESS:-0}"
}

# @description Require valid args — parse, or exit with cleanup. The one-liner.
# @description Требовать валидные аргументы: разбор или выход с очисткой.
#   Одна строка вместо идиомы:
#     args::parse "$@" || bs::exit invalid
#     [[ "${ARGS_HELP_REQUESTED}" == "1" ]] && bs::exit success
# @param $@ Script parameters (usually "$@") / Параметры скрипта (обычно "$@")
# @example
#   args::require "$@"
args::require() {
    args::parse "$@" || bs::exit invalid
    if [[ "${ARGS_HELP_REQUESTED:-0}" == "1" ]]; then
        bs::exit success
    fi
    return "${E_SUCCESS:-0}"
}

# @description Получить провалидированный параметр по позиции (1-based)
#   С дефолтом (третий аргумент): возвращает его вместо ошибки.
# @description Get a validated parameter by position (1-based)
#   With a default (third argument): returns it instead of failing.
# @param $1 Position / Позиция
# @param $2 [optional] Default value / [опционально] Значение по умолчанию
# @return Prints the value; 1 if position not set and no default given
#   Выводит значение; 1 если позиция пуста и дефолт не задан
# @example
#   stage="$(args::get 1)"
#   env="$(args::get 2 staging)"
args::get() {
    local -r position="${1:-}"

    if is::empty "${position}" || ! [[ "${position}" =~ ^[0-9]+$ ]] || [[ "${position}" -eq 0 ]]; then
        log::warn "args::get: position must be a positive integer, got: ${position}"
        return "${E_ERROR:-1}"
    fi

    local value="${ARGS_PARAMS[$((position - 1))]:-}"
    if is::empty "${value}"; then
        if (( $# >= 2 )); then
            printf '%s\n' "${2}"
            return "${E_SUCCESS:-0}"
        fi
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
    # При пустом множестве флагов printf '%s\n' "${!arr[@]}" выдал бы пустую
    # строку (ключ ""), read получил бы flag_name="" и индекс "" сломал бы
    # ассоциативный массив — циклы пропускаются целиком
    # With an empty flag set, printf '%s\n' "${!arr[@]}" emits an empty line
    # (key ""), read would set flag_name="" and the "" subscript would break
    # the associative array — the loops are skipped entirely
    local flag_words="--help"
    local value_flags=""
    if [[ ${#__ARGS_FLAGS[@]} -gt 0 ]]; then
        local flag_name
        while IFS= read -r flag_name; do
            flag_words+=" --${flag_name}"
        done < <(printf '%s\n' "${!__ARGS_FLAGS[@]}" | sort)

        # Список value-флагов (после них значение не дополняется);
        # enum-флаги исключаются — для них дополняются значения
        # Value flags list (their values are not completed);
        # enum flags are excluded — their values ARE completed
        while IFS= read -r flag_name; do
            if [[ "${__ARGS_FLAGS["${flag_name}"]:-}" == "value" ]] && \
               [[ "${__ARGS_FLAG_VALIDATORS["${flag_name}"]:-}" != enum:* ]]; then
                value_flags+=" --${flag_name}"
            fi
        done < <(printf '%s\n' "${!__ARGS_FLAGS[@]}" | sort)
    fi

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
    if is::not_empty "${value_flags}"; then
        local IFS=' '
        local vf_patterns=""
        local vf
        for vf in ${value_flags}; do
            if is::not_empty "${vf_patterns}"; then
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

    # enum-значения для value-флагов / enum values for value flags
    local enum_flag_name enum_values
    if [[ ${#__ARGS_FLAGS[@]} -gt 0 ]]; then
        while IFS= read -r enum_flag_name; do
            if [[ "${__ARGS_FLAGS["${enum_flag_name}"]:-}" == "value" ]] && \
               [[ "${__ARGS_FLAG_VALIDATORS["${enum_flag_name}"]:-}" == enum:* ]]; then
                enum_values="${__ARGS_FLAG_VALIDATORS["${enum_flag_name}"]#enum:}"
                enum_values="${enum_values//,/ }"
                cat <<EOF

    # enum-значения: --${enum_flag_name} <${enum_values// /|}>
    case "\${prev}" in
        --${enum_flag_name}) COMPREPLY=( \$(compgen -W "${enum_values}" -- "\${cur}") ); return 0 ;;
    esac
EOF
            fi
        done < <(printf '%s\n' "${!__ARGS_FLAGS[@]}" | sort)
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

    if is::not_empty "${value_flags}"; then
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
        if is::not_empty "${__ARGS_TREE["${level}"]:-}"; then
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
