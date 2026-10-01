#!/usr/bin/env bs
# shellcheck shell=bash
# lib/ui/output_contract.sh — catalog of output contract units / реестр единиц контракта вывода
# lib/ui/output_contract.sh — реестр единиц контракта вывода
#
# Единицы контракта — виды вывода, сложившиеся в практике BS (см.
# documentation/*/code-style-guide.md и скилл bs-cli-noop-output). Каждая
# запись: id, RU/EN название, модуль-источник, демо-скрипт. Модуль только
# каталогизирует и запускает демо — сами виды реализуют core/logger,
# lib/ui/presentation, lib/ui/steplog, lib/ui/elements/* и update_box в CLI bs.
#
# Использование / Usage:
#   load "lib/ui/output_contract"
#   output_contract::list
#   output_contract::demo noop_box
#   output_contract::check
#   bs run lib/ui/output_contract.sh          # список / list
#   bs run lib/ui/output_contract.sh --demo <id>
#   bs run lib/ui/output_contract.sh --check
#
# @depends core/utils

# Source Guard / Защита от повторной загрузки
bs::guard "LIB_UI_OUTPUT_CONTRACT" || return 0

# Dependencies / Зависимости
bs::source_relative "../../core/utils.sh"

# @global OUTPUT_CONTRACT_UNITS — Output contract: catalog entries "id:title ru / en:source:demo" (category: constant)
# @global OUTPUT_CONTRACT_UNITS — Контракт вывода: записи каталога "id:название ru / en:источник:демо" (категория: constant)
declare -ga OUTPUT_CONTRACT_UNITS=(
    "log_levels:Уровни лога / Log levels (trace…fatal):core/logger.sh:examples/output_contract/log_levels.sh"
    "header_box:Рамка-заголовок / Header box:core/logger.sh:examples/output_contract/header_box.sh"
    "bullets:Список с маркерами / Bullet list:core/logger.sh:examples/output_contract/bullets.sh"
    "table:Таблица / Table:core/logger.sh, lib/ui/presentation.sh:examples/output_contract/table.sh"
    "progress:Прогресс / Progress:core/logger.sh, lib/ui/presentation.sh:examples/output_contract/progress.sh"
    "notices:Уведомления / Notices:lib/ui/presentation.sh:examples/output_contract/notices.sh"
    "boxed:Рамка-текст / Boxed text:lib/ui/presentation.sh:examples/output_contract/boxed.sh"
    "noop_box:«Ничего не сделано» / No-op box:bs (update_box):examples/output_contract/noop_box.sh"
    "steplog:Журнал шагов / Step log:lib/ui/steplog.sh:examples/output_contract/steplog.sh"
    "tui_elements:TUI-элементы / TUI elements (12):lib/ui/elements/*:examples/output_contract/tui_elements.sh"
)

# @private Repo root: BS_ROOT or the module's parent dir / Корень репо.
# @stdout absolute path / абсолютный путь
output_contract::__root() {
    if is::not_empty "${BS_ROOT:-}"; then
        printf '%s\n' "${BS_ROOT}"
    else
        (cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." >/dev/null 2>&1 && pwd -P)
    fi
}

# @private Find a catalog entry by id / Найти запись каталога по id.
# @param $1 Unit id / Идентификатор единицы
# @stdout entry or empty / запись или пусто
# @return 0 found, 1 not found / 0 найдено, 1 нет
output_contract::__find() {
    local -r id="${1:?unit id required}"
    local entry
    for entry in "${OUTPUT_CONTRACT_UNITS[@]}"; do
        if [[ "${entry%%:*}" == "${id}" ]]; then
            printf '%s\n' "${entry}"
            return 0
        fi
    done
    return 1
}

# @description Print the catalog as an aligned table.
# @description Вывести каталог выровненной таблицей.
# @stdout catalog table / таблица каталога
output_contract::list() {
    local -i w_id=0 w_title=0
    local entry id title
    for entry in "${OUTPUT_CONTRACT_UNITS[@]}"; do
        id="${entry%%:*}"
        title="${entry#*:}"; title="${title%%:*}"
        (( ${#id} > w_id )) && w_id=${#id}
        (( ${#title} > w_title )) && w_title=${#title}
    done
    # Паддинг по символам: printf '%-*s' считает байты — с кириллицей
    # колонки схлопываются. ${#x} считает символы (= клетки).
    # Pad by characters: printf '%-*s' counts bytes — Cyrillic collapses
    # the columns. ${#x} counts chars (= cells).
    local -i n=0
    local row
    printf -v row '%-*s' "${w_id}" "ID"
    printf -v row '%s  %s  %s' "${row}" "$(printf '%-*s' "${w_title}" "Вид / Kind")" "Демо / Demo"
    printf '%s\n' "${row}"
    for entry in "${OUTPUT_CONTRACT_UNITS[@]}"; do
        id="${entry%%:*}"
        title="${entry#*:}"; title="${title%%:*}"
        (( n = w_id - ${#id} )) && (( n > 0 )) && printf -v id '%s%*s' "${id}" "${n}" ''
        (( n = w_title - ${#title} )) && (( n > 0 )) && printf -v title '%s%*s' "${title}" "${n}" ''
        printf '%s  %s  bs run %s\n' "${id}" "${title}" "${entry##*:}"
    done
}

# @description Run a unit's demo script / Запустить демо-скрипт единицы.
# @param $1 Unit id / Идентификатор единицы
# @return 0 ok, 1 unknown unit, 2 demo missing, 3 bs not in PATH /
#         0 успех, 1 нет единицы, 2 нет демо, 3 нет bs в PATH
output_contract::demo() {
    local -r id="${1:?unit id required}"
    local entry
    entry="$(output_contract::__find "${id}")" || {
        printf 'output_contract: неизвестная единица / unknown unit: %s\n' "${id}" >&2
        output_contract::list >&2
        return 1
    }
    local -r demo="${entry##*:}"
    local -r path="$(output_contract::__root)/${demo}"
    if ! is::file "${path}"; then
        printf 'output_contract: демо не найден / demo missing: %s\n' "${path}" >&2
        return 2
    fi
    if is::command bs; then
        exec bs run "${path}"
    fi
    printf 'output_contract: bs не найден в PATH — запустите вручную / run manually: bs run %s\n' "${demo}" >&2
    return 3
}

# @description Verify every demo script exists / Проверить наличие демо-скриптов.
# @return 0 all present, 1 some missing / 0 всё на месте, 1 чего-то нет
output_contract::check() {
    local -r root="$(output_contract::__root)"
    local -i missing=0
    local entry demo
    for entry in "${OUTPUT_CONTRACT_UNITS[@]}"; do
        demo="${entry##*:}"
        if is::file "${root}/${demo}"; then
            printf '  ✓ %s\n' "${demo}"
        else
            printf '  ✗ отсутствует / missing: %s\n' "${root}/${demo}" >&2
            (( missing += 1 ))
        fi
    done
    (( missing == 0 )) && return 0 || return 1
}

# Прямой запуск / Direct run: список, демо, проверка.
if [[ -n "${BASH_EXECUTION_STRING:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
    case "${1:-}" in
        --demo)
            shift
            output_contract::demo "${1:-}"
            exit $?
            ;;
        --check)
            output_contract::check
            exit $?
            ;;
        -h|--help)
            printf 'Usage: bs run lib/ui/output_contract.sh [--demo <id>|--check]\n\n'
            printf 'Каталог единиц контракта вывода / Output contract unit catalog:\n'
            printf '  --demo <id>   запустить демо-скрипт единицы / run the unit demo\n'
            printf '  --check       проверить наличие всех демо-скриптов / check demos\n'
            printf '  (без аргументов)  список / print the catalog\n'
            exit 0
            ;;
        *)
            output_contract::list
            ;;
    esac
fi