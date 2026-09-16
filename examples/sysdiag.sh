#!/usr/bin/env bs
# shellcheck shell=bash
# examples/sysdiag.sh — System diagnostics CLI
# examples/sysdiag.sh — CLI диагностики системы
#
# Демонстрирует возможности BS на реальном сценарии:
#   - core/args: декларативное дерево параметров + авто-help
#   - core/logger: уровни логирования (log::header/info/warn/success)
#   - lib/system/hw: геттеры оборудования (CPU, RAM)
#   - lib/ui/presentation: таблица presentation::table
#   - lib/integration/result: JSON-контракт для Go-бэкенда / CI
#
# Usage / Использование:
#   bs run examples/sysdiag.sh quick          # краткая сводка / quick summary
#   bs run examples/sysdiag.sh full           # полный отчёт / full report
#   bs run examples/sysdiag.sh json           # JSON (контракт result) / JSON contract
#   bs run examples/sysdiag.sh quick --output /tmp/sysdiag.txt
#   ./examples/sysdiag.sh quick               # bs в PATH / bs in PATH

set -euo pipefail

load "core/args"
load "core/utils"
load "lib/system/hw"
load "lib/ui/presentation"
load "lib/integration/result"

# ==========================================
# Helpers / Помощники
# ==========================================

sysdiag::os_name() {
    if is::file /etc/os-release; then
        ( source /etc/os-release; printf '%s %s\n' "${PRETTY_NAME:-${NAME:-Unknown}}" "${VERSION_ID:-}" )
    elif utils::has lsb_release; then
        utils::quiet_err lsb_release -ds
    elif utils::has uname; then
        utils::quiet_err uname -sr
    else
        printf 'Unknown\n'
    fi
}

sysdiag::mem_gib() {
    awk -v m="${1:?MiB required}" 'BEGIN { printf "%.1f", m / 1024 }'
}

sysdiag::uptime_str() {
    if utils::has uptime; then
        utils::quiet_err uptime -p
    else
        utils::quiet_err uptime
    fi
}

sysdiag::load_avg() {
    cut -d' ' -f1-3 /proc/loadavg 2>/dev/null || printf 'n/a'
}

# ==========================================
# Отчёты / Reports
# ==========================================

sysdiag::quick_report() {
    local -a rows
    rows+=(
        "Параметр:Значение"
        "Модель CPU:$(system::hw::cpu_model)"
        "Ядра:$(system::hw::cpu_cores) физ. / $(system::hw::cpu_threads) лог."
        "RAM всего:$(sysdiag::mem_gib "$(system::hw::mem_total)") GiB"
        "RAM доступно:$(sysdiag::mem_gib "$(system::hw::mem_available)") GiB"
        "ОС:$(sysdiag::os_name)"
        "Ядро:$(uname -r)"
        "Хост:$(hostname)"
        "Аптайм:$(sysdiag::uptime_str)"
        "Нагрузка:$(sysdiag::load_avg)"
    )
    presentation::table "${rows[@]}"

    printf '\nКорневая ФС / Root filesystem:\n'
    utils::attempt df -h /
}

sysdiag::full_report() {
    log::header "System / Система"
    printf 'OS:       %s\n' "$(sysdiag::os_name)"
    printf 'Kernel:   %s\n' "$(uname -r)"
    printf 'Host:     %s\n' "$(hostname)"
    printf 'Uptime:   %s\n' "$(sysdiag::uptime_str)"
    printf 'Load:     %s\n' "$(sysdiag::load_avg)"

    log::header "Hardware report (missing tools are skipped) / Железо"
    system::hw::summary
}

sysdiag::json_payload() {
    local model cores threads mem_total mem_avail os kernel
    model="$(system::hw::cpu_model)"
    model="${model//\"/\\\"}"
    cores="$(system::hw::cpu_cores)"
    threads="$(system::hw::cpu_threads)"
    mem_total="$(system::hw::mem_total)"
    mem_avail="$(system::hw::mem_available)"
    os="$(sysdiag::os_name)"
    kernel="$(uname -r)"

    printf '{"cpu":{"model":"%s","cores":%s,"threads":%s},"mem":{"total_mib":%s,"available_mib":%s},"os":"%s","kernel":"%s"}' \
        "${model}" "${cores}" "${threads}" "${mem_total}" "${mem_avail}" "${os}" "${kernel}"
}

sysdiag::json_report() {
    result::ok "$(sysdiag::json_payload)" "sysdiag report"
}

# ==========================================
# Entry point / Точка входа
# ==========================================

main() {
    args::level 1 quick full json
    args::describe quick "Краткая сводка / Quick summary"
    args::describe full "Полный отчёт / Full hardware report"
    args::describe json "JSON-результат (контракт result) / JSON result contract"

    args::flag output value
    args::flag_describe output "Сохранить отчёт в файл / Save the report to a file"

    if ! args::parse "$@"; then
        bs::exit invalid
    fi
    if [[ "${ARGS_HELP_REQUESTED}" == "1" ]]; then
        bs::exit success
    fi

    local action
    action="${ARGS_PARAMS[0]:-quick}"
    local out_file
    out_file="$(args::flag_get output || true)"

    case "${action}" in
        quick)
            if is::not_empty "${out_file}"; then
                sysdiag::quick_report > "${out_file}"
                log::success "Отчёт сохранён в ${out_file}"
            else
                sysdiag::quick_report
            fi
            ;;
        full)
            if is::not_empty "${out_file}"; then
                sysdiag::full_report > "${out_file}" 2>&1
                log::success "Отчёт сохранён в ${out_file}"
            else
                sysdiag::full_report
            fi
            ;;
        json)
            if is::not_empty "${out_file}"; then
                BS_RESULT_FILE="${out_file}" sysdiag::json_report
                log::success "JSON сохранён в ${out_file}"
            else
                sysdiag::json_report
            fi
            if utils::has jq; then
                local json rc
                json="$(sysdiag::json_report)"
                result::get "${json}" exit_code rc
                log::info "round-trip: exit_code=${rc} (result::get)"
            fi
            ;;
    esac

    bs::exit success
}

main "$@"