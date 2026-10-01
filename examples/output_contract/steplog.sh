#!/usr/bin/env bs
# shellcheck shell=bash
# examples/output_contract/steplog.sh — output contract demo: step log
# examples/output_contract/steplog.sh — демо контракта вывода: журнал шагов
#
# steplog::step/ok — ход ▶ и успех ✓; журнал гарантированно пишется при
# любом завершении (EXIT-trap). Непишемый файл → запасной журнал по UID.
# steplog::step/ok — step ▶ and success ✓; the log is guaranteed to be
# written on ANY exit (EXIT trap). Unwritable file → per-UID fallback log.
#
# Run / Запуск:
#   bs run examples/output_contract/steplog.sh

load "lib/ui/steplog"

main() {
    local -r logfile="${TMPDIR:-/tmp}/steplog_demo.log"
    steplog::init "${logfile}" 0
    steplog::step "useradd -m -s /usr/sbin/nologin demo"
    steplog::ok "пользователь создан / user created"
    steplog::step "systemctl enable --now demo.service"
    steplog::ok "сервис запущен / service started"
    steplog::finish
    printf 'Журнал / Log: %s\n\n' "${STEPLOG_FILE}"
    cat "${STEPLOG_FILE}"
    rm -f "${logfile}"
}

main "$@"