#!/usr/bin/env bash
# @shell bash4 — нужны конструкции bash: double-bracket [[ ]], associative array, /dev/tcp / needs bash constructs: double-bracket [[ ]], associative array, /dev/tcp
#
# lib/integration/webserver.sh — minimal HTTP server toolkit for BS
# lib/integration/webserver.sh — минимальный набор для HTTP-сервера на BS
#
# Парсер запроса + писатель ответа (чистый bash) и /dev/tcp-клиент для проверки.
# Сам LISTENER делегируется внешней утилите (socat / nc / inetd), потому что bash
# не умеет bind/listen/accept — /dev/tcp открывает только ИСХОДЯЩЕЕ соединение.
# The request parser + response writer (pure bash) and a /dev/tcp client for
# testing. The LISTENER itself is delegated (socat / nc / inetd): bash cannot
# bind/listen/accept — /dev/tcp only opens OUTGOING connections.
#
# @depends core/const, core/logger, core/utils

# Source Guard / Защита от повторной загрузки
bs::guard "IO_INTEGRATION_WEBSERVER" || return 0

# Зависимости / Dependencies
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh"

# @global __web_method — HTTP method (category: state)
# @global __web_path — request path (category: state)
# @global __web_version — HTTP version (category: state)
# @global __web_headers — lowercase header map (category: state)
# @global __web_body — request body (category: state)
declare -g __web_method=""
declare -g __web_path=""
declare -g __web_version=""
declare -gA __web_headers=()
declare -g __web_body=""

# @description Read one HTTP request from stdin into the __web_* globals / Прочитать
#   один HTTP-запрос из stdin в глобалы __web_*
# @return 0 on a request, 1 on EOF
web::read_request() {
    __web_method=""; __web_path=""; __web_version=""; __web_body=""
    __web_headers=()

    local line rest name val
    IFS= read -r line || return 1
    line="${line%$'\r'}"
    __web_method="${line%% *}"
    rest="${line#* }"
    __web_path="${rest%% *}"
    __web_version="${rest##* }"

    while IFS= read -r line; do
        line="${line%$'\r'}"
        [[ -z "${line}" ]] && break
        name="${line%%:*}"
        val="${line#*:}"
        val="${val# }"
        __web_headers["${name,,}"]="${val}"
    done

    local len="${__web_headers[content-length]:-}"
    if [[ "${len}" =~ ^[0-9]+$ ]] && (( len > 0 )); then
        IFS= read -r -n "${len}" __web_body || true
    fi
    return 0
}

# @description Get a header value (case-insensitive) / Значение заголовка (без учёта регистра)
# @param $1 Header name / Имя заголовка
# @stdout value / значение
web::header() {
    printf '%s' "${__web_headers[${1,,}]:-}"
}

# @description Write an HTTP response to stdout / Записать HTTP-ответ в stdout
# @param $1 Status code / Код
# @param $2 Reason phrase / Пояснение
# @param $3 Body / Тело
# @param $4 Content-Type / Тип
web::respond() {
    local -r status="${1:-200}" reason="${2:-OK}" body="${3:-}" ctype="${4:-text/plain; charset=utf-8}"
    # Content-Length в символах, не байтах: для UTF-8 не совпадает с байтами,
    # для ASCII-демо достаточно / Content-Length is in characters, not bytes:
    # wrong for UTF-8, fine for an ASCII demo
    printf 'HTTP/1.1 %s %s\r\n' "${status}" "${reason}"
    printf 'Content-Type: %s\r\n' "${ctype}"
    printf 'Content-Length: %s\r\n' "${#body}"
    printf 'Connection: close\r\n'
    printf '\r\n'
    printf '%s' "${body}"
}

# @description GET via bash /dev/tcp (client only) / GET через bash /dev/tcp (только клиент)
# @param $1 Host / Хост
# @param $2 Port / Порт
# @param $3 Path / Путь
web::client() {
    local -r host="${1:-127.0.0.1}" port="${2:-8080}" path="${3:-/}"
    if ! exec 3<>"/dev/tcp/${host}/${port}" 2>/dev/null; then
        log::error "cannot connect to ${host}:${port}"
        return "${E_ERROR}"
    fi
    printf 'GET %s HTTP/1.1\r\nHost: %s:%s\r\nConnection: close\r\n\r\n' "${path}" "${host}" "${port}" >&3
    cat <&3
    exec 3<&- 3>&-
    return 0
}
