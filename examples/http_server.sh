#!/usr/bin/env bs
# shellcheck shell=bash
# examples/http_server.sh — minimal parameterized HTTP server (socat / nc / inetd)
# examples/http_server.sh — минимальный параметризованный HTTP-сервер (socat / nc / inetd)
#
# Как это устроено / How it works
# Скрипт делится на ДВЕ части:
#   * ПРИЛОЖЕНИЕ (routing) — функция web::route: смотрит __web_path и отвечает.
#   * СЕРВЕР (listener)   — web::listen: принимает соединения и на каждое
#     запускает этот же скрипт в режиме --serve (один запрос → один ответ → выход).
# The script is split into TWO parts:
#   * APPLICATION (routing) — web::route reads __web_path and replies.
#   * SERVER (listener)     — web::listen accepts connections and, for each,
#     runs this very script in --serve mode (one request → one response → exit).
#
# Режимы / Modes
#   ./http_server.sh                          # слушать (бэкенд из $BACKEND)
#   ./http_server.sh --serve                  # обработать ОДИН запрос из stdin
#   ./http_server.sh --client HOST PORT PATH  # GET через /dev/tcp
#
# Запуск / Usage
#   PORT=8080 BACKEND=socat ./bs run examples/http_server.sh &   # сервер / server
#   ./bs run examples/http_server.sh --client 127.0.0.1 8080 /   # запрос / request
#
# Параметры / Parameters:
#   PORT     — порт (default 8080)
#   BACKEND  — socat | nc | inetd (default socat)
#   BS_BIN   — путь к bs (для перезапуска обработчика; default: bs из PATH)
#
# Ограничение / Limitation
# Слушать можно только через socat/nc/inetd: bash не умеет bind/listen, а
# /dev/tcp открывает только исходящие соединения (клиентская часть).
# Listening needs socat/nc/inetd: bash cannot bind/listen; /dev/tcp only opens
# outgoing connections (the client side).

load "lib/integration/webserver"

# --- параметры транспорта / transport parameters ------------------------------
PORT="${PORT:-8080}"
BACKEND="${BACKEND:-socat}"
SELF="$(bs::script_dir)/http_server.sh"    # путь к себе, чтобы socat/nc перезапускали
BS_BIN="${BS_BIN:-$(command -v bs 2>/dev/null || printf '%s/bs' "${BS_ROOT:-.}")}"

# ПРИЛОЖЕНИЕ / APPLICATION
# Здесь — только маршруты. Обработчик читает __web_path и отвечает через
# web::respond. Замени web::route на своё, чтобы сделать другое приложение.
# Here are the routes only. The handler reads __web_path and replies via
# web::respond. Replace web::route to build a different application.
web::route() {
    case "${__web_path}" in
        /)        web::respond 200 OK $'hello from BS HTTP server\n' ;;
        /time)    web::respond 200 OK "$(date)"$'\n' ;;
        /headers) web::respond 200 OK "User-Agent: $(web::header user-agent)"$'\n' ;;
        *)        web::respond 404 "Not Found" "no such path: ${__web_path}"$'\n' ;;
    esac
}

# СЕРВЕР / SERVER

# Одна итерация: прочитать запрос → маршрут → ответ → выход.
# One iteration: read a request → route → respond → exit.
web::serve() {
    web::read_request || return 0
    web::route
    return 0
}

# Listener: принимает соединения и на каждое форкает этот скрипт в --serve.
# The listener: accepts connections and forks this script in --serve per one.
web::listen() {
    # PORT попадает в адрес socat/nc — проверяем, что это число 1..65535, иначе
    # в адрес можно внедрить директивы / PORT goes into the socat/nc address —
    # require an integer 1..65535, or directives could be injected
    if [[ ! "${PORT}" =~ ^[0-9]+$ ]] || (( ${#PORT} > 5 )) || (( PORT < 1 || PORT > 65535 )); then
        log::error "Invalid PORT: ${PORT} (1-65535)"
        return "${E_INVALID}"
    fi
    case "${BACKEND}" in
        inetd)
            # inetd/systemd-socket уже передал соединение на stdin/stdout
            # inetd/systemd-socket already handed the connection to stdin/stdout
            web::serve ;;
        socat)
            if ! utils::has socat; then log::error "socat not found"; return "${E_ERROR}"; fi
            # fork + reuseaddr: на каждое соединение — новый процесс-обработчик
            # fork + reuseaddr: one handler process per connection
            exec socat TCP-LISTEN:"${PORT}",fork,reuseaddr SYSTEM:"${BS_BIN} run ${SELF} --serve",nofork ;;
        nc)
            # -e (GNU netcat) или -c (некоторые сборки): обработчик на соединение
            # -e (GNU netcat) or -c (some builds): a handler per connection
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
        --serve)  web::serve ;;
        --client) shift; web::client "$@" ;;
        *)        web::listen ;;
    esac
}

if bs::is_main; then
    main "$@"
fi
