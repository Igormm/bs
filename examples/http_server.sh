#!/usr/bin/env bs
# shellcheck shell=bash
# examples/http_server.sh — minimal parameterized HTTP server (socat / nc / inetd)
# examples/http_server.sh — минимальный параметризованный HTTP-сервер (socat / nc / inetd)
#
# Режимы / Modes:
#   ./http_server.sh                 # слушать (бэкенд из $BACKEND: socat|nc|inetd)
#   ./http_server.sh --serve         # обработать ОДИН запрос из stdin (для socat/nc/inetd)
#   ./http_server.sh --client HOST PORT PATH   # GET через /dev/tcp
#
# Пример / Example:
#   PORT=8080 BACKEND=socat ./http_server.sh &      # запустить / start
#   ./http_server.sh --client 127.0.0.1 8080 /      # спросить / request
#   ./http_server.sh --client 127.0.0.1 8080 /time
#
# Ограничение: слушает только через socat/nc/inetd — bash не умеет bind/listen,
# /dev/tcp открывает только исходящие соединения (клиент).
# Limitation: listening needs socat/nc/inetd — bash cannot bind/listen; /dev/tcp
# only opens outgoing connections (the client side).

load "lib/integration/webserver"

PORT="${PORT:-8080}"
BACKEND="${BACKEND:-socat}"
SELF="$(bs::script_dir)/http_server.sh"
BS_BIN="${BS_BIN:-$(command -v bs 2>/dev/null || printf '%s/bs' "${BS_ROOT:-.}")}"

# --- маршрутизация / routing ---
web::route() {
    case "${__web_path}" in
        /)       web::respond 200 OK "hello from BS HTTP server
" ;;
        /time)   web::respond 200 OK "$(date)
" ;;
        /headers) web::respond 200 OK "User-Agent: $(web::header user-agent)
" ;;
        *)       web::respond 404 "Not Found" "no such path: ${__web_path}
" ;;
    esac
}

web::serve() {
    web::read_request || return 0
    web::route
    return 0
}

web::listen() {
    case "${BACKEND}" in
        inetd)
            web::serve ;;
        socat)
            if ! utils::has socat; then log::error "socat not found"; return "${E_ERROR}"; fi
            exec socat TCP-LISTEN:"${PORT}",fork,reuseaddr SYSTEM:"${BS_BIN} run ${SELF} --serve",nofork ;;
        nc)
            while true; do
                nc -l "${PORT}" -e "${BS_BIN} run ${SELF} --serve" 2>/dev/null \
                    || nc -l "${PORT}" -c "${BS_BIN} run ${SELF} --serve" 2>/dev/null || break
            done ;;
        *)
            log::error "Unknown backend: ${BACKEND} (socat|nc|inetd)"
            return "${E_ERROR}" ;;
    esac
}

main() {
    case "${1:-}" in
        --serve) web::serve ;;
        --client) shift; web::client "$@" ;;
        *) web::listen ;;
    esac
}

if bs::is_main; then
    main "$@"
fi
