#!/usr/bin/env bs
# shellcheck shell=bash
# examples/openbao_wizard.sh — interactive TUI wizard: OpenBao server, client
# or both (dev/prod), with TLS, systemd, init/unseal and token storage
# examples/openbao_wizard.sh — интерактивный TUI-визард: сервер OpenBao,
# клиент или оба (dev/prod), TLS, systemd, init/unseal и сохранение токена
#
# Run / Запуск:
#   sudo bs run examples/openbao_wizard.sh
#   sudo bs run examples/openbao_wizard.sh --profile prod
#   bs run examples/openbao_wizard.sh --role client
#
# Keys / Клавиши: стрелки, 1-9, Enter, Space (в чекбоксах), q — отмена.
# Секреты вводятся скрыто и не пишутся в журнал.
#
# @depends lib/ui/wizard, lib/ui/steplog, lib/ui/presentation,
#   lib/system/openbao, lib/integration/openbao

load "lib/ui/presentation"
load "lib/ui/steplog"
load "lib/ui/wizard"
load "lib/system/openbao"
load "lib/integration/openbao"

# @global OBW_ROLE — OpenBao wizard: server|client|both (category: state)
# @global OBW_ROLE — Визард OpenBao: server|client|both (категория: state)
declare -g OBW_ROLE=""
# @global OBW_PROFILE — OpenBao wizard: dev|prod (category: state)
# @global OBW_PROFILE — Визард OpenBao: dev|prod (категория: state)
declare -g OBW_PROFILE=""
# @global OBW_ADDR — OpenBao wizard: client address (category: state)
# @global OBW_ADDR — Визард OpenBao: адрес клиента (категория: state)
declare -g OBW_ADDR=""
# @global OBW_CA — OpenBao wizard: client CA path (category: state)
# @global OBW_CA — Визард OpenBao: CA клиента (категория: state)
declare -g OBW_CA=""
# @global OBW_TOKEN — OpenBao wizard: token buffer, never logged (category: state)
# @global OBW_TOKEN — Визард OpenBao: буфер токена, не пишется в журнал (категория: state)
declare -g OBW_TOKEN=""
# @global OBW_VERBOSE — OpenBao wizard: verbose log flag (category: state)
# @global OBW_VERBOSE — Визард OpenBao: флаг подробного журнала (категория: state)
declare -g OBW_VERBOSE=0
# @global OBW_SERVER_READY — OpenBao wizard: server settings prepared (category: state)
# @global OBW_SERVER_READY — Визард OpenBao: настройки сервера готовы (категория: state)
declare -g OBW_SERVER_READY=0
# @global OBW_CLIENT_READY — OpenBao wizard: client settings prepared (category: state)
# @global OBW_CLIENT_READY — Визард OpenBao: настройки клиента готовы (категория: state)
declare -g OBW_CLIENT_READY=0

# @private Usage / Справка
obw::help() {
    printf 'Usage: sudo bs run examples/openbao_wizard.sh [options]\n'
    printf '       bs run examples/openbao_wizard.sh --role client [options]\n\n'
    printf 'Что это / What is this:\n'
    printf '  Ставит OpenBao и настраивает сервер или клиент.\n'
    printf '  Installs OpenBao and configures a server or a client.\n\n'
    printf 'Профили / Profiles:\n'
    printf '  dev  — HTTP на 127.0.0.1:8200, root token, сервер в этом терминале\n'
    printf '  prod — single-node Raft storage, TLS, systemd, operator init + unseal\n\n'
    printf 'Опции / Options:\n'
    printf '  --role server|client|both   роль / role\n'
    printf '  --profile dev|prod          профиль сервера / server profile\n'
    printf '  --addr URL                  адрес клиента / client address\n'
    printf '  --dry-run                   показать действия / print actions only\n'
    printf '  --verbose                   журнал в stderr / log to stderr\n'
    printf '  -h, --help                  эта справка / this help\n\n'
    printf 'Безопасность / Security:\n'
    printf '  Ключи и root token сохраняются в %s (0600).\n' "${BS_OPENBAO_INIT_FILE}"
    printf '  Токен клиента — в %s (0600).\n' "${BS_OPENBAO_TOKEN_FILE}"
    printf '  Секреты не выводятся в консоль и не попадают в журнал.\n'
    printf '  Secrets are not printed and never reach the log.\n'
    printf '  Журнал / Log: %s/openbao_wizard.log\n' "${TMPDIR:-/tmp}"
}

# @private Fatal framed error / Фатальная ошибка в рамке
# @param $1 Message / Сообщение
obw::fail() {
    steplog::error "${1}"
    wizard::fail "${1}"
}

# @private Cancel / Отмена
# @param $1 Step / Шаг
obw::cancel() {
    steplog::warn "Отменено / Cancelled: ${1}"
    wizard::__restore
    printf '\n'
    presentation::warning "Отменено / Cancelled"
    presentation::info "Остановился на шаге / Stopped at: ${1}"
    if (( OBW_SERVER_READY == 0 && OBW_CLIENT_READY == 0 )); then
        presentation::info "Ничего не изменено / Nothing was changed"
    fi
    presentation::info "Журнал / Log: ${STEPLOG_FILE}"
    exit 0
}

# @private Step marker / Маркер шага
# @param $1 Text / Текст
obw::step_go() {
    printf '  '
    wizard::__sgr 36
    printf '▶'
    wizard::__sgr_reset
    printf ' %s\n' "$1"
    steplog::step "$1"
}

# @private Step success / Успех шага
# @param $1 Text / Текст
obw::step_ok() {
    printf '  '
    wizard::__sgr 32
    printf '✓'
    wizard::__sgr_reset
    printf ' %s\n' "$1"
    steplog::ok "$1"
}

# @private Run a step; on failure show the log path / Выполнить шаг
# @param $1 Description / Описание
# @param $@ Command / Команда
obw::run() {
    local -r desc="${1:?step description required}"
    shift
    obw::step_go "${desc}"
    local rc=0
    "$@" || rc=$?
    if (( rc != 0 )); then
        obw::fail "Шаг не выполнен / Step failed: ${desc}
  Код / Code: ${rc}
  Журнал / Log: ${STEPLOG_FILE}"
    fi
    obw::step_ok "${desc}"
}

# @private Parse CLI arguments / Разобрать аргументы
# @param $@ Arguments / Аргументы
# @return 0 ok, 2 usage error, 3 help / 0 ok, 2 ошибка, 3 справка
obw::parse_args() {
    while (( $# > 0 )); do
        case "${1}" in
            -h|--help) return 3 ;;
            --dry-run)
                BS_OPENBAO_DRY_RUN=1
                export FRAMEWORK_DRY_RUN=true
                ;;
            --verbose|verbose) OBW_VERBOSE=1 ;;
            --role)
                [[ -n "${2:-}" ]] || { printf 'openbao_wizard: --role needs a value\n' >&2; return 2; }
                OBW_ROLE="${2}"
                shift
                ;;
            --role=*) OBW_ROLE="${1#*=}" ;;
            --profile)
                [[ -n "${2:-}" ]] || { printf 'openbao_wizard: --profile needs a value\n' >&2; return 2; }
                OBW_PROFILE="${2}"
                shift
                ;;
            --profile=*) OBW_PROFILE="${1#*=}" ;;
            --addr)
                [[ -n "${2:-}" ]] || { printf 'openbao_wizard: --addr needs a value\n' >&2; return 2; }
                OBW_ADDR="${2}"
                shift
                ;;
            --addr=*) OBW_ADDR="${1#*=}" ;;
            --) shift; break ;;
            *) printf 'openbao_wizard: unknown option: %s\n' "${1}" >&2; return 2 ;;
        esac
        shift
    done
    case "${OBW_ROLE}" in
        ""|server|client|both) ;;
        *) printf 'openbao_wizard: --role must be server|client|both\n' >&2; return 2 ;;
    esac
    case "${OBW_PROFILE}" in
        ""|dev|prod) ;;
        *) printf 'openbao_wizard: --profile must be dev|prod\n' >&2; return 2 ;;
    esac
    return 0
}

# @private Choose server/client role / Выбрать роль
obw::choose_role() {
    if [[ -n "${OBW_ROLE}" ]]; then
        return 0
    fi
    local pick=0
    wizard::menu pick "Роль / Role" "Что настроить на этой машине / What to configure" \
        "Сервер / Server" "Клиент / Client" "Сервер + клиент / Both"
    case "${pick}" in
        0) OBW_ROLE="server" ;;
        1) OBW_ROLE="client" ;;
        2) OBW_ROLE="both" ;;
        *) obw::cancel "роль / role" ;;
    esac
}

# @private Choose dev/prod / Выбрать dev/prod
obw::choose_profile() {
    if [[ -n "${OBW_PROFILE}" ]]; then
        return 0
    fi
    local pick=0
    wizard::menu pick "Профиль сервера / Server profile" \
        "dev — локально и быстро · prod — TLS + systemd + init" \
        "dev" "prod"
    case "${pick}" in
        0) OBW_PROFILE="dev" ;;
        1) OBW_PROFILE="prod" ;;
        *) obw::cancel "профиль / profile" ;;
    esac
}

# @private Check server tools / Проверить инструменты сервера
obw::check_server_tools() {
    local -a missing=()
    local tool
    for tool in tar sha256sum gzip; do
        is::command "${tool}" || missing+=("${tool}")
    done
    is::command "${BS_OPENBAO_JQ:-jq}" || missing+=("jq")
    if ! is::command curl && ! is::command wget; then
        missing+=("curl|wget")
    fi
    if [[ "${OBW_PROFILE}" == "prod" ]]; then
        local t
        for t in systemctl useradd; do
            is::command "${t}" || missing+=("${t}")
        done
    fi
    if (( ${#missing[@]} > 0 )); then
        obw::fail "Отсутствуют зависимости / Missing dependencies:
  ${missing[*]}
Установите пакеты и повторите / Install the packages and retry."
    fi
}

# @private Check client tools / Проверить инструменты клиента
obw::check_client_tools() {
    local -a missing=()
    is::command curl || missing+=("curl")
    is::command "${BS_OPENBAO_JQ:-jq}" || missing+=("jq")
    if (( ${#missing[@]} > 0 )); then
        obw::fail "Отсутствуют зависимости клиента / Missing client dependencies:
  ${missing[*]}
API-клиенту OpenBao нужны curl и jq / the OpenBao API client needs curl and jq."
    fi
}

# @private Ask for server settings / Спросить настройки сервера
obw::ask_server() {
    if (( EUID != 0 )) && [[ "${BS_OPENBAO_DRY_RUN}" != "1" ]]; then
        obw::fail "Требуются права root / Root required.
  Запустите / Run: sudo bs run examples/openbao_wizard.sh"
    fi
    obw::choose_profile
    if [[ "${OBW_PROFILE}" == "dev" ]]; then
        BS_OPENBAO_TLS_MODE="off"
    else
        BS_OPENBAO_TLS_MODE="selfsigned"
    fi
    obw::check_server_tools

    local install=0
    local detected=""
    detected="$(openbao_server::detect)" || detected=""
    if [[ -n "${detected}" ]]; then
        local use=0
        wizard::yn use "Использовать установленный OpenBao? / Use installed OpenBao?" \
            "Найден / Found: ${detected}"
        case "${use}" in
            y) ;;
            n)
                wizard::yn install "Скачать и установить OpenBao? / Download and install OpenBao?" \
                    "Релиз / Release: ${BS_OPENBAO_VERSION}"
                [[ "${install}" == "y" ]] || obw::cancel "установка / install"
                obw::run "Установка OpenBao / Install OpenBao" openbao_server::install
                ;;
            *) obw::cancel "установка / install" ;;
        esac
    else
        wizard::yn install "Скачать и установить OpenBao? / Download and install OpenBao?" \
            "Релиз / Release: ${BS_OPENBAO_VERSION}; путь / path: ${BS_OPENBAO_BIN}"
        if [[ "${install}" != "y" ]]; then
            obw::cancel "установка / install"
        fi
        obw::run "Установка OpenBao / Install OpenBao" openbao_server::install
    fi

    local listen="${BS_OPENBAO_LISTEN}"
    wizard::ask_input listen "Адрес сервера / Listen address" "${listen}" \
        "host:port · 127.0.0.1:8200 или 0.0.0.0:8200"
    [[ "${listen}" == "q" ]] && obw::cancel "адрес / address"
    BS_OPENBAO_LISTEN="${listen}"

    if [[ "${OBW_PROFILE}" == "prod" ]]; then
        local tls=0
        wizard::menu tls "TLS сервера / Server TLS" \
            "Самоподписанный CA или готовые файлы / Self-signed CA or existing files" \
            "Самоподписанный / Self-signed" "Готовые файлы / Existing files" "Без TLS / No TLS (не рекомендуется)"
        case "${tls}" in
            0)
                BS_OPENBAO_TLS_MODE="selfsigned"
                is::command openssl || obw::fail "Нужен openssl / openssl is required for a self-signed CA"
                ;;
            1)
                BS_OPENBAO_TLS_MODE="files"
                local cert="${BS_OPENBAO_TLS_CERT}" key="${BS_OPENBAO_TLS_KEY}"
                wizard::ask_input cert "Сертификат / Certificate" "${cert}" "полный путь / full path"
                [[ "${cert}" == "q" ]] && obw::cancel "TLS / certificate"
                wizard::ask_input key "Ключ / Key" "${key}" "полный путь / full path"
                [[ "${key}" == "q" ]] && obw::cancel "TLS / key"
                BS_OPENBAO_TLS_CERT="${cert}"
                BS_OPENBAO_TLS_KEY="${key}"
                if ! openbao_server::__service_readable "${cert}" \
                    || ! openbao_server::__service_readable "${key}"; then
                    obw::fail "TLS-файлы не найдены или недоступны пользователю ${BS_OPENBAO_USER} / TLS files are missing or not readable by ${BS_OPENBAO_USER}:
  ${cert}
  ${key}"
                fi
                local ca="${BS_OPENBAO_TLS_CA}"
                [[ -r "${ca}" ]] || ca=""
                wizard::ask_input ca "CA-сертификат / CA bundle" "${ca}" \
                    "пусто для системного CA / empty for the system CA"
                [[ "${ca}" == "q" ]] && obw::cancel "CA / certificate"
                if [[ -n "${ca}" && ! -r "${ca}" ]]; then
                    obw::fail "CA-сертификат не найден / CA bundle not found: ${ca}"
                fi
                BS_OPENBAO_TLS_CA="${ca}"
                ;;
            2)
                BS_OPENBAO_TLS_MODE="off"
                local no_tls=0
                wizard::yn no_tls "Точно без TLS? / Really without TLS?" \
                    "Токены пойдут открытым текстом. / Tokens will travel in clear text."
                [[ "${no_tls}" == "y" ]] || obw::cancel "TLS / no TLS"
                ;;
            *) obw::cancel "TLS / choice" ;;
        esac
    fi
    OBW_SERVER_READY=1
}

# @private Ask for client settings / Спросить настройки клиента
obw::ask_client() {
    obw::check_client_tools
    local def_addr="${OBW_ADDR:-${BS_OPENBAO_ADDR:-https://127.0.0.1:8200}}"
    local def_ca="${OBW_CA:-${BS_OPENBAO_CACERT:-}}"
    if (( OBW_SERVER_READY == 1 )); then
        def_addr="$(openbao_server::local_api_addr "${OBW_PROFILE:-prod}")"
        if [[ "${BS_OPENBAO_TLS_MODE}" == "selfsigned" ]]; then
            def_ca="${BS_OPENBAO_TLS_DIR}/ca.crt"
        elif [[ "${BS_OPENBAO_TLS_MODE}" == "files" && -r "${BS_OPENBAO_TLS_CA}" ]]; then
            def_ca="${BS_OPENBAO_TLS_CA}"
        fi
    fi

    local addr="${def_addr}" ca="${def_ca}"
    wizard::ask_input addr "Адрес OpenBao / OpenBao address" "${addr}" \
        "https://127.0.0.1:8200"
    [[ "${addr}" == "q" ]] && obw::cancel "адрес / address"
    wizard::ask_input ca "CA-сертификат / CA bundle" "${ca}" \
        "пусто для системного CA / empty for the system CA"
    [[ "${ca}" == "q" ]] && obw::cancel "CA / certificate"
    OBW_ADDR="${addr}"
    OBW_CA="${ca}"

    local mode=0
    wizard::menu mode "Токен клиента / Client token" \
        "Можно вставить сейчас или сохранить позже / Paste now or save later" \
        "Вставить токен / Paste token" "Не задавать / Skip"
    case "${mode}" in
        0)
            wizard::ask_pass OBW_TOKEN "Токен не будет показан и попадёт только в файл 0600" \
                "Токен OpenBao / OpenBao token"
            [[ "${OBW_TOKEN}" == "q" ]] && obw::cancel "токен / token"
            ;;
        1) OBW_TOKEN="" ;;
        *) obw::cancel "токен / token" ;;
    esac
    OBW_CLIENT_READY=1
}

# @private Server summary / Сводка сервера
obw::server_summary() {
    printf 'Профиль / Profile: %s\n' "${OBW_PROFILE}"
    printf 'Бинарник / Binary: %s\n' "${BS_OPENBAO_BIN}"
    printf 'Адрес / Listen: %s\n' "${BS_OPENBAO_LISTEN}"
    printf 'TLS: %s\n' "${BS_OPENBAO_TLS_MODE}"
    if [[ "${OBW_PROFILE}" == "prod" ]]; then
        printf 'Конфиг / Config: %s\n' "${BS_OPENBAO_CONFIG}"
        printf 'Данные / Data: %s\n' "${BS_OPENBAO_DATA_DIR}"
        printf 'Init-файл / Init: %s (0600, секреты / secrets)\n' "${BS_OPENBAO_INIT_FILE}"
        printf 'Сервис / Service: %s\n' "${BS_OPENBAO_SERVICE}"
    else
        printf 'Dev-сервер запустится в этом терминале / The dev server will run here\n'
    fi
}

# @private Client summary / Сводка клиента
obw::client_summary() {
    printf 'Адрес / Address: %s\n' "${OBW_ADDR}"
    printf 'CA: %s\n' "${OBW_CA:-системный / system}"
    if [[ -n "${OBW_TOKEN}" ]]; then
        printf 'Токен / Token: будет проверен и сохранён / checked and saved\n'
    else
        printf 'Токен / Token: не задан / not set\n'
    fi
    printf 'Файл токена / Token file: %s (0600)\n' "${BS_OPENBAO_TOKEN_FILE}"
}

# @private Apply client settings / Применить настройки клиента
obw::apply_client() {
    BS_OPENBAO_ADDR="${OBW_ADDR}"
    BS_OPENBAO_CACERT="${OBW_CA}"
    export BS_OPENBAO_TOKEN=""
    openbao::init || obw::fail "Не удалось разобрать настройки клиента / Cannot resolve client settings"
    if [[ -n "${OBW_TOKEN}" ]]; then
        obw::run "Проверка и сохранение токена / Check and save token" \
            openbao::login "${OBW_TOKEN}"
    fi
    local health
    if ! health="$(openbao::health)"; then
        obw::fail "OpenBao не отвечает / OpenBao is not reachable:
  ${OBW_ADDR}
  CA: ${OBW_CA:-system}
  Проверьте адрес, CA и сервер / Check the address, CA and server."
    fi
    steplog::info "OpenBao health: ${health}"
    local sealed
    sealed="$(printf '%s' "${health}" | "${BS_OPENBAO_JQ:-jq}" -r '.sealed' 2>/dev/null || true)"
    if [[ "${sealed}" == "true" ]]; then
        presentation::warning "Сервер sealed — нужен unseal / Server is sealed — unseal is required"
    fi
    obw::step_ok "Соединение с OpenBao / OpenBao connection"
}

# @private Apply server settings / Применить настройки сервера
obw::apply_server() {
    if [[ "${OBW_PROFILE}" == "dev" ]]; then
        BS_OPENBAO_DEV_TOKEN="${BS_OPENBAO_DEV_TOKEN:-$(wizard::gen_pass | tr -d '\n')}"
        obw::run "Установка OpenBao / Install OpenBao" openbao_server::install
        wizard::__restore
        printf '\n'
        presentation::success "OpenBao dev готов / ready"
        presentation::info "Root token (только dev / dev only): ${BS_OPENBAO_DEV_TOKEN}"
        presentation::info "Сервер запускается в этом терминале / The server starts in this terminal"
        presentation::info "Остановка / Stop: Ctrl-C"
        presentation::info "Журнал / Log: ${STEPLOG_FILE}"
        printf '\n'
        openbao_server::dev_start
        exit $?
    fi

    obw::run "Применение OpenBao prod / Apply OpenBao prod" openbao_server::apply prod
}

# @private Final server notice / Итог сервера
obw::final_server() {
    wizard::__restore
    printf '\n'
    presentation::success "OpenBao prod готов / ready"
    printf '\n'
    presentation::info "Проверка / Check:"
    presentation::info "  sudo systemctl status ${BS_OPENBAO_SERVICE}"
    local api ca check
    api="$(openbao_server::local_api_addr prod)"
    ca="$(openbao_server::__ca_file)"
    if [[ -n "${ca}" ]]; then
        check="sudo env BAO_ADDR=$(printf '%q' "${api}") BAO_CACERT=$(printf '%q' "${ca}") $(printf '%q' "${BS_OPENBAO_BIN}") status"
    else
        check="sudo env BAO_ADDR=$(printf '%q' "${api}") $(printf '%q' "${BS_OPENBAO_BIN}") status"
    fi
    presentation::info "  ${check}"
    presentation::info "Файлы / Files:"
    presentation::info "  ${BS_OPENBAO_CONFIG}"
    presentation::info "  ${BS_OPENBAO_DATA_DIR}"
    presentation::info "  ${BS_OPENBAO_INIT_FILE}  # ключи + root token, 0600"
    presentation::warning "Init-файл содержит секреты / the init file contains secrets — не публикуйте / do not publish it"
    presentation::info "Журнал / Log: ${STEPLOG_FILE}"
}

# @private Final client notice / Итог клиента
obw::final_client() {
    wizard::__restore
    printf '\n'
    presentation::success "OpenBao client готов / ready"
    printf '\n'
    presentation::info "Проверка / Check:"
    presentation::info "  export BS_OPENBAO_ADDR='${OBW_ADDR}'"
    if [[ -n "${OBW_CA}" ]]; then
        presentation::info "  export BS_OPENBAO_CACERT='${OBW_CA}'"
    fi
    presentation::info "  bs repl"
    presentation::info "  load \"lib/integration/openbao\"; openbao::health"
    presentation::info "Токен / Token file: ${BS_OPENBAO_TOKEN_FILE} (0600)"
    presentation::info "Журнал / Log: ${STEPLOG_FILE}"
}

# @private Main / Главная функция
# @param $@ Arguments / Аргументы
obw::main() {
    local parse=0
    obw::parse_args "$@" || parse=$?
    if (( parse == 3 )); then
        obw::help
        exit 0
    fi
    if (( parse != 0 )); then
        obw::help >&2
        exit 2
    fi

    steplog::init "${TMPDIR:-/tmp}/openbao_wizard.log" "${OBW_VERBOSE}"
    steplog::on_exit wizard::__restore
    signal::on INT wizard::__restore

    wizard::__enter_alt
    if ! wizard::intro "OpenBao — установка и клиент / setup and client" \
        "Этот визард ставит OpenBao и настраивает сервер или клиент." \
        "This wizard installs OpenBao and configures a server or a client." \
        "" \
        "dev  — HTTP на loopback, root token, сервер в терминале." \
        "prod — TLS, systemd, operator init + unseal." \
        "" \
        "Секреты сохраняются в файлы 0600 и не печатаются." \
        "Secrets go to 0600 files and are never printed."; then
        obw::cancel "вступление / intro"
    fi

    obw::choose_role
    if [[ "${OBW_ROLE}" == "server" || "${OBW_ROLE}" == "both" ]]; then
        obw::ask_server
    fi
    if [[ "${OBW_ROLE}" == "both" && "${OBW_PROFILE}" == "dev" ]]; then
        presentation::warning "Для dev клиент настраивается после запуска сервера / configure the dev client after the server starts"
        OBW_ROLE="server"
    fi
    if [[ "${OBW_ROLE}" == "client" || "${OBW_ROLE}" == "both" ]]; then
        obw::ask_client
    fi

    local summary=""
    if (( OBW_SERVER_READY == 1 )); then
        summary+="$(obw::server_summary)"$'\n\n'
    fi
    if (( OBW_CLIENT_READY == 1 )); then
        summary+="$(obw::client_summary)"
    fi
    local confirm=0
    wizard::yn confirm "Применить настройки? / Apply these settings?" "${summary}"
    if [[ "${confirm}" == "q" ]]; then
        obw::cancel "подтверждение / confirmation"
    fi
    if [[ "${confirm}" != "y" ]]; then
        obw::cancel "подтверждение / confirmation"
    fi

    if (( OBW_SERVER_READY == 1 )); then
        obw::apply_server
    fi
    if (( OBW_CLIENT_READY == 1 )); then
        obw::apply_client
    fi

    if (( OBW_CLIENT_READY == 1 && OBW_SERVER_READY == 0 )); then
        obw::final_client
    elif (( OBW_CLIENT_READY == 1 && OBW_SERVER_READY == 1 )); then
        obw::final_server
        printf '\n'
        obw::final_client
    else
        obw::final_server
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]] || [[ -n "${BASH_EXECUTION_STRING:-}" ]]; then
    obw::main "$@"
fi
