#!/usr/bin/env bs
# shellcheck shell=bash
# lib/network/vpn/core.sh — core control (sing-box, Xray): install, start/stop, status,
# API (traffic, live server switch, delay), latency tests, exit IP, systemd
# lib/network/vpn/core.sh — управление ядрами (sing-box, Xray): установка, запуск/остановка,
# статус, API (трафик, смена сервера на лету, задержка), замеры, внешний IP, systemd
#
# Two cores: sing-box is the main one (every protocol, TUN, Clash API), Xray
# takes the profiles only it can dial (XHTTP, VLESS encryption). The "core"
# setting picks one: auto chooses by the selected profile. Only one core runs
# at a time; the config holds the profiles of the group that core can dial.
# Два ядра: sing-box основное (все протоколы, TUN, Clash API), Xray берёт
# профили, к которым умеет подключаться только он (XHTTP, шифрование VLESS).
# Настройка «core» выбирает ядро: auto — по выбранному профилю. Работает
# одно ядро; в конфиг идут профили группы, которые это ядро умеет.
#
# The core runs detached from the terminal (setsid/nohup), so the TUI and the
# CLI may exit while the tunnel stays up. TUN mode needs root: without it the
# core is started through "sudo -n" and a clear error is returned when sudo
# would ask for a password.
# Ядро работает отдельно от терминала (setsid/nohup): TUI и CLI можно закрыть,
# туннель останется. Режиму TUN нужен root: без него ядро запускается через
# «sudo -n», а если sudo спросит пароль — возвращается понятная ошибка.
#
# @depends core/lang, core/const, lib/network/vpn/link, lib/network/vpn/store, lib/network/vpn/singbox, lib/network/vpn/xray
# @tier gnu-linux
# @shell bash4 — нужны конструкции bash: double-bracket [[ ]], arithmetic command (( )), array, nameref, local/declare flags / needs bash constructs: double-bracket [[ ]], arithmetic command (( )), array, nameref, local/declare flags

# Source Guard / Защита от повторной загрузки
bs::guard "LIB_NETWORK_VPN_CORE" || return 0

# Dependencies / Зависимости
bs::source_relative "../../../core/lang.sh" "../../../core/const.sh" "link.sh" "store.sh" "singbox.sh" "xray.sh"

# @global VPN_CORE_RELEASE_BASE — Vpn core: sing-box release download base URL (category: hook)
# @global VPN_CORE_RELEASE_BASE — Vpn core: базовый URL загрузки релизов sing-box (категория: hook)
declare -g VPN_CORE_RELEASE_BASE="${BS_VPN_RELEASE_BASE:-https://github.com/SagerNet/sing-box/releases/download}"
# @global VPN_CORE_RELEASE_API — Vpn core: URL of the sing-box latest-release API (category: hook)
# @global VPN_CORE_RELEASE_API — Vpn core: URL API последнего релиза sing-box (категория: hook)
declare -g VPN_CORE_RELEASE_API="${BS_VPN_RELEASE_API:-https://api.github.com/repos/SagerNet/sing-box/releases/latest}"
# @global VPN_CORE_XRAY_RELEASE_BASE — Vpn core: Xray release download base URL (category: hook)
# @global VPN_CORE_XRAY_RELEASE_BASE — Vpn core: базовый URL загрузки релизов Xray (категория: hook)
declare -g VPN_CORE_XRAY_RELEASE_BASE="${BS_VPN_XRAY_RELEASE_BASE:-https://github.com/XTLS/Xray-core/releases/download}"
# @global VPN_CORE_XRAY_RELEASE_API — Vpn core: URL of the Xray latest-release API (category: hook)
# @global VPN_CORE_XRAY_RELEASE_API — Vpn core: URL API последнего релиза Xray (категория: hook)
declare -g VPN_CORE_XRAY_RELEASE_API="${BS_VPN_XRAY_RELEASE_API:-https://api.github.com/repos/XTLS/Xray-core/releases/latest}"
# @global VPN_CORE_MIN_VERSION — Vpn core: oldest supported sing-box (category: constant)
# @global VPN_CORE_MIN_VERSION — Vpn core: самая старая поддерживаемая версия sing-box (категория: constant)
readonly VPN_CORE_MIN_VERSION="1.12"
# @global VPN_CORE_XRAY_MIN_VERSION — Vpn core: oldest supported Xray (XHTTP, api.listen) (category: constant)
# @global VPN_CORE_XRAY_MIN_VERSION — Vpn core: самая старая поддерживаемая версия Xray (XHTTP, api.listen) (категория: constant)
readonly VPN_CORE_XRAY_MIN_VERSION="24.11"
# @global VPN_CORE_GROUP_LIMIT — Vpn core: max profiles of a group put into one config (category: constant)
# @global VPN_CORE_GROUP_LIMIT — Vpn core: максимум профилей группы в одном конфиге (категория: constant)
readonly VPN_CORE_GROUP_LIMIT=200
# @global VPN_CORE_PRUNED — Vpn core: ids dropped by the last config check (category: state)
# @global VPN_CORE_PRUNED — Vpn core: id, отброшенные последней проверкой конфига (категория: state)
declare -ga VPN_CORE_PRUNED=()
# @global VPN_CORE_IDS — Vpn core: ids that went into the last config (category: state)
# @global VPN_CORE_IDS — Vpn core: id, попавшие в последний конфиг (категория: state)
declare -ga VPN_CORE_IDS=()
# @global VPN_CORE_ENGINE — Vpn core: core the next config is built for: sing-box|xray (category: state)
# @global VPN_CORE_ENGINE — Vpn core: ядро, для которого собирается следующий конфиг: sing-box|xray (категория: state)
declare -g VPN_CORE_ENGINE="sing-box"
# @global VPN_XRAY_VERSION — Vpn core: version of the installed Xray, set by vpn::core::require xray (category: state)
# @global VPN_XRAY_VERSION — Vpn core: версия установленного Xray, задаёт vpn::core::require xray (категория: state)
declare -g VPN_XRAY_VERSION=""

# Binary / Бинарник

# @description Directory for the downloaded cores / Каталог скачанных ядер.
# @stdout path / путь
vpn::core::bin_dir() {
    printf '%s\n' "${BS_VPN_BIN_DIR:-${XDG_DATA_HOME:-${HOME}/.local/share}/bs/vpn/bin}"
}

# @private
# @description Is the engine name known? / Известно ли имя ядра?
vpn::core::__engine_ok() {
    [[ "${1-}" == "sing-box" || "${1-}" == "xray" ]] || {
        printf 'неизвестное ядро / unknown core: %s (sing-box|xray)\n' "${1-}" >&2
        return "${LIB_ERROR_INVALID_ARGS}"
    }
}

# @description Path of a core binary: the override variable, the downloaded one, then PATH.
# @description Путь к бинарнику ядра: переменная-переопределение, скачанный, затем PATH.
#   sing-box: BS_VPN_CORE; xray: BS_VPN_XRAY.
# @param $1 [optional] engine: sing-box (default) | xray / ядро
# @stdout path / путь
# @return 0 found, LIB_ERROR_DEPENDENCY_MISSING not found
vpn::core::bin() {
    local -r engine="${1:-sing-box}"
    vpn::core::__engine_ok "${engine}" || return $?
    local override="${BS_VPN_CORE:-}"
    [[ "${engine}" == "xray" ]] && override="${BS_VPN_XRAY:-}"
    if is::not_empty "${override}"; then
        is::executable "${override}" && { printf '%s\n' "${override}"; return 0; }
        return "${LIB_ERROR_DEPENDENCY_MISSING}"
    fi
    local -r local_bin="$(vpn::core::bin_dir)/${engine}"
    is::executable "${local_bin}" && { printf '%s\n' "${local_bin}"; return 0; }
    if is::command "${engine}"; then
        command -v "${engine}"
        return 0
    fi
    return "${LIB_ERROR_DEPENDENCY_MISSING}"
}

# @description Installed core version (X.Y.Z), empty when unknown.
# @description Версия установленного ядра (X.Y.Z), пусто, если неизвестна.
# @param $1 [optional] engine (default sing-box) / ядро
# @stdout version / версия
vpn::core::version() {
    local bin out
    bin="$(vpn::core::bin "${1:-sing-box}")" || return "${LIB_ERROR_DEPENDENCY_MISSING}"
    out="$("${bin}" version 2>/dev/null | sed -n 1p)"
    if [[ "${out}" =~ ([0-9]+\.[0-9]+\.[0-9]+[^[:space:]]*) ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
    fi
    return 0
}

# @private
# @description Is version $1 >= $2 (X.Y compared)? Empty $1 counts as new enough.
# @description Версия $1 >= $2 (сравниваются X.Y)? Пустая $1 считается достаточно новой.
vpn::core::__ver_ge() {
    local -r have="${1-}" want="${2:?}"
    [[ "${have}" =~ ^([0-9]+)\.([0-9]+) ]] || return 0
    local -ri hmaj="${BASH_REMATCH[1]}" hmin="${BASH_REMATCH[2]}"
    [[ "${want}" =~ ^([0-9]+)\.([0-9]+) ]] || return 0
    (( hmaj > BASH_REMATCH[1] || (hmaj == BASH_REMATCH[1] && hmin >= BASH_REMATCH[2]) ))
}

# @description Fail with a hint when the core is missing or too old; sets VPN_SINGBOX_VERSION or VPN_XRAY_VERSION.
# @description Ошибка с подсказкой, если ядра нет или оно старое; задаёт VPN_SINGBOX_VERSION или VPN_XRAY_VERSION.
# @param $1 [optional] engine (default sing-box) / ядро
# @return 0 ok, LIB_ERROR_DEPENDENCY_MISSING missing, LIB_ERROR_DEPENDENCY too old
vpn::core::require() {
    local -r engine="${1:-sing-box}"
    vpn::core::__engine_ok "${engine}" || return $?
    if ! vpn::core::bin "${engine}" >/dev/null; then
        printf 'ядро %s не найдено: выполните «vpn core install %s» / %s not found: run "vpn core install %s"\n' \
            "${engine}" "${engine}" "${engine}" "${engine}" >&2
        return "${LIB_ERROR_DEPENDENCY_MISSING}"
    fi
    local version min="${VPN_CORE_MIN_VERSION}"
    version="$(vpn::core::version "${engine}")"
    if [[ "${engine}" == "xray" ]]; then
        VPN_XRAY_VERSION="${version}"
        min="${VPN_CORE_XRAY_MIN_VERSION}"
    else
        VPN_SINGBOX_VERSION="${version}"
    fi
    if is::not_empty "${version}" && ! vpn::core::__ver_ge "${version}" "${min}"; then
        printf '%s %s слишком старый, нужен >= %s / too old, need >= %s\n' \
            "${engine}" "${version}" "${min}" "${min}" >&2
        return "${LIB_ERROR_DEPENDENCY}"
    fi
    return 0
}

# @description Release platform suffix for this machine (linux-amd64, darwin-arm64 …).
# @description Суффикс платформы релиза для этой машины (linux-amd64, darwin-arm64 …).
# @stdout os-arch
# @return 0 ok, LIB_ERROR_PLATFORM_UNSUPPORTED unknown
vpn::core::platform() {
    local os arch
    os="$(uname -s 2>/dev/null)"
    arch="$(uname -m 2>/dev/null)"
    case "${os}" in
        Linux) os="linux" ;;
        Darwin) os="darwin" ;;
        FreeBSD) os="freebsd" ;;
        *) return "${LIB_ERROR_PLATFORM_UNSUPPORTED}" ;;
    esac
    case "${arch}" in
        x86_64|amd64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        armv7*|armv8l) arch="armv7" ;;
        armv6*) arch="armv6" ;;
        i?86) arch="386" ;;
        riscv64) arch="riscv64" ;;
        s390x) arch="s390x" ;;
        loongarch64) arch="loong64" ;;
        *) return "${LIB_ERROR_PLATFORM_UNSUPPORTED}" ;;
    esac
    printf '%s-%s\n' "${os}" "${arch}"
}

# @description Xray release asset name for a platform (linux-amd64 → Xray-linux-64.zip).
# @description Имя архива релиза Xray для платформы (linux-amd64 → Xray-linux-64.zip).
# @param $1 [optional] platform (default: this machine) / платформа
# @stdout asset name / имя архива
# @return 0 ok, LIB_ERROR_PLATFORM_UNSUPPORTED no such build
vpn::core::xray_asset() {
    local platform="${1-}"
    is::empty "${platform}" && { platform="$(vpn::core::platform)" || return $?; }
    local os="${platform%%-*}" arch="${platform#*-}"
    [[ "${os}" == "darwin" ]] && os="macos"
    case "${arch}" in
        amd64) arch="64" ;;
        386) arch="32" ;;
        arm64) arch="arm64-v8a" ;;
        armv7) arch="arm32-v7a" ;;
        armv6) arch="arm32-v6" ;;
        riscv64|s390x|loong64) [[ "${os}" == "linux" ]] || return "${LIB_ERROR_PLATFORM_UNSUPPORTED}" ;;
        *) return "${LIB_ERROR_PLATFORM_UNSUPPORTED}" ;;
    esac
    printf 'Xray-%s-%s.zip\n' "${os}" "${arch}"
}

# @description Latest released version of a core: the GitHub API, then the redirect of ".../releases/latest".
# @description Последняя версия ядра: GitHub API, затем редирект «.../releases/latest».
#   The fallback helps when the API is rate limited (60 requests an hour without a token).
#   Запасной путь выручает, когда API упирается в лимит (60 запросов в час без токена).
# @param $1 [optional] engine (default sing-box) / ядро
# @stdout X.Y.Z
vpn::core::latest_version() {
    local api="${VPN_CORE_RELEASE_API}" base="${VPN_CORE_RELEASE_BASE}"
    if [[ "${1:-sing-box}" == "xray" ]]; then
        api="${VPN_CORE_XRAY_RELEASE_API}"
        base="${VPN_CORE_XRAY_RELEASE_BASE}"
    fi
    local body="" re='"tag_name"[[:space:]]*:[[:space:]]*"v?([0-9]+\.[0-9]+\.[0-9]+)"'
    body="$(vpn::sub::fetch "${api}" 2>/dev/null)" || body=""
    if [[ "${body}" =~ ${re} ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi
    # https://github.com/<repo>/releases/latest → 302 на / to .../releases/tag/vX.Y.Z
    if is::command curl && [[ "${base}" == */releases/download ]]; then
        body="$(curl -sS -o /dev/null -m 15 -w '%{redirect_url}' "${base%/download}/latest" 2>/dev/null)" || body=""
        if [[ "${body}" =~ /tag/v?([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
            printf '%s\n' "${BASH_REMATCH[1]}"
            return 0
        fi
    fi
    printf 'не удалось узнать последнюю версию: укажите её явно («vpn core install %s X.Y.Z») / cannot read the latest version: pass it explicitly\n' "${1:-sing-box}" >&2
    return "${LIB_ERROR_INVALID_INPUT}"
}

# @private
# @description Unpack a zip archive (unzip, bsdtar or busybox unzip).
# @description Распаковать zip (unzip, bsdtar или busybox unzip).
# @param $1 archive, $2 directory / архив, каталог
vpn::core::__unzip() {
    if is::command unzip; then
        unzip -qo "$1" -d "$2"
    elif is::command bsdtar; then
        bsdtar -xf "$1" -C "$2"
    elif is::command busybox; then
        busybox unzip -qo "$1" -d "$2"
    else
        printf 'нужен unzip / unzip required\n' >&2
        return "${LIB_ERROR_DEPENDENCY_MISSING}"
    fi
}

# @description Download and install a core into bin_dir, with the files it needs next to it.
# @description Скачать и установить ядро в bin_dir вместе с нужными ему файлами.
#   sing-box: the binary and libcronet.so (NaiveProxy) when the build ships it;
#   xray: the binary, geoip.dat and geosite.dat (routing presets).
#   sing-box: бинарник и libcronet.so (NaiveProxy), если сборка его содержит;
#   xray: бинарник, geoip.dat и geosite.dat (пресеты маршрутизации).
# @param $1 [optional] engine sing-box|xray (default sing-box); a version here means sing-box
# @param $2 [optional] version X.Y.Z (default: latest) / версия
# @stdout installed binary path / путь установленного бинарника
# @return 0 ok, LIB_ERROR_DEPENDENCY_MISSING no tar/unzip, LIB_ERROR_FILE_OPERATION failed
vpn::core::install() {
    local engine="${1:-sing-box}" version="${2-}"
    # совместимость: «install 1.14.4» — версия sing-box / compatibility: "install 1.14.4" is a sing-box version
    if [[ "${engine}" =~ ^v?[0-9] ]]; then
        version="${engine}"
        engine="sing-box"
    fi
    vpn::core::__engine_ok "${engine}" || return $?
    local platform
    platform="$(vpn::core::platform)" || {
        printf 'платформа не поддерживается / unsupported platform: %s %s\n' "$(uname -s)" "$(uname -m)" >&2
        return "${LIB_ERROR_PLATFORM_UNSUPPORTED}"
    }
    is::empty "${version}" && { version="$(vpn::core::latest_version "${engine}")" || return $?; }
    version="${version#v}"
    [[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$ ]] || {
        printf 'неверная версия / invalid version: %s\n' "${version}" >&2
        return "${LIB_ERROR_INVALID_ARGS}"
    }
    local url src_dir tmp
    local -a files=()
    tmp="$(mktemp -d)" || return "${LIB_ERROR_FILE_OPERATION}"
    if [[ "${engine}" == "xray" ]]; then
        local asset
        asset="$(vpn::core::xray_asset "${platform}")" || {
            rm -rf "${tmp}"
            printf 'нет сборки Xray для / no Xray build for %s\n' "${platform}" >&2
            return "${LIB_ERROR_PLATFORM_UNSUPPORTED}"
        }
        url="${VPN_CORE_XRAY_RELEASE_BASE}/v${version}/${asset}"
        src_dir="${tmp}/x"
        files=(xray geoip.dat geosite.dat)
    else
        is::command tar || { rm -rf "${tmp}"; printf 'нужен tar / tar required\n' >&2; return "${LIB_ERROR_DEPENDENCY_MISSING}"; }
        local -r name="sing-box-${version}-${platform}"
        url="${VPN_CORE_RELEASE_BASE}/v${version}/${name}.tar.gz"
        src_dir="${tmp}/x/${name}"
        files=(sing-box libcronet.so)
    fi
    printf 'загрузка / downloading %s\n' "${url}" >&2
    mkdir -p "${tmp}/x"
    local ok=1
    if vpn::sub::fetch "${url}" > "${tmp}/core.pkg"; then
        if [[ "${engine}" == "xray" ]]; then
            vpn::core::__unzip "${tmp}/core.pkg" "${tmp}/x" >/dev/null || ok=0
        else
            tar -xzf "${tmp}/core.pkg" -C "${tmp}/x" || ok=0
        fi
    else
        ok=0
    fi
    if (( ok == 0 )) || ! is::file "${src_dir}/${engine}"; then
        rm -rf "${tmp}"
        printf 'загрузка не удалась / download failed: %s\n' "${url}" >&2
        return "${LIB_ERROR_FILE_OPERATION}"
    fi
    local -r dir="$(vpn::core::bin_dir)"
    local f
    mkdir -p "${dir}" || ok=0
    # каждый файл ставится через .new + mv, чтобы работающее ядро не увидело половину файла
    # each file goes through .new + mv so a running core never sees half a file
    for f in "${files[@]}"; do
        is::file "${src_dir}/${f}" || continue
        cp -f "${src_dir}/${f}" "${dir}/${f}.new" && mv -f "${dir}/${f}.new" "${dir}/${f}" || ok=0
    done
    chmod 755 "${dir}/${engine}" 2>/dev/null || ok=0
    rm -rf "${tmp}"
    if (( ok == 0 )); then
        printf 'установка не удалась / install failed: %s\n' "${dir}" >&2
        return "${LIB_ERROR_FILE_OPERATION}"
    fi
    printf '%s\n' "${dir}/${engine}"
}

# @description Directory with geoip.dat and geosite.dat for Xray, empty when there is none.
# @description Каталог с geoip.dat и geosite.dat для Xray, пусто, если его нет.
# @stdout path / путь
# @return 0 found, 1 not found
vpn::core::xray_assets() {
    local bin="" dir
    bin="$(vpn::core::bin xray 2>/dev/null)" || bin=""
    for dir in "${XRAY_LOCATION_ASSET:-}" "${bin%/*}" /usr/local/share/xray /usr/share/xray; do
        is::empty "${dir}" && continue
        if is::file "${dir}/geoip.dat" && is::file "${dir}/geosite.dat"; then
            printf '%s\n' "${dir}"
            return 0
        fi
    done
    return 1
}

# Runtime files / Файлы состояния

# @private
vpn::core::__f() {
    printf '%s/%s\n' "$(vpn::store::state)" "$1"
}

# @description Path of the core log / Путь журнала ядра.
vpn::core::log_file() {
    vpn::core::__f core.log
}

# @description Path of the generated config / Путь сгенерированного конфига.
vpn::core::config_file() {
    vpn::core::__f config.json
}

# @private
# @description Run a command as root when needed: directly as root, otherwise sudo -n.
# @description Выполнить команду от root при необходимости: напрямую под root, иначе sudo -n.
vpn::core::__as_root() {
    if (( EUID == 0 )); then
        "$@"
    elif is::command sudo; then
        sudo -n "$@"
    else
        return "${LIB_ERROR_PERMISSION_DENIED}"
    fi
}

# @description Can root commands run without a password prompt now?
# @description Можно ли сейчас выполнять команды root без запроса пароля?
# @return 0 yes, 1 no
vpn::core::root_ready() {
    (( EUID == 0 )) && return 0
    is::command sudo && sudo -n true 2>/dev/null
}

# @description Pid of the running core, empty when not running.
# @description Pid работающего ядра, пусто, если не работает.
# @stdout pid
# @return 0 running, 1 not running
vpn::core::pid() {
    local -r file="$(vpn::core::__f core.pid)"
    is::file "${file}" || return 1
    local pid
    pid="$(head -n 1 "${file}" 2>/dev/null)"
    is::number "${pid}" || return 1
    if is::dir /proc; then
        is::dir "/proc/${pid}" || return 1
        # pid мог достаться чужому процессу: в его командной строке должен быть наш конфиг
        # the pid may have been reused: its command line must name our config
        local cmdline=""
        cmdline="$(tr '\0' ' ' < "/proc/${pid}/cmdline" 2>/dev/null)"
        [[ -z "${cmdline}" || "${cmdline}" == *"$(vpn::core::config_file)"* ]] || return 1
    else
        ps -p "${pid}" >/dev/null 2>&1 || return 1
    fi
    printf '%s\n' "${pid}"
}

# @description Is the core running? / Работает ли ядро?
# @return 0 yes, 1 no
vpn::core::running() {
    vpn::core::pid >/dev/null
}

# @private
# @description Session fields of the running core ("key=value": id, engine, mode, route, started, ids).
# @description Поля сессии работающего ядра («ключ=значение»: id, engine, mode, route, started, ids).
vpn::core::session_get() {
    local -r file="$(vpn::core::__f session)" key="${1:?key required}"
    is::file "${file}" || return 0
    local line
    while IFS= read -r line; do
        [[ "${line}" == "${key}="* ]] && { printf '%s\n' "${line#*=}"; return 0; }
    done < "${file}"
    return 0
}

# Engine choice / Выбор ядра

# @description Core that serves a profile under the "core" setting.
# @description Ядро, которое обслуживает профиль при текущей настройке «core».
#   auto: Xray when only Xray can dial the profile, sing-box otherwise.
#   auto: Xray, если к профилю умеет подключаться только Xray, иначе sing-box.
# @param $1 id
# @stdout sing-box|xray
# @return 0 ok, LIB_ERROR_FILE_NOT_FOUND no profile,
#   LIB_ERROR_INVALID_INPUT the forced core cannot dial the profile (reason on stderr)
vpn::core::engine_for() {
    local -A p=()
    vpn::store::load "${1-}" p || return $?
    local need setting
    need="$(vpn::link::core_need p)"
    setting="$(vpn::settings::get core)"
    if [[ "${setting}" == "xray" ]] && ! vpn::xray::supports p; then
        printf 'профиль %s не поддерживается Xray (настройка core=xray) / not supported by Xray\n' "${1}" >&2
        return "${LIB_ERROR_INVALID_INPUT}"
    fi
    if [[ "${setting}" == "sing-box" && "${need}" == "xray" ]]; then
        printf 'профилю %s нужен Xray (XHTTP или шифрование VLESS), а настройка core=sing-box / needs Xray\n' "${1}" >&2
        return "${LIB_ERROR_INVALID_INPUT}"
    fi
    case "${setting}" in
        sing-box|xray) printf '%s\n' "${setting}" ;;
        *) if [[ "${need}" == "xray" ]]; then printf 'xray\n'; else printf 'sing-box\n'; fi ;;
    esac
}

# @description Core of the running session, else the one the active profile would use.
# @description Ядро работающей сессии, иначе то, что взял бы активный профиль.
# @stdout sing-box|xray
vpn::core::engine() {
    local engine=""
    vpn::core::running && engine="$(vpn::core::session_get engine)"
    if is::empty "${engine}"; then
        local -r active="$(vpn::settings::get active)"
        is::not_empty "${active}" && engine="$(vpn::core::engine_for "${active}" 2>/dev/null)"
    fi
    printf '%s\n' "${engine:-sing-box}"
}

# @description Can this core dial the profile? / Умеет ли это ядро подключаться к профилю?
# @param $1 engine, $2 id
# @return 0 yes, 1 no
vpn::core::engine_can() {
    local -A p=()
    vpn::store::load "${2-}" p 2>/dev/null || return 1
    if [[ "${1-}" == "xray" ]]; then
        vpn::xray::supports p
    else
        [[ "$(vpn::link::core_need p)" != "xray" ]]
    fi
}

# Config / Конфиг

# @description Profile ids that go into a config for the selected profile: it first, then its group.
# @description Id профилей для конфига выбранного профиля: он первым, затем его группа.
#   Members the core cannot dial are left out.
#   Профили, к которым ядро не умеет подключаться, пропускаются.
# @param $1 selected id / выбранный id
# @param $2 [optional] engine (default: vpn::core::engine_for) / ядро
# @stdout ids
vpn::core::config_ids() {
    local -r selected="${1:?id required}"
    local engine="${2-}"
    is::empty "${engine}" && engine="$(vpn::core::engine_for "${selected}" 2>/dev/null || printf 'sing-box')"
    printf '%s\n' "${selected}"
    local group id
    local -i n=1
    group="$(vpn::store::field "${selected}" group)"
    while IFS= read -r id; do
        [[ "${id}" == "${selected}" ]] && continue
        (( n >= VPN_CORE_GROUP_LIMIT )) && break
        vpn::core::engine_can "${engine}" "${id}" || continue
        printf '%s\n' "${id}"
        n=$(( n + 1 ))
    done < <(vpn::store::ids "${group:-manual}")
}

# @private
# @description Environment for running Xray: where its geo files are / Окружение запуска Xray: где его geo-файлы.
# @stdout "XRAY_LOCATION_ASSET=dir" or nothing
vpn::core::__xray_env() {
    local dir
    dir="$(vpn::core::xray_assets)" && printf 'XRAY_LOCATION_ASSET=%s\n' "${dir}"
    return 0
}

# @description Check a config file with the core ("sing-box check" or "xray run -test").
# @description Проверить файл конфига ядром («sing-box check» или «xray run -test»).
# @param $1 config file / файл конфига
# @param $2 [optional] engine (default VPN_CORE_ENGINE) / ядро
# @stdout check output on failure / вывод проверки при ошибке
# @return 0 valid, LIB_ERROR_INVALID_INPUT invalid
vpn::core::check() {
    local -r file="${1:?config required}" engine="${2:-${VPN_CORE_ENGINE}}"
    local bin out
    bin="$(vpn::core::bin "${engine}")" || return "${LIB_ERROR_DEPENDENCY_MISSING}"
    if [[ "${engine}" == "xray" ]]; then
        local -a env=()
        local e
        e="$(vpn::core::__xray_env)"
        is::not_empty "${e}" && env=("${e}")
        out="$(env "${env[@]}" "${bin}" run -test -format json -c "${file}" 2>&1)" && return 0
    else
        out="$("${bin}" check -c "${file}" 2>&1)" && return 0
    fi
    printf '%s\n' "${out}"
    return "${LIB_ERROR_INVALID_INPUT}"
}

# @private
# @description Profile id named by a core check error.
# @description Id профиля из ошибки проверки ядра.
#   sing-box: "outbound[N]"/"endpoint[N]" through the index maps of the last config;
#   Xray: "outbound config with tag p:<id>".
#   sing-box: «outbound[N]»/«endpoint[N]» через карты индексов последнего конфига;
#   Xray: «outbound config with tag p:<id>».
# @param $1 check output / вывод проверки
# @stdout id
# @return 0 found, 1 not a profile error
vpn::core::__bad_id() {
    local id=""
    if [[ "${1-}" =~ outbound\ config\ with\ tag\ p:([A-Za-z0-9._-]+) ]]; then
        id="${BASH_REMATCH[1]}"
    elif [[ "${1-}" =~ (outbound|endpoint)s?\[([0-9]+)\] ]]; then
        local -ri n="${BASH_REMATCH[2]}"
        if [[ "${BASH_REMATCH[1]}" == "endpoint" ]]; then
            (( n < ${#VPN_SINGBOX_EP_IDS[@]} )) && id="${VPN_SINGBOX_EP_IDS[n]}"
        else
            (( n < ${#VPN_SINGBOX_OUT_IDS[@]} )) && id="${VPN_SINGBOX_OUT_IDS[n]}"
        fi
    fi
    is::not_empty "${id}" || return 1
    printf '%s\n' "${id}"
}

# @description Build a checked config into a file for VPN_CORE_ENGINE; profiles the core rejects are dropped (VPN_CORE_PRUNED).
# @description Собрать проверенный конфиг для VPN_CORE_ENGINE; профили, отвергнутые ядром, отбрасываются (VPN_CORE_PRUNED).
# @param $1 kind: full|test / вид
# @param $2 output file / выходной файл
# @param $3 [test only] api port (sing-box) or base port (xray) / порт API или базовый порт
# @param $@ ids (selected first for full) / id (выбранный первым для full)
# @return 0 ok, LIB_ERROR_INVALID_INPUT the selected profile or the config itself is invalid
vpn::core::build_config() {
    local -r kind="${1:?kind required}" out="${2:?file required}"
    shift 2
    local port=""
    if [[ "${kind}" == "test" ]]; then
        port="${1:?port required}"
        shift
    fi
    local -a ids=("$@")
    local -r engine="${VPN_CORE_ENGINE}"
    VPN_CORE_PRUNED=()
    local result bad
    local -i tries=0 i
    while (( ${#ids[@]} > 0 && tries <= ${#ids[@]} + 1 )); do
        tries=$(( tries + 1 ))
        case "${engine}:${kind}" in
            sing-box:test) vpn::singbox::test_config "${port}" "${ids[@]}" > "${out}" || return $? ;;
            sing-box:*) vpn::singbox::config "${ids[@]}" > "${out}" || return $? ;;
            xray:test) vpn::xray::test_config "${port}" "${ids[@]}" > "${out}" || return $? ;;
            xray:*) vpn::xray::config "${ids[@]}" > "${out}" || return $? ;;
        esac
        if result="$(vpn::core::check "${out}" "${engine}")"; then
            VPN_CORE_IDS=("${ids[@]}")
            [[ "${engine}:${kind}" == "xray:test" ]] && VPN_CORE_IDS=("${VPN_XRAY_TEST_IDS[@]}")
            [[ "${engine}:${kind}" == "sing-box:test" ]] \
                && VPN_CORE_IDS=("${VPN_SINGBOX_OUT_IDS[@]}" "${VPN_SINGBOX_EP_IDS[@]}")
            return 0
        fi
        bad="$(vpn::core::__bad_id "${result}")" || {
            printf 'конфиг отклонён ядром / config rejected by the core:\n%s\n' "${result}" >&2
            return "${LIB_ERROR_INVALID_INPUT}"
        }
        if [[ "${kind}" == "full" && "${bad}" == "${ids[0]}" ]] || ! arr::contains ids "${bad}"; then
            printf 'профиль отклонён ядром / profile rejected by the core: %s\n%s\n' "${bad}" "${result}" >&2
            return "${LIB_ERROR_INVALID_INPUT}"
        fi
        VPN_CORE_PRUNED+=("${bad}")
        for (( i = 0; i < ${#ids[@]}; i++ )); do
            if [[ "${ids[i]}" == "${bad}" ]]; then
                ids=("${ids[@]:0:i}" "${ids[@]:i+1}")
                break
            fi
        done
    done
    return "${LIB_ERROR_INVALID_INPUT}"
}

# Start / stop / Запуск и остановка

# @private
# @description Command line that runs the core on the generated config, one word per line.
# @description Командная строка запуска ядра на сгенерированном конфиге, по слову в строке.
# @param $1 engine / ядро
vpn::core::__run_cmd() {
    local -r engine="$1"
    local bin
    bin="$(vpn::core::bin "${engine}")" || return "${LIB_ERROR_DEPENDENCY_MISSING}"
    if [[ "${engine}" == "xray" ]]; then
        local e
        e="$(vpn::core::__xray_env)"
        is::not_empty "${e}" && printf 'env\n%s\n' "${e}"
        printf '%s\nrun\n-format\njson\n-c\n%s\n' "${bin}" "$(vpn::core::config_file)"
    else
        printf '%s\nrun\n-c\n%s\n-D\n%s\n' "${bin}" "$(vpn::core::config_file)" "$(vpn::store::state)"
    fi
}

# @private
# @description Launch the core detached; pid goes to core.pid.
# @description Запустить ядро отдельно от терминала; pid пишется в core.pid.
# @param $1 engine, $2 1 = as root / ядро, от root
vpn::core::__launch() {
    local -r engine="$1" as_root="$2"
    local -a run=()
    mapfile -t run < <(vpn::core::__run_cmd "${engine}")
    (( ${#run[@]} > 0 )) || return "${LIB_ERROR_DEPENDENCY_MISSING}"
    local -r log="$(vpn::core::log_file)"
    local -r pidf="$(vpn::core::__f core.pid)"
    # Журнал > 1 МБ — откладываем в .1 / log over 1 MB goes to .1
    if is::file "${log}" && (( $(wc -c < "${log}") > 1048576 )); then
        mv -f "${log}" "${log}.1" 2>/dev/null || : > "${log}"
    fi
    rm -f "${pidf}"
    # shellcheck disable=SC2016 # $$ и $1… раскрываются во внутреннем sh / expand in the inner sh
    local -r inner='p="$1"; shift; echo $$ > "$p"; exec "$@"'
    local -a cmd=(sh -c "${inner}" bs-vpn "${pidf}" "${run[@]}")
    (( as_root == 1 && EUID != 0 )) && cmd=(sudo -n "${cmd[@]}")
    local -a detach=()
    if is::command setsid; then detach=(setsid); else detach=(nohup); fi
    ( "${detach[@]}" "${cmd[@]}" >> "${log}" 2>&1 < /dev/null & )
    return 0
}

# @private
# @description Is a local TCP port accepting connections? / Принимает ли локальный TCP-порт соединения?
vpn::core::__port_open() {
    # shellcheck disable=SC2016 # $1 раскрывает внутренний bash / expanded by the inner bash
    bash -c 'exec 3<>"/dev/tcp/127.0.0.1/$1"' _ "${1:?port required}" 2>/dev/null
}

# @description Start (or restart) the core with a profile; the core is chosen by vpn::core::engine_for.
# @description Запустить (или перезапустить) ядро с профилем; ядро выбирает vpn::core::engine_for.
# @param $1 [optional] profile id (default: the active setting, then the first profile)
# @return 0 started, LIB_ERROR_FILE_NOT_FOUND no profile, LIB_ERROR_PERMISSION_DENIED TUN without root,
#   LIB_ERROR_INVALID_INPUT bad config, LIB_ERROR_TIMEOUT core did not come up,
#   LIB_ERROR_CONFLICT TUN with Xray
vpn::core::start() {
    local id="${1-}"
    is::empty "${id}" && id="$(vpn::settings::get active)"
    is::empty "${id}" && id="$(vpn::store::ids | sed -n 1p)"
    vpn::store::exists "${id}" || {
        printf 'нет профиля / no profile: %s (импортируйте ссылку: vpn import <ссылка>)\n' "${id:-—}" >&2
        return "${LIB_ERROR_FILE_NOT_FOUND}"
    }
    local engine
    engine="$(vpn::core::engine_for "${id}")" || return $?
    vpn::core::require "${engine}" || return $?
    vpn::store::init || return $?
    local -r mode="$(vpn::settings::get mode)"
    local as_root=0
    if [[ "${mode}" == "tun" ]]; then
        if [[ "${engine}" == "xray" ]]; then
            printf 'режим TUN работает только с sing-box; для профилей Xray выберите режим proxy / TUN mode needs sing-box: use proxy mode for Xray profiles\n' >&2
            return "${LIB_ERROR_CONFLICT}"
        fi
        as_root=1
        vpn::core::root_ready || {
            printf 'режиму TUN нужен root: запустите через sudo или выполните «sudo -v» / TUN mode needs root: run with sudo or "sudo -v" first\n' >&2
            return "${LIB_ERROR_PERMISSION_DENIED}"
        }
    fi
    if [[ "${engine}" == "xray" ]]; then
        VPN_XRAY_GEO=0
        vpn::core::xray_assets >/dev/null && VPN_XRAY_GEO=1
        if [[ "${VPN_XRAY_GEO}" == 0 && "$(vpn::settings::get route)" == bypass-* ]]; then
            printf 'нет geoip.dat/geosite.dat для Xray: обход работает только по доменным зонам («vpn core install xray») / no Xray geo files: bypass uses domain zones only\n' >&2
        fi
    fi
    VPN_CORE_ENGINE="${engine}"
    local -a ids=()
    mapfile -t ids < <(vpn::core::config_ids "${id}" "${engine}")
    local -r cfg="$(vpn::core::config_file)"
    vpn::core::build_config full "${cfg}.new" "${ids[@]}" || { rm -f "${cfg}.new"; return "${LIB_ERROR_INVALID_INPUT}"; }
    if (( ${#VPN_CORE_PRUNED[@]} > 0 )); then
        printf 'пропущены профили, которые ядро не принимает / skipped profiles the core rejects: %s\n' \
            "$(IFS=' '; printf '%s' "${VPN_CORE_PRUNED[*]}")" >&2
    fi
    vpn::core::running && vpn::core::stop
    mv -f "${cfg}.new" "${cfg}"
    chmod 600 "${cfg}" 2>/dev/null
    vpn::settings::set active "${id}" >/dev/null
    local -r log="$(vpn::core::log_file)"
    local -i log_from=0
    is::file "${log}" && log_from="$(wc -l < "${log}")"
    vpn::core::__launch "${engine}" "${as_root}" || return $?
    printf 'id=%s\nengine=%s\nmode=%s\nroute=%s\nstarted=%s\nids=%s\n' "${id}" "${engine}" "${mode}" \
        "$(vpn::settings::get route)" "$(date +%s)" "$(IFS=' '; printf '%s' "${VPN_CORE_IDS[*]}")" \
        | vpn::store::__write "$(vpn::core::__f session)"
    # До 8 с ждём сообщения о старте, открытого порта или падения
    # wait up to 8 s for the start message, an open port or a crash
    local -i i
    local tail_text="" ready_re='sing-box started'
    [[ "${engine}" == "xray" ]] && ready_re='Xray [^ ]+ started'
    local -r listen_port="$(vpn::settings::get listen_port)"
    for (( i = 0; i < 40; i++ )); do
        read -r -t 0.2 <> <(:) || :
        tail_text="$(tail -n +"$(( log_from + 1 ))" "${log}" 2>/dev/null)"
        if [[ "${tail_text}" == *"FATAL"* || "${tail_text}" == *"Failed to start"* ]] \
            || { (( i > 5 )) && ! vpn::core::running; }; then
            printf 'ядро не запустилось / core failed to start:\n%s\n' "$(printf '%s\n' "${tail_text}" | tail -n 8)" >&2
            vpn::core::stop 2>/dev/null
            return "${LIB_ERROR_INVALID_INPUT}"
        fi
        if [[ "${tail_text}" =~ ${ready_re} ]] || { (( i > 2 )) && vpn::core::__port_open "${listen_port}"; }; then
            vpn::core::__select "${id}"
            return 0
        fi
    done
    vpn::core::running && { vpn::core::__select "${id}"; return 0; }
    printf 'ядро не ответило за 8 с / core did not start in 8 s\n' >&2
    return "${LIB_ERROR_TIMEOUT}"
}

# @private
# @description Point the running core at the profile (or "auto"): the selector of sing-box or the balancer override of Xray.
# @description Направить работающее ядро на профиль (или «auto»): селектор sing-box или override балансировщика Xray.
#   The sing-box cache file may remember an older choice; Xray forgets the override on restart.
#   Кэш sing-box может помнить прежний выбор; Xray забывает override при перезапуске.
# @param $1 id
vpn::core::__select() {
    local target="$1"
    [[ "$(vpn::settings::get auto_select)" == 1 && "$(vpn::core::session_get ids)" == *" "* ]] && target="auto"
    local -i i
    for (( i = 0; i < 10; i++ )); do
        vpn::core::__point "${target}" && return 0
        read -r -t 0.2 <> <(:) || :
    done
    return 0
}

# @private
# @description One switch request to the running core / Один запрос переключения к работающему ядру.
# @param $1 id or "auto"
vpn::core::__point() {
    local -r target="$1"
    if [[ "$(vpn::core::session_get engine)" == "xray" ]]; then
        if [[ "${target}" == "auto" ]]; then
            vpn::core::xray_api bo -b proxy -r >/dev/null 2>&1
        else
            vpn::core::xray_api bo -b proxy "$(vpn::xray::tag "${target}")" >/dev/null 2>&1
        fi
    else
        vpn::core::api PUT /proxies/proxy "{\"name\":\"${target}\"}" >/dev/null 2>&1
    fi
}

# @description Stop the core (TERM, then KILL after 3 s).
# @description Остановить ядро (TERM, затем KILL через 3 с).
# @return 0 stopped or was not running
vpn::core::stop() {
    local pid
    pid="$(vpn::core::pid)" || { rm -f "$(vpn::core::__f core.pid)" "$(vpn::core::__f session)"; return 0; }
    kill -TERM "${pid}" 2>/dev/null || vpn::core::__as_root kill -TERM "${pid}" 2>/dev/null
    local -i i
    for (( i = 0; i < 15; i++ )); do
        vpn::core::running || break
        read -r -t 0.2 <> <(:) || :
    done
    if vpn::core::running; then
        kill -KILL "${pid}" 2>/dev/null || vpn::core::__as_root kill -KILL "${pid}" 2>/dev/null
    fi
    rm -f "$(vpn::core::__f core.pid)" "$(vpn::core::__f session)" 2>/dev/null \
        || vpn::core::__as_root rm -f "$(vpn::core::__f core.pid)" "$(vpn::core::__f session)"
    return 0
}

# @description Status as "key=value" lines: running, pid, id, name, engine, mode, route, uptime, listen.
# @description Статус строками «ключ=значение»: running, pid, id, name, engine, mode, route, uptime, listen.
# @stdout lines / строки
vpn::core::status() {
    local pid="" running=0 started uptime=0 id
    if pid="$(vpn::core::pid)"; then running=1; fi
    id="$(vpn::core::session_get id)"
    is::empty "${id}" && id="$(vpn::settings::get active)"
    started="$(vpn::core::session_get started)"
    if (( running == 1 )) && is::number "${started}"; then
        uptime=$(( $(date +%s) - started ))
    fi
    printf 'running=%s\npid=%s\nid=%s\nname=%s\nengine=%s\nmode=%s\nroute=%s\nuptime=%s\nlisten=%s\n' \
        "${running}" "${pid}" "${id}" "$(vpn::store::field "${id}" name 2>/dev/null)" \
        "$(vpn::core::engine)" \
        "$(if (( running == 1 )); then vpn::core::session_get mode; else vpn::settings::get mode; fi)" \
        "$(vpn::settings::get route)" "${uptime}" \
        "127.0.0.1:$(vpn::settings::get listen_port)"
}

# @description Last lines of the core log / Последние строки журнала ядра.
# @param $1 [optional] count (default 50) / число строк
vpn::core::log_tail() {
    local -r n="${1:-50}"
    local -r log="$(vpn::core::log_file)"
    is::file "${log}" || return 0
    tail -n "${n}" "${log}"
}

# Core API / API ядра

# @description Call the Clash API of the running sing-box.
# @description Вызвать Clash API работающего sing-box.
# @param $1 method (GET/PUT/DELETE), $2 path, $3 [optional] JSON body
# @param $4 [optional] port (default: api_port setting), $5 [optional] secret
# @stdout response body / тело ответа
# @return 0 ok, LIB_ERROR_DEPENDENCY_MISSING no curl for non-GET, other — request failed
vpn::core::api() {
    local -r method="${1:?method required}" path="${2:?path required}" body="${3-}"
    local -r port="${4:-$(vpn::settings::get api_port)}"
    local secret="${5-}"
    [[ $# -lt 5 ]] && secret="$(vpn::settings::get api_secret)"
    if is::command curl; then
        local -a args=(-fsS -m 6 --noproxy "*" -X "${method}")
        is::not_empty "${secret}" && args+=(-H "Authorization: Bearer ${secret}")
        is::not_empty "${body}" && args+=(-H 'Content-Type: application/json' --data "${body}")
        curl "${args[@]}" "http://127.0.0.1:${port}${path}"
        return $?
    fi
    [[ "${method}" == GET ]] || return "${LIB_ERROR_DEPENDENCY_MISSING}"
    # Без curl: GET через /dev/tcp, HTTP/1.0 — сервер сам закрывает соединение
    # Without curl: GET over /dev/tcp, HTTP/1.0 — the server closes the connection
    local fd resp="" line
    exec {fd}<>"/dev/tcp/127.0.0.1/${port}" 2>/dev/null || return "${LIB_ERROR_INVALID_INPUT}"
    printf 'GET %s HTTP/1.0\r\nHost: 127.0.0.1\r\nAuthorization: Bearer %s\r\n\r\n' "${path}" "${secret}" >&"${fd}"
    while IFS= read -r -t 5 -u "${fd}" line || is::not_empty "${line}"; do
        resp+="${line}"$'\n'
    done
    exec {fd}>&-
    [[ "${resp}" == "HTTP/"*" 200 "* || "${resp}" == "HTTP/"*" 204 "* ]] || return "${LIB_ERROR_INVALID_INPUT}"
    resp="${resp#*$'\r\n\r\n'}"
    printf '%s' "${resp}"
}

# @description Call the API of the running Xray ("xray api <command> --server=…").
# @description Вызвать API работающего Xray («xray api <команда> --server=…»).
# @param $1 command (statsquery, bi, bo …), $@ its arguments / команда и её аргументы
# @stdout response / ответ
vpn::core::xray_api() {
    local -r api_cmd="${1:?command required}"
    shift
    local bin
    bin="$(vpn::core::bin xray)" || return "${LIB_ERROR_DEPENDENCY_MISSING}"
    "${bin}" api "${api_cmd}" --server="127.0.0.1:$(vpn::settings::get api_port)" -t 3 "$@"
}

# @description Traffic totals and open connections of the running core (Xray does not count connections: "-").
# @description Суммарный трафик и открытые соединения работающего ядра (Xray не считает соединения: «-»).
# @stdout "upload_bytes download_bytes connections"
# @return 0 ok, LIB_ERROR_INVALID_INPUT API unavailable
vpn::core::traffic() {
    local body up=0 down=0 conns=0
    if [[ "$(vpn::core::session_get engine)" == "xray" ]]; then
        body="$(vpn::core::xray_api statsquery -pattern 'outbound>>>' 2>/dev/null)" || return "${LIB_ERROR_INVALID_INPUT}"
        # {"stat":[{"name":"outbound>>>p:de>>>traffic>>>uplink","value":"123"}, …]}
        local re='"name":[[:space:]]*"outbound>>>([^>"]*)>>>traffic>>>(up|down)link"[[:space:]]*,?[[:space:]]*("value":[[:space:]]*"?([0-9]+)"?)?'
        local rest="${body//[$'\n\r']/ }"
        while [[ "${rest}" =~ ${re} ]]; do
            rest="${rest#*"${BASH_REMATCH[0]}"}"
            [[ "${BASH_REMATCH[1]}" == p:* ]] || continue
            if [[ "${BASH_REMATCH[2]}" == "up" ]]; then
                up=$(( up + ${BASH_REMATCH[4]:-0} ))
            else
                down=$(( down + ${BASH_REMATCH[4]:-0} ))
            fi
        done
        printf '%s %s -\n' "${up}" "${down}"
        return 0
    fi
    body="$(vpn::core::api GET /connections 2>/dev/null)" || return "${LIB_ERROR_INVALID_INPUT}"
    [[ "${body}" =~ \"uploadTotal\":[[:space:]]*([0-9]+) ]] && up="${BASH_REMATCH[1]}"
    [[ "${body}" =~ \"downloadTotal\":[[:space:]]*([0-9]+) ]] && down="${BASH_REMATCH[1]}"
    # каждое соединение несёт ровно одно поле "chains" / every connection has exactly one "chains" field
    local marks="${body//\"chains\"/$'\x01'}"
    marks="${marks//[!$'\x01']/}"
    conns="${#marks}"
    printf '%s %s %s\n' "${up}" "${down}" "${conns}"
}

# @description Server currently chosen by the core: an id, or "auto:<id>" when auto select chose it.
# @description Сервер, выбранный ядром: id или «auto:<id>», если его выбрал автовыбор.
# @stdout id
vpn::core::current() {
    local body now
    if [[ "$(vpn::core::session_get engine)" == "xray" ]]; then
        body="$(vpn::core::xray_api bi proxy 2>/dev/null)" || return "${LIB_ERROR_INVALID_INPUT}"
        # «- Selecting Override:» и «- Selects:», под каждым строки «N   p:<id>»
        # "- Selecting Override:" and "- Selects:", each followed by "N   p:<id>" lines
        local line section="" override="" pick=""
        while IFS= read -r line; do
            case "${line}" in
                *Override:*) section="override"; continue ;;
                *Selects:*) section="selects"; continue ;;
                *-\ *:*) section=""; continue ;;
            esac
            [[ "${line}" =~ ^[[:space:]]*[0-9]+[[:space:]]+p:([^[:space:]]+) ]] || continue
            if [[ "${section}" == "override" && -z "${override}" ]]; then
                override="${BASH_REMATCH[1]}"
            elif [[ "${section}" == "selects" && -z "${pick}" ]]; then
                pick="${BASH_REMATCH[1]}"
            fi
        done <<< "${body}"
        if is::not_empty "${override}"; then
            printf '%s\n' "${override}"
        elif is::not_empty "${pick}"; then
            printf 'auto:%s\n' "${pick}"
        else
            printf 'auto\n'
        fi
        return 0
    fi
    body="$(vpn::core::api GET /proxies/proxy 2>/dev/null)" || return "${LIB_ERROR_INVALID_INPUT}"
    [[ "${body}" =~ \"now\":[[:space:]]*\"([^\"]*)\" ]] || return "${LIB_ERROR_INVALID_INPUT}"
    now="${BASH_REMATCH[1]}"
    if [[ "${now}" == "auto" ]]; then
        body="$(vpn::core::api GET /proxies/auto 2>/dev/null)" || { printf 'auto\n'; return 0; }
        [[ "${body}" =~ \"now\":[[:space:]]*\"([^\"]*)\" ]] && now="auto:${BASH_REMATCH[1]}"
    fi
    printf '%s\n' "${now}"
}

# @description Switch the server: live when it is in the running config, otherwise restart (maybe on the other core).
# @description Сменить сервер: на лету, если он есть в работающем конфиге, иначе перезапуск (возможно, на другом ядре).
# @param $1 id (or "auto")
# @return 0 ok, other — as vpn::core::start
vpn::core::switch() {
    local -r id="${1:?id required}"
    # явный выбор сервера отключает автовыбор / an explicit server choice turns auto select off
    [[ "${id}" != "auto" ]] && vpn::settings::set auto_select 0 >/dev/null
    if vpn::core::running; then
        local -a live=()
        IFS=' ' read -ra live <<< "$(vpn::core::session_get ids)"
        if [[ "${id}" == "auto" && ${#live[@]} -gt 1 ]] || arr::contains live "${id}"; then
            vpn::core::__point "${id}" && {
                [[ "${id}" != "auto" ]] && vpn::settings::set active "${id}" >/dev/null
                return 0
            }
        fi
    fi
    [[ "${id}" == "auto" ]] && return "${LIB_ERROR_INVALID_ARGS}"
    vpn::core::start "${id}"
}

# Latency / Задержка

# @private
# @description Milliseconds since epoch (EPOCHREALTIME in bash 5, date otherwise).
# @description Миллисекунды от эпохи (EPOCHREALTIME в bash 5, иначе date).
vpn::core::__now_ms() {
    if is::not_empty "${EPOCHREALTIME:-}"; then
        local t="${EPOCHREALTIME/,/.}"
        printf '%s\n' "$(( ${t%.*} * 1000 + 10#${t#*.} / 1000 ))"
    else
        local n
        n="$(date +%s%N 2>/dev/null)"
        if [[ "${n}" =~ ^[0-9]+$ ]]; then printf '%s\n' "$(( n / 1000000 ))"; else printf '%s\n' "$(( $(date +%s) * 1000 ))"; fi
    fi
}

# @description TCP connect time to a profile's server (no core needed; not for UDP protocols).
# @description Время TCP-подключения к серверу профиля (ядро не нужно; не для UDP-протоколов).
# @param $1 id
# @stdout milliseconds / миллисекунды
# @return 0 ok, LIB_ERROR_TIMEOUT unreachable, LIB_ERROR_INVALID_ARGS UDP protocol
vpn::core::test_tcp() {
    local -A p=()
    vpn::store::load "${1-}" p || return $?
    case "${p[proto]}" in
        hysteria2|hysteria|tuic|wireguard) return "${LIB_ERROR_INVALID_ARGS}" ;;
        naive) [[ "${p[transport]:-}" == "quic" ]] && return "${LIB_ERROR_INVALID_ARGS}" ;;
    esac
    local -i t0 t1
    t0="$(vpn::core::__now_ms)"
    local -a wrap=()
    is::command timeout && wrap=(timeout 4)
    # shellcheck disable=SC2016 # $1/$2 раскрывает внутренний bash / expanded by the inner bash
    "${wrap[@]}" bash -c 'exec 3<>"/dev/tcp/$1/$2"' _ "${p[server]}" "${p[port]}" 2>/dev/null \
        || return "${LIB_ERROR_TIMEOUT}"
    t1="$(vpn::core::__now_ms)"
    printf '%d\n' "$(( t1 - t0 ))"
}

# @private
vpn::core::__latency_file() {
    vpn::core::__f latency.tsv
}

# @description Store a latency result (ms, or -1 failed, -2 rejected by core).
# @description Сохранить замер (мс, либо -1 ошибка, -2 отвергнут ядром).
# @param $1 id, $2 value
vpn::core::latency_save() {
    local -r id="${1:?id required}" value="${2:?value required}"
    vpn::store::init || return $?
    local -r file="$(vpn::core::__latency_file)"
    {
        is::file "${file}" && awk -F'\t' -v id="${id}" '$1 != id' "${file}"
        printf '%s\t%s\t%s\n' "${id}" "${value}" "$(date +%s)"
    } | vpn::store::__write "${file}"
}

# @description All stored latency results / Все сохранённые замеры.
# @stdout id<TAB>ms<TAB>epoch
vpn::core::latency_list() {
    local -r file="$(vpn::core::__latency_file)"
    is::file "${file}" && cat "${file}"
    return 0
}

# @private
# @description Report and store one result / Вывести и сохранить один результат.
vpn::core::__result() {
    printf '%s\t%s\n' "$1" "$2"
    vpn::core::latency_save "$1" "$2"
}

# @private
# @description Wait for a batch of background jobs / Дождаться пачки фоновых задач.
vpn::core::__wait_all() {
    local b
    for b in "$@"; do wait "${b}" 2>/dev/null || :; done
    return 0
}

# @private
# @description Real latency of ids through a temporary sing-box (Clash API delay).
# @description Реальная задержка id через временный sing-box (delay из Clash API).
vpn::core::__test_singbox() {
    local -r tmp="$1"
    shift
    local -ri port=$(( 20000 + RANDOM % 30000 ))
    local id
    VPN_CORE_ENGINE="sing-box"
    if ! vpn::core::build_config test "${tmp}/sb.json" "${port}" "$@" 2>/dev/null; then
        for id in "$@"; do vpn::core::__result "${id}" -2; done
        return 0
    fi
    for id in "$@"; do
        arr::contains VPN_CORE_IDS "${id}" || vpn::core::__result "${id}" -2
    done
    local bin
    bin="$(vpn::core::bin sing-box)"
    "${bin}" run -c "${tmp}/sb.json" -D "${tmp}" > "${tmp}/sb.log" 2>&1 &
    local -r pid=$!
    local -i i
    for (( i = 0; i < 25; i++ )); do
        vpn::core::api GET /version "" "${port}" "" >/dev/null 2>&1 && break
        read -r -t 0.2 <> <(:) || :
    done
    local url
    url="$(uri::encode "$(vpn::settings::get test_url)")"
    local -a batch=()
    for id in "${VPN_CORE_IDS[@]}"; do
        ( vpn::core::api GET "/proxies/${id}/delay?timeout=5000&url=${url}" "" "${port}" "" \
            > "${tmp}/d.${id}" 2>/dev/null ) &
        batch+=("$!")
        # не больше 16 одновременных замеров / at most 16 concurrent probes
        (( ${#batch[@]} >= 16 )) && { vpn::core::__wait_all "${batch[@]}"; batch=(); }
    done
    vpn::core::__wait_all "${batch[@]}"
    kill "${pid}" 2>/dev/null || :
    wait "${pid}" 2>/dev/null || :
    local body ms
    for id in "${VPN_CORE_IDS[@]}"; do
        body="$(cat "${tmp}/d.${id}" 2>/dev/null)"
        ms=-1
        [[ "${body}" =~ \"delay\":[[:space:]]*([0-9]+) ]] && ms="${BASH_REMATCH[1]}"
        (( ms == 0 )) && ms=-1
        vpn::core::__result "${id}" "${ms}"
    done
}

# @private
# @description Real latency of ids through a temporary Xray: curl through a SOCKS inbound per profile.
# @description Реальная задержка id через временный Xray: curl через SOCKS-вход каждого профиля.
#   Like the Clash API delay, the first request of a fresh connection is timed.
#   Как и delay Clash API, замеряется первый запрос нового соединения.
vpn::core::__test_xray() {
    local -r tmp="$1"
    shift
    local -ri base=$(( 20000 + RANDOM % 30000 ))
    local id
    VPN_CORE_ENGINE="xray"
    if ! vpn::core::build_config test "${tmp}/xr.json" "${base}" "$@" 2>/dev/null; then
        for id in "$@"; do vpn::core::__result "${id}" -2; done
        return 0
    fi
    for id in "$@"; do
        arr::contains VPN_CORE_IDS "${id}" || vpn::core::__result "${id}" -2
    done
    local -a run=()
    mapfile -t run < <(vpn::core::__run_cmd xray)
    # __run_cmd указывает на основной конфиг — подменяем на тестовый / __run_cmd names the main config — use the test one
    run[${#run[@]}-1]="${tmp}/xr.json"
    "${run[@]}" > "${tmp}/xr.log" 2>&1 &
    local -r pid=$!
    local -i i
    for (( i = 0; i < 25; i++ )); do
        vpn::core::__port_open "${base}" && break
        read -r -t 0.2 <> <(:) || :
    done
    local -r url="$(vpn::settings::get test_url)"
    local -a batch=()
    local -i port="${base}"
    for id in "${VPN_CORE_IDS[@]}"; do
        ( curl -s -o /dev/null -m 5 --noproxy "" -x "socks5h://127.0.0.1:${port}" \
            -w '%{http_code} %{time_total}' "${url}" > "${tmp}/d.${id}" 2>/dev/null ) &
        batch+=("$!")
        port=$(( port + 1 ))
        (( ${#batch[@]} >= 16 )) && { vpn::core::__wait_all "${batch[@]}"; batch=(); }
    done
    vpn::core::__wait_all "${batch[@]}"
    kill "${pid}" 2>/dev/null || :
    wait "${pid}" 2>/dev/null || :
    local body ms
    for id in "${VPN_CORE_IDS[@]}"; do
        body="$(cat "${tmp}/d.${id}" 2>/dev/null)"
        ms=-1
        if [[ "${body}" =~ ^([0-9]{3})\ ([0-9]+)[.,]([0-9]{3}) ]] && [[ "${BASH_REMATCH[1]}" != 000 ]]; then
            ms=$(( 10#${BASH_REMATCH[2]} * 1000 + 10#${BASH_REMATCH[3]} ))
            (( ms == 0 )) && ms=1
        fi
        vpn::core::__result "${id}" "${ms}"
    done
}

# @description Real latency through the cores: temporary instances measure every profile in parallel.
# @description Реальная задержка через ядра: временные экземпляры замеряют все профили параллельно.
#   sing-box measures what it can dial; profiles only Xray can dial go to Xray (and
#   everything goes to Xray when sing-box is not installed). Works for every protocol,
#   UDP ones too, and does not touch the running tunnel.
#   sing-box замеряет всё, что умеет; профили только для Xray идут в Xray (а без
#   sing-box — всё в Xray). Работает для всех протоколов, и UDP тоже, и не трогает туннель.
# @param $@ ids (default: all profiles) / id (по умолчанию все)
# @stdout id<TAB>ms (-1 failed, -2 rejected by the core or no core for it) / id<TAB>мс
# @return 0 ok, LIB_ERROR_DEPENDENCY_MISSING no core or curl
vpn::core::test_real() {
    is::command curl || { printf 'нужен curl / curl required\n' >&2; return "${LIB_ERROR_DEPENDENCY_MISSING}"; }
    local have_sb=0 have_xr=0
    vpn::core::require sing-box 2>/dev/null && have_sb=1
    vpn::core::require xray 2>/dev/null && have_xr=1
    if (( have_sb == 0 && have_xr == 0 )); then
        vpn::core::require sing-box
        return "${LIB_ERROR_DEPENDENCY_MISSING}"
    fi
    local -a ids=("$@")
    (( ${#ids[@]} > 0 )) || mapfile -t ids < <(vpn::store::ids)
    (( ${#ids[@]} > 0 )) || return 0
    vpn::store::init || return $?
    VPN_XRAY_GEO=0
    local -a sb=() xr=()
    local id
    for id in "${ids[@]}"; do
        if (( have_sb == 1 )) && vpn::core::engine_can sing-box "${id}"; then
            sb+=("${id}")
        elif (( have_xr == 1 )) && vpn::core::engine_can xray "${id}"; then
            xr+=("${id}")
        else
            vpn::core::__result "${id}" -2
        fi
    done
    local tmp
    tmp="$(mktemp -d)" || return "${LIB_ERROR_FILE_OPERATION}"
    (( ${#sb[@]} > 0 )) && vpn::core::__test_singbox "${tmp}" "${sb[@]}"
    (( ${#xr[@]} > 0 )) && vpn::core::__test_xray "${tmp}" "${xr[@]}"
    rm -rf "${tmp}"
    return 0
}

# @description Public exit IP (and country/org when available) through the local proxy or directly.
# @description Внешний IP (и страна/провайдер, если есть) через локальный прокси или напрямую.
# @param $1 [optional] "direct" to bypass the proxy / «direct» — мимо прокси
# @stdout "ip country city org" (unknown fields are "-") / неизвестные поля — «-»
vpn::core::exit_ip() {
    is::command curl || return "${LIB_ERROR_DEPENDENCY_MISSING}"
    local -a proxy=()
    if [[ "${1-}" != "direct" ]] && vpn::core::running; then
        proxy=(-x "socks5h://127.0.0.1:$(vpn::settings::get listen_port)")
    fi
    local body ip="-" country="-" city="-" org="-"
    if body="$(curl -fsS -m 8 "${proxy[@]}" https://ipinfo.io/json 2>/dev/null)"; then
        [[ "${body}" =~ \"ip\":[[:space:]]*\"([^\"]+)\" ]] && ip="${BASH_REMATCH[1]}"
        [[ "${body}" =~ \"country\":[[:space:]]*\"([^\"]+)\" ]] && country="${BASH_REMATCH[1]}"
        [[ "${body}" =~ \"city\":[[:space:]]*\"([^\"]+)\" ]] && city="${BASH_REMATCH[1]// /_}"
        [[ "${body}" =~ \"org\":[[:space:]]*\"([^\"]+)\" ]] && org="${BASH_REMATCH[1]// /_}"
    elif body="$(curl -fsS -m 8 "${proxy[@]}" https://api.ipify.org 2>/dev/null)"; then
        ip="${body//[^0-9a-fA-F.:]/}"
    else
        return "${LIB_ERROR_TIMEOUT}"
    fi
    printf '%s %s %s %s\n' "${ip}" "${country}" "${city}" "${org}"
}

# systemd / systemd

# @description systemd unit that runs the generated config at boot (with the core of the last session).
# @description Юнит systemd, запускающий сгенерированный конфиг при загрузке (ядром последней сессии).
# @param $1 [optional] engine (default: vpn::core::engine) / ядро
# @stdout unit text / текст юнита
vpn::core::service_unit() {
    local engine="${1-}"
    is::empty "${engine}" && engine="$(vpn::core::engine)"
    local -a run=()
    mapfile -t run < <(vpn::core::__run_cmd "${engine}")
    (( ${#run[@]} > 0 )) || return "${LIB_ERROR_DEPENDENCY_MISSING}"
    local env_line="" exec_line
    if [[ "${run[0]}" == "env" ]]; then
        env_line="Environment=${run[1]}"$'\n'
        run=("${run[@]:2}")
    fi
    exec_line="$(IFS=' '; printf '%s' "${run[*]}")"
    cat <<UNIT
# Generated by BS VPN — bs-vpn.service
[Unit]
Description=BS VPN client (${engine})
After=network-online.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
${env_line}ExecStart=${exec_line}
Restart=on-failure
RestartSec=5
LimitNOFILE=infinity
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
UNIT
}

# @description Install and enable the systemd unit (root; BS_VPN_DRY_RUN=1 only prints).
# @description Установить и включить юнит systemd (root; BS_VPN_DRY_RUN=1 только печатает).
# @return 0 ok, LIB_ERROR_FILE_NOT_FOUND no generated config, LIB_ERROR_PERMISSION_DENIED no root
vpn::core::service_install() {
    is::file "$(vpn::core::config_file)" || {
        printf 'сначала подключитесь один раз, чтобы собрать конфиг / connect once first to build the config\n' >&2
        return "${LIB_ERROR_FILE_NOT_FOUND}"
    }
    local -r unit="${BS_VPN_UNIT_DIR:-/etc/systemd/system}/bs-vpn.service"
    local -r engine="$(vpn::core::engine)"
    if [[ "${BS_VPN_DRY_RUN:-0}" == 1 ]]; then
        printf 'dry-run: %s\n' "${unit}" >&2
        vpn::core::service_unit "${engine}"
        return 0
    fi
    vpn::core::root_ready || {
        printf 'нужен root / root required (sudo)\n' >&2
        return "${LIB_ERROR_PERMISSION_DENIED}"
    }
    vpn::core::running && vpn::core::stop
    vpn::core::service_unit "${engine}" | vpn::core::__as_root tee "${unit}" >/dev/null || return "${LIB_ERROR_FILE_OPERATION}"
    vpn::core::__as_root systemctl daemon-reload
    vpn::core::__as_root systemctl enable --now bs-vpn.service
}

# @description Disable and remove the systemd unit / Выключить и удалить юнит systemd.
vpn::core::service_remove() {
    local -r unit="${BS_VPN_UNIT_DIR:-/etc/systemd/system}/bs-vpn.service"
    if [[ "${BS_VPN_DRY_RUN:-0}" == 1 ]]; then
        printf 'dry-run: systemctl disable --now bs-vpn; rm %s\n' "${unit}" >&2
        return 0
    fi
    vpn::core::root_ready || return "${LIB_ERROR_PERMISSION_DENIED}"
    vpn::core::__as_root systemctl disable --now bs-vpn.service 2>/dev/null
    vpn::core::__as_root rm -f "${unit}"
    vpn::core::__as_root systemctl daemon-reload
}
