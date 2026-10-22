#!/usr/bin/env bs
# shellcheck shell=bash
# @shell bash4 — нужны конструкции bash: double-bracket [[ ]], array, local/declare flags, parameter expansion / needs bash constructs: double-bracket [[ ]], array, local/declare flags, parameter expansion
# lib/integration/openbao.sh — OpenBao HTTP API client: address/token/TLS
# resolution, generic request, KV v2/auth/policy/mount/sys/namespace helpers
# lib/integration/openbao.sh — HTTP-клиент OpenBao: адрес/токен/TLS,
# generic-запрос и помощники KV v2/auth/policy/mount/sys/namespace
#
# Usage / Использование:
#   load "lib/integration/openbao"
#   openbao::init
#   openbao::request GET sys/health
#   openbao::kv::put secret app '{"password":"s3cret"}'
#   openbao::kv::get secret app
#
# The token is read from BS_OPENBAO_TOKEN, BAO_TOKEN or a 0600 token file.
# TLS uses BS_OPENBAO_CACERT (or BAO_CACERT); tokens are never logged or
# passed in argv.
# Токен читается из BS_OPENBAO_TOKEN, BAO_TOKEN или файла 0600.
# TLS использует BS_OPENBAO_CACERT (или BAO_CACERT); токены не пишутся в лог
# и не передаются в argv.
#
# @depends core/const, core/logger, core/utils
# @optdeps curl, jq

# Source Guard / Защита от повторной загрузки
bs::guard "LIB_INTEGRATION_OPENBAO" || return 0

# Dependencies / Зависимости
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh"

# @global OPENBAO_ERROR_HTTP — OpenBao: unexpected HTTP status (category: error-const)
# @global OPENBAO_ERROR_HTTP — OpenBao: неожиданный HTTP-статус (категория: error-const)
declare -g OPENBAO_ERROR_HTTP=240
# @global OPENBAO_ERROR_AUTH — OpenBao: authentication/authorization failed (category: error-const)
# @global OPENBAO_ERROR_AUTH — OpenBao: аутентификация/авторизация не прошла (категория: error-const)
declare -g OPENBAO_ERROR_AUTH=241
# @global OPENBAO_ERROR_JSON — OpenBao: invalid JSON (category: error-const)
# @global OPENBAO_ERROR_JSON — OpenBao: неверный JSON (категория: error-const)
declare -g OPENBAO_ERROR_JSON=242

# @global BS_OPENBAO_ADDR — Hook: OpenBao API address (category: hook)
# @global BS_OPENBAO_ADDR — Хук: адрес API OpenBao (категория: hook)
declare -g BS_OPENBAO_ADDR="${BS_OPENBAO_ADDR:-}"
# @global BS_OPENBAO_TOKEN — Hook: OpenBao token, wins over BAO_TOKEN/file (category: hook)
# @global BS_OPENBAO_TOKEN — Хук: токен OpenBao, важнее BAO_TOKEN/файла (категория: hook)
declare -g BS_OPENBAO_TOKEN="${BS_OPENBAO_TOKEN:-}"
# @global BS_OPENBAO_TOKEN_FILE — Hook: 0600 token file (category: hook)
# @global BS_OPENBAO_TOKEN_FILE — Хук: файл токена 0600 (категория: hook)
declare -g BS_OPENBAO_TOKEN_FILE="${BS_OPENBAO_TOKEN_FILE:-${XDG_CONFIG_HOME:-${HOME:-/root}/.config}/bs/openbao-token}"
# @global BS_OPENBAO_CACERT — Hook: CA bundle for TLS (category: hook)
# @global BS_OPENBAO_CACERT — Хук: CA-сертификат для TLS (категория: hook)
declare -g BS_OPENBAO_CACERT="${BS_OPENBAO_CACERT:-}"
# @global BS_OPENBAO_NAMESPACE — Hook: OpenBao namespace (category: hook)
# @global BS_OPENBAO_NAMESPACE — Хук: namespace OpenBao (категория: hook)
declare -g BS_OPENBAO_NAMESPACE="${BS_OPENBAO_NAMESPACE:-}"
# @global BS_OPENBAO_CURL — Hook: curl binary, for tests (category: hook)
# @global BS_OPENBAO_CURL — Хук: бинарник curl, для тестов (категория: hook)
declare -g BS_OPENBAO_CURL="${BS_OPENBAO_CURL:-curl}"
# @global BS_OPENBAO_JQ — Hook: jq binary, for tests (category: hook)
# @global BS_OPENBAO_JQ — Хук: бинарник jq, для тестов (категория: hook)
declare -g BS_OPENBAO_JQ="${BS_OPENBAO_JQ:-jq}"
# @global BS_OPENBAO_TIMEOUT — Hook: HTTP timeout in seconds (category: hook)
# @global BS_OPENBAO_TIMEOUT — Хук: таймаут HTTP в секундах (категория: hook)
declare -g BS_OPENBAO_TIMEOUT="${BS_OPENBAO_TIMEOUT:-30}"
# @global BS_OPENBAO_DRY_RUN — Hook: 1 = do not make HTTP requests (category: hook)
# @global BS_OPENBAO_DRY_RUN — Хук: 1 = не делать HTTP-запросы (категория: hook)
declare -g BS_OPENBAO_DRY_RUN="${BS_OPENBAO_DRY_RUN:-0}"

# @global OPENBAO_ADDR — Current effective API address (category: state)
# @global OPENBAO_ADDR — Текущий адрес API (категория: state)
declare -g OPENBAO_ADDR=""
# @global OPENBAO_TOKEN — Current effective token (category: state)
# @global OPENBAO_TOKEN — Текущий токен (категория: state)
declare -g OPENBAO_TOKEN=""
# @global OPENBAO_CACERT — Current effective CA bundle (category: state)
# @global OPENBAO_CACERT — Текущий CA-сертификат (категория: state)
declare -g OPENBAO_CACERT=""
# @global OPENBAO_NAMESPACE — Current effective namespace (category: state)
# @global OPENBAO_NAMESPACE — Текущий namespace (категория: state)
declare -g OPENBAO_NAMESPACE=""
# @global OPENBAO_LAST_STATUS — HTTP status of the last request (category: state)
# @global OPENBAO_LAST_STATUS — HTTP-статус последнего запроса (категория: state)
declare -g OPENBAO_LAST_STATUS=0

# @private Check a required command / Проверить обязательную команду
# @param $1 Command / Команда
# @param $2 What it is for / Для чего
openbao::__need() {
    local -r cmd="${1:?command required}" what="${2:-OpenBao}"
    if ! is::command "${cmd}"; then
        log::error "OpenBao: требуется ${cmd} / ${cmd} is required for ${what}"
        return "${LIB_ERROR_DEPENDENCY_MISSING}"
    fi
    return 0
}

# @private Require jq for typed helpers / Требовать jq для типовых помощников
openbao::__need_jq() {
    openbao::__need "${BS_OPENBAO_JQ}" "JSON helpers"
}

# @private Trim leading/trailing whitespace / Убрать пробелы по краям
# @param $1 String / Строка
# @stdout trimmed string / строка без пробелов по краям
openbao::__trim() {
    local s="${1-}"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "${s}"
}

# @private Reject control characters and whitespace in a token/address /
# Отклонить управляющие символы и пробелы в токене/адресе
# @param $1 Value / Значение
# @param $2 Name for the message / Имя для сообщения
openbao::__safe_value() {
    local -r value="${1-}" name="${2:-value}"
    if [[ -n "${value}" && "${value}" == *[[:space:][:cntrl:]]* ]]; then
        log::error "OpenBao: недопустимые символы в ${name} / invalid characters in ${name}"
        return "${LIB_ERROR_INVALID_INPUT}"
    fi
    return 0
}

# @private Read a token file / Прочитать файл токена
# @param $1 Path / Путь
# @stdout token or empty / токен или пусто
openbao::__read_token_file() {
    local -r file="${1-}"
    [[ -n "${file}" && -r "${file}" ]] || return 0
    local token
    token="$(<"${file}")" || return 0
    openbao::__trim "${token}"
}

# @description Resolve address, token, CA and namespace.
# @description Определить адрес, токен, CA и namespace.
# @return 0 or LIB_ERROR_INVALID_INPUT / 0 или LIB_ERROR_INVALID_INPUT
openbao::init() {
    OPENBAO_ADDR="${BS_OPENBAO_ADDR:-${BAO_ADDR:-https://127.0.0.1:8200}}"
    OPENBAO_ADDR="${OPENBAO_ADDR%/}"
    OPENBAO_NAMESPACE="${BS_OPENBAO_NAMESPACE:-${BAO_NAMESPACE:-}}"
    OPENBAO_CACERT="${BS_OPENBAO_CACERT:-${BAO_CACERT:-}}"
    OPENBAO_TOKEN="${BS_OPENBAO_TOKEN:-${BAO_TOKEN:-}}"
    if [[ -z "${OPENBAO_TOKEN}" ]]; then
        OPENBAO_TOKEN="$(openbao::__read_token_file "${BS_OPENBAO_TOKEN_FILE}")"
    fi
    OPENBAO_LAST_STATUS=0

    openbao::__safe_value "${OPENBAO_ADDR}" "address" || return $?
    openbao::__safe_value "${OPENBAO_TOKEN}" "token" || return $?
    openbao::__safe_value "${OPENBAO_CACERT}" "CA path" || return $?
    openbao::__safe_value "${OPENBAO_NAMESPACE}" "namespace" || return $?

    if [[ "${OPENBAO_ADDR}" != http://* && "${OPENBAO_ADDR}" != https://* ]]; then
        log::error "OpenBao: адрес должен начинаться с http:// или https:// / address must start with http:// or https://"
        return "${LIB_ERROR_INVALID_INPUT}"
    fi
    return 0
}

# @private Build the request URL / Собрать URL запроса
# @param $1 Path or full URL / Путь или полный URL
# @stdout URL / URL
openbao::__url() {
    local path="${1:-}"
    if [[ "${path}" == http://* || "${path}" == https://* ]]; then
        printf '%s' "${path}"
        return 0
    fi
    path="${path#/}"
    if [[ "${path}" != v1/* ]]; then
        path="v1/${path}"
    fi
    printf '%s/%s' "${OPENBAO_ADDR}" "${path}"
}

# @private Validate an API path / Проверить путь API
# @param $1 Path / Путь
openbao::__validate_path() {
    local -r path="${1-}"
    if [[ -z "${path}" || "${path}" == *[$'\n\r\t ']* ]]; then
        log::error "OpenBao: пустой или недопустимый путь / empty or invalid path"
        return "${LIB_ERROR_INVALID_INPUT}"
    fi
    if [[ "${path}" == *..* ]]; then
        log::error "OpenBao: '..' в пути запрещён / '..' is not allowed in a path"
        return "${LIB_ERROR_INVALID_INPUT}"
    fi
    return 0
}

# @private Raw HTTP call: body and status, no token in argv.
# Prints "<body>\n<http_status>\n<curl_rc>". curl's stderr is suppressed.
# @private Сырой HTTP-вызов: тело и статус, токена нет в argv.
# Печатает "<тело>\n<http_status>\n<curl_rc>"; stderr curl подавлен.
# @param $1 Method / Метод
# @param $2 URL / URL
# @param $3 Body or empty / Тело или пусто
# @return curl exit code / код выхода curl
openbao::__http() {
    local -r method="${1:?method required}" url="${2:?url required}" data="${3-}"
    local -a args=(
        -sS
        -X "${method}"
        -w '\n%{http_code}'
        --max-time "${BS_OPENBAO_TIMEOUT}"
        -H "Content-Type: application/json"
    )
    local hdr=""
    if [[ -n "${OPENBAO_TOKEN}" || -n "${OPENBAO_NAMESPACE}" ]]; then
        hdr="$(mktemp "${TMPDIR:-/tmp}/bs-openbao-hdr.XXXXXX")" || {
            log::error "OpenBao: не удалось создать временный файл заголовков / cannot create header file"
            return "${LIB_ERROR_FILE_OPERATION}"
        }
        chmod 600 "${hdr}" 2>/dev/null || true
        {
            if [[ -n "${OPENBAO_TOKEN}" ]]; then
                local token_esc="${OPENBAO_TOKEN//\\/\\\\}"
                token_esc="${token_esc//\"/\\\"}"
                printf 'header = "X-Vault-Token: %s"\n' "${token_esc}"
            fi
            if [[ -n "${OPENBAO_NAMESPACE}" ]]; then
                local ns_esc="${OPENBAO_NAMESPACE//\\/\\\\}"
                ns_esc="${ns_esc//\"/\\\"}"
                printf 'header = "X-Vault-Namespace: %s"\n' "${ns_esc}"
            fi
        } > "${hdr}" || {
            rm -f -- "${hdr}"
            return "${LIB_ERROR_FILE_OPERATION}"
        }
        args+=(--config "${hdr}")
    fi
    [[ -n "${OPENBAO_CACERT}" ]] && args+=(--cacert "${OPENBAO_CACERT}")

    local rc=0
    if [[ -n "${data}" ]]; then
        printf '%s' "${data}" | "${BS_OPENBAO_CURL}" "${args[@]}" --data-binary @- -- "${url}" 2>/dev/null || rc=$?
    else
        "${BS_OPENBAO_CURL}" "${args[@]}" -- "${url}" 2>/dev/null || rc=$?
    fi
    [[ -n "${hdr}" ]] && rm -f -- "${hdr}"
    printf '\n%s\n' "${rc}"
}

# @description Generic OpenBao request.
# @description Универсальный запрос к OpenBao.
# @param $1 HTTP method (GET/POST/PUT/LIST/DELETE/PATCH) / Метод
# @param $2 Path without /v1 or a full URL / Путь без /v1 или полный URL
# @param $3 [optional] JSON body / JSON-тело
# @stdout response body / тело ответа
# @return 0 on 2xx, OPENBAO_ERROR_AUTH on 401/403, OPENBAO_ERROR_HTTP otherwise
# @example
#   openbao::request GET sys/health
#   openbao::request POST auth/token/create '{"policies":["default"]}'
openbao::request() {
    local -r method="${1:?method required}" path="${2:?path required}" data="${3-}"
    case "${method}" in
        GET|POST|PUT|DELETE|LIST|PATCH|HEAD) ;;
        *)
            log::error "OpenBao: неверный HTTP-метод / invalid HTTP method: ${method}"
            return "${LIB_ERROR_INVALID_INPUT}"
            ;;
    esac
    openbao::init || return $?
    openbao::__validate_path "${path}" || return $?
    openbao::__need "${BS_OPENBAO_CURL}" "OpenBao API" || return $?

    local -r url="$(openbao::__url "${path}")"
    if [[ "${BS_OPENBAO_DRY_RUN}" == "1" || "${FRAMEWORK_DRY_RUN:-false}" == "true" ]]; then
        log::warn "[DRY-RUN] OpenBao ${method} ${url}"
        return 0
    fi
    log::debug "OpenBao ${method} ${url}"

    local output rc=0
    output="$(openbao::__http "${method}" "${url}" "${data}")" || rc=$?
    # Last line is curl rc, the one before it is the HTTP status.
    # Последняя строка — код curl, перед ней — HTTP-статус.
    local http_rc="${output##*$'\n'}"
    local rest="${output%$'\n'*}"
    local status="${rest##*$'\n'}"
    local body="${rest%$'\n'*}"
    [[ "${status}" =~ ^[0-9]{3}$ ]] || status=0
    OPENBAO_LAST_STATUS="${status}"
    printf '%s' "${body}"

    if (( rc != 0 )) || (( http_rc != 0 )); then
        return "${OPENBAO_ERROR_HTTP}"
    fi
    if [[ "${status}" == 401 || "${status}" == 403 ]]; then
        return "${OPENBAO_ERROR_AUTH}"
    fi
    if [[ "${status}" != 2* ]]; then
        return "${OPENBAO_ERROR_HTTP}"
    fi
    return 0
}

# @description Save a token after checking it with lookup-self.
# @description Сохранить токен после проверки через lookup-self.
# @param $1 Token / Токен
# @return 0 saved, OPENBAO_ERROR_AUTH if rejected / 0 сохранён, OPENBAO_ERROR_AUTH если отклонён
openbao::login() {
    local -r token="${1:?token required}"
    openbao::__safe_value "${token}" "token" || return $?

    local old_token="${BS_OPENBAO_TOKEN-}" had_old=0
    [[ -n "${BS_OPENBAO_TOKEN+x}" ]] && had_old=1
    BS_OPENBAO_TOKEN="${token}"
    local rc=0
    openbao::init || rc=$?
    if (( rc != 0 )); then
        if [[ "${had_old}" == "1" ]]; then BS_OPENBAO_TOKEN="${old_token}"; else unset BS_OPENBAO_TOKEN; fi
        return "${rc}"
    fi
    rc=0
    openbao::request GET auth/token/lookup-self >/dev/null || rc=$?
    if (( rc != 0 )); then
        if [[ "${had_old}" == "1" ]]; then BS_OPENBAO_TOKEN="${old_token}"; else unset BS_OPENBAO_TOKEN; fi
        openbao::init >/dev/null 2>&1 || true
        return "${rc}"
    fi
    if [[ "${had_old}" == "1" ]]; then BS_OPENBAO_TOKEN="${old_token}"; else unset BS_OPENBAO_TOKEN; fi

    local -r dir="$(dirname -- "${BS_OPENBAO_TOKEN_FILE}")"
    if ! mkdir -p -- "${dir}" || ! chmod 700 -- "${dir}"; then
        log::error "OpenBao: не удалось создать каталог токена / cannot create token directory: ${dir}"
        return "${LIB_ERROR_FILE_OPERATION}"
    fi
    local tmp="${BS_OPENBAO_TOKEN_FILE}.tmp.$$"
    ( umask 077; printf '%s\n' "${token}" > "${tmp}" ) || return "${LIB_ERROR_FILE_OPERATION}"
    chmod 600 -- "${tmp}" || { rm -f -- "${tmp}"; return "${LIB_ERROR_FILE_OPERATION}"; }
    if ! mv -f -- "${tmp}" "${BS_OPENBAO_TOKEN_FILE}"; then
        rm -f -- "${tmp}"
        return "${LIB_ERROR_FILE_OPERATION}"
    fi
    OPENBAO_TOKEN="${token}"
    log::info "OpenBao: токен сохранён / token saved: ${BS_OPENBAO_TOKEN_FILE}"
}

# @description Remove the saved token / Удалить сохранённый токен
openbao::logout() {
    if [[ -f "${BS_OPENBAO_TOKEN_FILE}" ]]; then
        rm -f -- "${BS_OPENBAO_TOKEN_FILE}" || return "${LIB_ERROR_FILE_OPERATION}"
    fi
    OPENBAO_TOKEN=""
    log::info "OpenBao: токен удалён / token removed"
}

# @description Print the current token (explicit diagnostic only).
# @description Напечатать текущий токен (только для явной диагностики).
openbao::token() {
    openbao::init || return $?
    if [[ -z "${OPENBAO_TOKEN}" ]]; then
        log::error "OpenBao: токен не задан / no token configured"
        return "${OPENBAO_ERROR_AUTH}"
    fi
    printf '%s' "${OPENBAO_TOKEN}"
}

# @description Health endpoint; non-2xx OpenBao states are not errors here.
# @description health-endpoint; не-2xx состояния OpenBao здесь не ошибка.
# @stdout JSON / JSON
# @return 0 for 200/429/472/473/501/503 / 0 для 200/429/472/473/501/503
openbao::health() {
    local body rc=0 tmp
    tmp="$(mktemp "${TMPDIR:-/tmp}/bs-openbao-health.XXXXXX")" || {
        log::error "OpenBao: не удалось создать временный файл / cannot create temp file"
        return "${LIB_ERROR_FILE_OPERATION}"
    }
    openbao::request GET sys/health > "${tmp}" || rc=$?
    body="$(<"${tmp}")"
    rm -f -- "${tmp}"
    printf '%s' "${body}"
    case "${OPENBAO_LAST_STATUS}" in
        200|429|472|473|501|503) return 0 ;;
        *) return "${rc:-${OPENBAO_ERROR_HTTP}}" ;;
    esac
}

# @description Seal status / Статус запечатывания
openbao::seal_status() { openbao::request GET sys/seal-status; }
# @description Unseal with one key / Разблокировать одним ключом
# @param $1 Unseal key / Ключ
openbao::unseal() {
    local -r key="${1:?unseal key required}"
    local body
    body="$(printf '%s' "${key}" | "${BS_OPENBAO_JQ}" -Rs '{key: .}')" || return "${OPENBAO_ERROR_JSON}"
    openbao::request POST sys/unseal "${body}"
}
# @description Seal the server / Запечатать сервер
openbao::seal() { openbao::request POST sys/seal '{}'; }
# @description Leader info / Информация о лидере
openbao::leader() { openbao::request GET sys/leader; }

# @private JSON-escape a string through jq stdin / Экранировать строку через stdin jq
# @param $1 String / Строка
# @stdout JSON string / JSON-строка
openbao::__json_string() {
    openbao::__need_jq || return $?
    printf '%s' "${1-}" | "${BS_OPENBAO_JQ}" -Rs .
}

# @private Require jq and a valid JSON value / Требовать jq и валидный JSON
# @param $1 JSON / JSON
openbao::__check_json() {
    openbao::__need_jq || return $?
    if ! printf '%s' "${1-}" | "${BS_OPENBAO_JQ}" empty >/dev/null 2>&1; then
        log::error "OpenBao: неверный JSON / invalid JSON"
        return "${OPENBAO_ERROR_JSON}"
    fi
    return 0
}

# @private Validate a mount name / Проверить имя mount
openbao::__mount() {
    local -r mount="${1:-secret}"
    if [[ ! "${mount}" =~ ^[A-Za-z0-9_./-]+$ || "${mount}" == *..* ]]; then
        log::error "OpenBao: недопустимый mount / invalid mount: ${mount}"
        return "${LIB_ERROR_INVALID_INPUT}"
    fi
    printf '%s' "${mount}"
}

# @private Validate a KV key path / Проверить путь ключа KV
openbao::__key_path() {
    local -r path="${1-}"
    if [[ -z "${path}" || "${path}" == /* || "${path}" == *..* || "${path}" == *[$'\n\r\t ']* ]]; then
        log::error "OpenBao: недопустимый путь ключа / invalid key path: ${path}"
        return "${LIB_ERROR_INVALID_INPUT}"
    fi
    printf '%s' "${path}"
}

# @description Read a KV v2 secret / Прочитать секрет KV v2
# @param $1 Mount / Mount
# @param $2 Path / Путь
openbao::kv::get() {
    local mount path
    mount="$(openbao::__mount "${1:-secret}")" || return $?
    path="$(openbao::__key_path "${2:-}")" || return $?
    openbao::request GET "${mount}/data/${path}"
}

# @description Write a KV v2 secret / Записать секрет KV v2
# @param $1 Mount / Mount
# @param $2 Path / Путь
# @param $3 JSON object / JSON-объект
openbao::kv::put() {
    local mount path
    mount="$(openbao::__mount "${1:-secret}")" || return $?
    path="$(openbao::__key_path "${2:-}")" || return $?
    local -r data="${3:?JSON body required}"
    openbao::__check_json "${data}" || return $?
    openbao::request POST "${mount}/data/${path}" "${data}"
}

# @description Delete a KV v2 secret / Удалить секрет KV v2
# @param $1 Mount / Mount
# @param $2 Path / Путь
openbao::kv::delete() {
    local mount path
    mount="$(openbao::__mount "${1:-secret}")" || return $?
    path="$(openbao::__key_path "${2:-}")" || return $?
    openbao::request DELETE "${mount}/data/${path}"
}

# @description List KV v2 keys / Список ключей KV v2
# @param $1 Mount / Mount
# @param $2 Path / Путь
openbao::kv::list() {
    local mount path
    mount="$(openbao::__mount "${1:-secret}")" || return $?
    path="$(openbao::__key_path "${2:-}")" || return $?
    openbao::request LIST "${mount}/metadata/${path}"
}

# @description KV v2 metadata / Метаданные KV v2
# @param $1 Mount / Mount
# @param $2 Path / Путь
openbao::kv::metadata() {
    local mount path
    mount="$(openbao::__mount "${1:-secret}")" || return $?
    path="$(openbao::__key_path "${2:-}")" || return $?
    openbao::request GET "${mount}/metadata/${path}"
}

# @description Current token info / Информация о текущем токене
openbao::auth::lookup() { openbao::request GET auth/token/lookup-self; }
# @description Create a token from JSON / Создать токен из JSON
# @param $1 JSON / JSON
openbao::auth::create() {
    local -r data="${1:?JSON body required}"
    openbao::__check_json "${data}" || return $?
    openbao::request POST auth/token/create "${data}"
}
# @description Revoke a token / Отозвать токен
# @param $1 Token / Токен
openbao::auth::revoke() {
    local -r token="${1:?token required}"
    local body
    body="$(openbao::__json_string "${token}")" || return $?
    openbao::request POST auth/token/revoke "{\"token\":${body}}"
}

# @description List ACL policies / Список ACL-политик
openbao::policy::list() { openbao::request LIST sys/policies/acl; }
# @description Read an ACL policy / Прочитать ACL-политику
# @param $1 Name / Имя
openbao::policy::read() { openbao::request GET "sys/policies/acl/${1:?policy name required}"; }
# @description Write an ACL policy from a file / Записать ACL-политику из файла
# @param $1 Name / Имя
# @param $2 File / Файл
openbao::policy::write() {
    local -r name="${1:?policy name required}" file="${2:?policy file required}"
    [[ -r "${file}" ]] || { log::error "OpenBao: политика не найдена / policy not found: ${file}"; return "${LIB_ERROR_FILE_NOT_FOUND}"; }
    openbao::__need_jq || return $?
    local policy body
    policy="$(<"${file}")" || return "${LIB_ERROR_FILE_OPERATION}"
    body="$(printf '%s' "${policy}" | "${BS_OPENBAO_JQ}" -Rs '{policy: .}')" || return "${OPENBAO_ERROR_JSON}"
    openbao::request PUT "sys/policies/acl/${name}" "${body}"
}

# @description List mounts / Список mount
openbao::mount::list() { openbao::request GET sys/mounts; }
# @description Enable a mount / Включить mount
# @param $1 Path / Путь
# @param $2 Type / Тип
openbao::mount::enable() {
    local -r path="${1:?mount path required}" type="${2:?mount type required}"
    local body
    body="$(printf '%s' "${type}" | "${BS_OPENBAO_JQ}" -Rs '{type: .}')" || return "${OPENBAO_ERROR_JSON}"
    openbao::request POST "sys/mounts/${path}" "${body}"
}
# @description Disable a mount / Отключить mount
# @param $1 Path / Путь
openbao::mount::disable() { openbao::request DELETE "sys/mounts/${1:?mount path required}"; }

# @description List namespaces / Список namespace
openbao::namespace::list() { openbao::request LIST sys/namespaces; }
# @description Create a namespace / Создать namespace
# @param $1 Name / Имя
openbao::namespace::create() { openbao::request POST "sys/namespaces/${1:?namespace required}" '{}'; }
