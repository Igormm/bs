#!/usr/bin/env bash
# @shell bash4 — нужны конструкции bash: double-bracket [[ ]], associative array, /dev/tcp / needs bash constructs: double-bracket [[ ]], associative array, /dev/tcp
#
# lib/integration/webserver.sh — minimal HTTP server toolkit for BS
# lib/integration/webserver.sh — минимальный набор для HTTP-сервера на BS
#
# Что это / What it is
# Набор из трёх примитивов, чтобы собрать HTTP-сервер в стиле CGI/inetd:
#   1. web::read_request  — разобрать ОДИН запрос из stdin;
#   2. web::respond       — записать ОДИН ответ в stdout;
#   3. web::client        — сделать GET через bash /dev/tcp (для проверки).
# A toolkit of three primitives to build a CGI/inetd-style HTTP server:
#   1. web::read_request  — parse ONE request from stdin;
#   2. web::respond       — write ONE response to stdout;
#   3. web::client        — do a GET over bash /dev/tcp (for testing).
#
# Модель конкурентности / Concurrency model
# Это НЕ event loop. Одно соединение = один процесс: внешний listener (socat /
# nc / inetd) принимает соединение и запускает обработчик, у которого stdin —
# запрос, stdout — ответ. Обработчик читает один запрос, пишет один ответ и
# выходит. Просто, безопасно (изоляция процессов), но дорого на fork.
# This is NOT an event loop. One connection = one process: an external listener
# (socat / nc / inetd) accepts the connection and runs a handler whose stdin is
# the request and stdout is the response. The handler reads one request, writes
# one response and exits. Simple and safe (process isolation) but fork-heavy.
#
# Контракт обработчика / The handler contract
# Обработчик (функция) читает глобалы __web_* и отвечает через web::respond:
#   route() {
#     case "${__web_path}" in
#       /) web::respond 200 OK "hello\n" ;;
#       *) web::respond 404 "Not Found" "" ;;
#     esac
#   }
# The handler (a function) reads the __web_* globals and replies via web::respond.
#
# Ограничения / Limitations
# * Listener делегируется (socat / nc / inetd): bash не умеет bind/listen/accept,
#   а /dev/tcp открывает только ИСХОДЯЩЕЕ соединение (клиент), не входящее.
# * Безопасность: входные данные НЕ санитизируются — путь/заголовки приходят как
#   есть; защита от path traversal и инъекций — задача обработчика.
# * Content-Length считается в СИМВОЛАХ (${#var}), не в байтах: для UTF-8
#   неточен, для ASCII-демо достаточно.
# * keep-alive нет (Connection: close), HTTP/1.1 без чанков.
# * The listener is delegated (socat / nc / inetd): bash cannot bind/listen/
#   accept, and /dev/tcp only opens OUTGOING connections (client), not inbound.
# * Security: inputs are NOT sanitized — path/headers arrive as-is; path
#   traversal and injection protection is the handler's job.
# * Content-Length is counted in CHARACTERS (${#var}), not bytes: wrong for
#   UTF-8, fine for an ASCII demo.
# * No keep-alive (Connection: close), HTTP/1.1 without chunks.
#
# @depends core/const, core/logger, core/utils

# Source Guard / Защита от повторной загрузки
bs::guard "IO_INTEGRATION_WEBSERVER" || return 0

# Зависимости / Dependencies
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh"

# «Объект запроса» / The "request object"
# web::read_request заполняет эти глобалы; обработчик их читает.
# web::read_request fills these globals; the handler reads them.
#
# @global __web_method  — HTTP method (GET/POST/...)
# @global __web_path    — путь из request line (включая ?query)
# @global __web_version — HTTP-версия (HTTP/1.0, HTTP/1.1)
# @global __web_headers — заголовки, ключи в нижнем регистре (host, user-agent)
# @global __web_body    — тело запроса (по Content-Length)
declare -g __web_method=""
declare -g __web_path=""
declare -g __web_version=""
declare -gA __web_headers=()
declare -g __web_body=""

# @description Разобрать ОДИН HTTP-запрос из stdin в глобалы __web_* / Parse ONE
#   HTTP request from stdin into the __web_* globals
# @stdout nothing / ничего
# @return 0 — запрос прочитан / a request was read; 1 — EOF (соединение закрыто)
web::read_request() {
    # сброс предыдущего запроса / reset the previous request
    __web_method=""; __web_path=""; __web_version=""; __web_body=""
    __web_headers=()

    local line rest name val
    # request line: "METHOD PATH VERSION" / строка запроса
    IFS= read -r line || return 1
    line="${line%$'\r'}"                 # снять \r (CRLF-совместимость)
    __web_method="${line%% *}"
    rest="${line#* }"
    __web_path="${rest%% *}"
    __web_version="${rest##* }"

    # заголовки до пустой строки / headers until the blank line
    while IFS= read -r line; do
        line="${line%$'\r'}"
        [[ -z "${line}" ]] && break
        name="${line%%:*}"
        val="${line#*:}"
        val="${val# }"                   # ведущий пробел после ":"
        __web_headers["${name,,}"]="${val}"   # ключ в нижнем регистре / lower-case key
    done

    # тело, если задан Content-Length / the body when Content-Length is set
    local len="${__web_headers[content-length]:-}"
    if [[ "${len}" =~ ^[0-9]+$ ]] && [[ "${len//0/}" != "" ]]; then
        local -r max="${BS_WEB_MAX_BODY:-1048576}"
        # отклоняем слишком большой Content-Length до любой арифметики (защита от
        # переполнения и истощения) / reject an over-large Content-Length before
        # any arithmetic (overflow and exhaustion guard)
        if (( ${#len} > ${#max} )) || { (( ${#len} == ${#max} )) && [[ "${len}" > "${max}" ]]; }; then
            log::error "Content-Length ${len} exceeds BS_WEB_MAX_BODY (${max})"
            return "${E_INVALID}"
        fi
        IFS= read -r -n "${len}" __web_body || true
    fi
    return 0
}

# @description Значение заголовка (регистр не важен) / A header's value (case-insensitive)
# @param $1 Имя заголовка / Header name
# @stdout значение или пусто / the value or nothing
web::header() {
    printf '%s' "${__web_headers[${1,,}]:-}"
}

# @description Записать HTTP-ответ в stdout / Write an HTTP response to stdout
# @param $1 Код статуса / Status code (default 200)
# @param $2 Reason phrase (default OK)
# @param $3 Тело / Body (default empty)
# @param $4 Content-Type (default text/plain; charset=utf-8)
web::respond() {
    local -r status="${1:-200}" reason="${2:-OK}" body="${3:-}" ctype="${4:-text/plain; charset=utf-8}"
    # reject CR/LF in the header fields (response splitting) / отклонить CR/LF в полях заголовка
    case "${status}${reason}${ctype}" in
        *$'\r'*|*$'\n'*)
            log::error "web::respond: status/reason/ctype must not contain CR/LF"
            return "${E_INVALID}" ;;
    esac
    # ответ закрывает соединение / the response closes the connection
    printf 'HTTP/1.1 %s %s\r\n' "${status}" "${reason}"
    printf 'Content-Type: %s\r\n' "${ctype}"
    printf 'Content-Length: %s\r\n' "${#body}"
    printf 'Connection: close\r\n'
    printf '\r\n'
    printf '%s' "${body}"
}

# @description GET через bash /dev/tcp — только КЛИЕНТ / GET over bash /dev/tcp — client ONLY
# @param $1 Хост / Host (default 127.0.0.1)
# @param $2 Порт / Port (default 8080)
# @param $3 Путь / Path (default /)
# @stdout сырой HTTP-ответ / the raw HTTP response
web::client() {
    local -r host="${1:-127.0.0.1}" port="${2:-8080}" path="${3:-/}"
    # /dev/tcp открывает исходящее соединение; слушать оно НЕ умеет
    # /dev/tcp opens an outgoing connection; it cannot listen
    if ! exec 3<>"/dev/tcp/${host}/${port}" 2>/dev/null; then
        log::error "cannot connect to ${host}:${port}"
        return "${E_ERROR}"
    fi
    printf 'GET %s HTTP/1.1\r\nHost: %s:%s\r\nConnection: close\r\n\r\n' "${path}" "${host}" "${port}" >&3
    cat <&3
    exec 3<&- 3>&-
    return 0
}
