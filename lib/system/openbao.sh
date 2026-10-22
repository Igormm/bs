#!/usr/bin/env bs
# shellcheck shell=bash
# @shell bash4 — нужны конструкции bash: double-bracket [[ ]], array, local/declare flags, process substitution / needs bash constructs: double-bracket [[ ]], array, local/declare flags, process substitution
# lib/system/openbao.sh — OpenBao server: release install, system user, file
# storage, TLS, HCL config, systemd unit, operator init and unseal
# lib/system/openbao.sh — сервер OpenBao: установка релиза, системный
# пользователь, file storage, TLS, HCL-конфиг, systemd-юнит, init и unseal
#
# Usage / Использование:
#   load "lib/system/openbao"
#   openbao_server::install
#   openbao_server::apply prod
#   openbao_server::apply dev
#
# All paths are overridable with BS_OPENBAO_* hooks for tests.
# Все пути переопределяются хуками BS_OPENBAO_* для тестов.
#
# @depends core/const, core/logger, core/utils, lib/io/files,
#   lib/system/systemd, lib/system/user, lib/integration/http,
#   lib/integration/openbao
# @optdeps curl, wget, sha256sum, tar, gzip, openssl, systemctl, useradd

# Source Guard / Защита от повторной загрузки
bs::guard "LIB_SYSTEM_OPENBAO" || return 0

# Dependencies / Зависимости
bs::source_relative "../../core/const.sh" "../../core/logger.sh" \
    "../../core/utils.sh" "../io/files.sh" "systemd.sh" "user.sh" \
    "../integration/http.sh" "../integration/openbao.sh"

# @global BS_OPENBAO_VERSION — Hook: release version or latest (category: hook)
# @global BS_OPENBAO_VERSION — Хук: версия релиза или latest (категория: hook)
declare -g BS_OPENBAO_VERSION="${BS_OPENBAO_VERSION:-latest}"
# @global BS_OPENBAO_BIN — Hook: bao binary path (category: hook)
# @global BS_OPENBAO_BIN — Хук: путь к бинарнику bao (категория: hook)
declare -g BS_OPENBAO_BIN="${BS_OPENBAO_BIN:-/usr/local/bin/bao}"
# @global BS_OPENBAO_CONFIG — Hook: server config path (category: hook)
# @global BS_OPENBAO_CONFIG — Хук: путь к конфигу сервера (категория: hook)
declare -g BS_OPENBAO_CONFIG="${BS_OPENBAO_CONFIG:-/etc/openbao/openbao.hcl}"
# @global BS_OPENBAO_CONFIG_DIR — Hook: config directory (category: hook)
# @global BS_OPENBAO_CONFIG_DIR — Хук: каталог конфига (категория: hook)
declare -g BS_OPENBAO_CONFIG_DIR="${BS_OPENBAO_CONFIG_DIR:-/etc/openbao}"
# @global BS_OPENBAO_DATA_DIR — Hook: data/storage directory (category: hook)
# @global BS_OPENBAO_DATA_DIR — Хук: каталог данных/storage (категория: hook)
declare -g BS_OPENBAO_DATA_DIR="${BS_OPENBAO_DATA_DIR:-/var/lib/openbao}"
# @global BS_OPENBAO_TLS_DIR — Hook: TLS directory (category: hook)
# @global BS_OPENBAO_TLS_DIR — Хук: каталог TLS (категория: hook)
declare -g BS_OPENBAO_TLS_DIR="${BS_OPENBAO_TLS_DIR:-/etc/openbao/tls}"
# @global BS_OPENBAO_TLS_MODE — Hook: selfsigned|files|off (category: hook)
# @global BS_OPENBAO_TLS_MODE — Хук: selfsigned|files|off (категория: hook)
declare -g BS_OPENBAO_TLS_MODE="${BS_OPENBAO_TLS_MODE:-selfsigned}"
# @global BS_OPENBAO_TLS_CERT — Hook: server certificate path (category: hook)
# @global BS_OPENBAO_TLS_CERT — Хук: путь к серверному сертификату (категория: hook)
declare -g BS_OPENBAO_TLS_CERT="${BS_OPENBAO_TLS_CERT:-${BS_OPENBAO_TLS_DIR}/server.crt}"
# @global BS_OPENBAO_TLS_KEY — Hook: server key path (category: hook)
# @global BS_OPENBAO_TLS_KEY — Хук: путь к серверному ключу (категория: hook)
declare -g BS_OPENBAO_TLS_KEY="${BS_OPENBAO_TLS_KEY:-${BS_OPENBAO_TLS_DIR}/server.key}"
# @global BS_OPENBAO_TLS_CA — Hook: CA bundle for a client of this server (category: hook)
# @global BS_OPENBAO_TLS_CA — Хук: CA-сертификат для клиента этого сервера (категория: hook)
declare -g BS_OPENBAO_TLS_CA="${BS_OPENBAO_TLS_CA:-${BS_OPENBAO_TLS_DIR}/ca.crt}"
# @global BS_OPENBAO_LISTEN — Hook: listener address host:port (category: hook)
# @global BS_OPENBAO_LISTEN — Хук: адрес listener host:port (категория: hook)
declare -g BS_OPENBAO_LISTEN="${BS_OPENBAO_LISTEN:-127.0.0.1:8200}"
# @global BS_OPENBAO_INIT_FILE — Hook: operator init JSON path (category: hook)
# @global BS_OPENBAO_INIT_FILE — Хук: путь к JSON operator init (категория: hook)
declare -g BS_OPENBAO_INIT_FILE="${BS_OPENBAO_INIT_FILE:-/root/openbao-init.json}"
# @global BS_OPENBAO_SERVICE — Hook: systemd unit name (category: hook)
# @global BS_OPENBAO_SERVICE — Хук: имя systemd-юнита (категория: hook)
declare -g BS_OPENBAO_SERVICE="${BS_OPENBAO_SERVICE:-openbao}"
# @global BS_OPENBAO_USER — Hook: service user (category: hook)
# @global BS_OPENBAO_USER — Хук: пользователь сервиса (категория: hook)
declare -g BS_OPENBAO_USER="${BS_OPENBAO_USER:-openbao}"
# @global BS_OPENBAO_GROUP — Hook: service group (category: hook)
# @global BS_OPENBAO_GROUP — Хук: группа сервиса (категория: hook)
declare -g BS_OPENBAO_GROUP="${BS_OPENBAO_GROUP:-openbao}"
# @global BS_OPENBAO_RELEASE_BASE — Hook: release download base (category: hook)
# @global BS_OPENBAO_RELEASE_BASE — Хук: база скачивания релизов (категория: hook)
declare -g BS_OPENBAO_RELEASE_BASE="${BS_OPENBAO_RELEASE_BASE:-https://github.com/openbao/openbao/releases}"
# @global BS_OPENBAO_API_BASE — Hook: latest release API (category: hook)
# @global BS_OPENBAO_API_BASE — Хук: API последнего релиза (категория: hook)
declare -g BS_OPENBAO_API_BASE="${BS_OPENBAO_API_BASE:-https://api.github.com/repos/openbao/openbao/releases/latest}"
# @global BS_OPENBAO_LATEST_VERSION — Hook: pre-resolved latest version, for tests (category: hook)
# @global BS_OPENBAO_LATEST_VERSION — Хук: заранее определённая latest-версия, для тестов (категория: hook)
declare -g BS_OPENBAO_LATEST_VERSION="${BS_OPENBAO_LATEST_VERSION:-}"
# @global BS_OPENBAO_INIT_SHARES — Hook: number of unseal shares (category: hook)
# @global BS_OPENBAO_INIT_SHARES — Хук: число unseal-долей (категория: hook)
declare -g BS_OPENBAO_INIT_SHARES="${BS_OPENBAO_INIT_SHARES:-5}"
# @global BS_OPENBAO_INIT_THRESHOLD — Hook: unseal threshold (category: hook)
# @global BS_OPENBAO_INIT_THRESHOLD — Хук: порог unseal (категория: hook)
declare -g BS_OPENBAO_INIT_THRESHOLD="${BS_OPENBAO_INIT_THRESHOLD:-3}"
# @global BS_OPENBAO_DEV_TOKEN — Hook: dev root token (category: hook)
# @global BS_OPENBAO_DEV_TOKEN — Хук: root-токен dev (категория: hook)
declare -g BS_OPENBAO_DEV_TOKEN="${BS_OPENBAO_DEV_TOKEN:-}"
# @global BS_OPENBAO_DEV_LISTEN — Hook: dev listener address (category: hook)
# @global BS_OPENBAO_DEV_LISTEN — Хук: адрес listener dev (категория: hook)
declare -g BS_OPENBAO_DEV_LISTEN="${BS_OPENBAO_DEV_LISTEN:-127.0.0.1:8200}"
# @global BS_OPENBAO_DRY_RUN — Hook: 1 = do not change the system (category: hook)
# @global BS_OPENBAO_DRY_RUN — Хук: 1 = не менять систему (категория: hook)
declare -g BS_OPENBAO_DRY_RUN="${BS_OPENBAO_DRY_RUN:-0}"
# @global BS_OPENBAO_TIMEOUT — Hook: readiness timeout in seconds (category: hook)
# @global BS_OPENBAO_TIMEOUT — Хук: таймаут готовности в секундах (категория: hook)
declare -g BS_OPENBAO_TIMEOUT="${BS_OPENBAO_TIMEOUT:-30}"

# @private Dry-run predicate / Признак dry-run
openbao_server::__dry() {
    [[ "${BS_OPENBAO_DRY_RUN}" == "1" || "${FRAMEWORK_DRY_RUN:-false}" == "true" ]]
}

# @private Reject newlines/quotes in a path used inside HCL/systemd /
# Отклонить переводы строк и кавычки в пути для HCL/systemd
# @param $1 Path / Путь
# @param $2 Name / Имя
openbao_server::__safe_path() {
    local -r path="${1-}" name="${2:-path}"
    if [[ -z "${path}" || "${path}" == *$'\n'* || "${path}" == *'"'* || "${path}" == *$'\r'* ]]; then
        log::error "OpenBao: недопустимый ${name} / invalid ${name}: ${path}"
        return "${LIB_ERROR_INVALID_INPUT}"
    fi
    return 0
}

# @private Ensure a directory and optionally chown it / Создать каталог и chown
# @param $1 Path / Путь
# @param $2 Mode / Права
openbao_server::__dir() {
    local -r path="${1:?path required}" mode="${2:-0750}"
    openbao_server::__safe_path "${path}" "directory" || return $?
    if openbao_server::__dry; then
        log::warn "[DRY-RUN] mkdir -p ${path} && chmod ${mode} ${path}"
        return 0
    fi
    io::files::ensure_dir "${path}" "${mode}" || return "${LIB_ERROR_FILE_OPERATION}"
    if (( EUID == 0 )) && is::command chown; then
        chown "${BS_OPENBAO_USER}:${BS_OPENBAO_GROUP}" "${path}" || return "${LIB_ERROR_FILE_OPERATION}"
    fi
    return 0
}

# @private Atomic file write with mode and optional root ownership /
# Атомарная запись файла с правами и опциональным владельцем root
# @param $1 Path / Путь
# @param $2 Mode / Права
# @param $3 Content / Содержимое
openbao_server::__write_file() {
    local -r path="${1:?path required}" mode="${2:?mode required}" content="${3-}"
    openbao_server::__safe_path "${path}" "file" || return $?
    if openbao_server::__dry; then
        log::warn "[DRY-RUN] write ${path} (${mode})"
        return 0
    fi
    local -r dir="$(dirname -- "${path}")"
    is::dir "${dir}" || io::files::ensure_dir "${dir}" "0755" || return "${LIB_ERROR_FILE_OPERATION}"
    local tmp="${path}.tmp.$$"
    if ! ( umask 077; printf '%s' "${content}" > "${tmp}" ); then
        rm -f -- "${tmp}"
        log::error "OpenBao: не удалось записать / cannot write: ${tmp}"
        return "${LIB_ERROR_FILE_OPERATION}"
    fi
    if ! chmod "${mode}" "${tmp}"; then
        rm -f -- "${tmp}"
        return "${LIB_ERROR_FILE_OPERATION}"
    fi
    if (( EUID == 0 )) && is::command chown; then
        chown root:"${BS_OPENBAO_GROUP}" "${tmp}" 2>/dev/null || true
    fi
    if ! mv -f -- "${tmp}" "${path}"; then
        rm -f -- "${tmp}"
        return "${LIB_ERROR_FILE_OPERATION}"
    fi
    return 0
}

# @private Backup an existing file / Сделать backup существующего файла
# @param $1 Path / Путь
openbao_server::__backup() {
    local -r path="${1:?path required}"
    is::file "${path}" || return 0
    openbao_server::__dry && { log::warn "[DRY-RUN] backup ${path}"; return 0; }
    local -r backup="${path}.bak.$(date +%Y%m%d%H%M%S)"
    io::files::copy_file "${path}" "${backup}" false || return "${LIB_ERROR_FILE_OPERATION}"
    return 0
}

# @private Require one of curl/wget / Требовать curl или wget
openbao_server::__need_http() {
    if is::command curl || is::command wget; then
        return 0
    fi
    log::error "OpenBao: нужен curl или wget / curl or wget is required"
    return "${LIB_ERROR_DEPENDENCY_MISSING}"
}

# @description Initialize and validate hooks / Инициализировать и проверить хуки
openbao_server::init() {
    if [[ "$(uname -s 2>/dev/null)" != "Linux" ]]; then
        log::error "OpenBao: поддерживается только Linux / only Linux is supported"
        return "${LIB_ERROR_UNSUPPORTED_OS}"
    fi
    openbao_server::__safe_path "${BS_OPENBAO_LISTEN}" "listen address" || return $?
    if [[ ! "${BS_OPENBAO_LISTEN}" =~ ^[^:]+:[0-9]+$ ]]; then
        log::error "OpenBao: неверный listen-адрес / invalid listen address: ${BS_OPENBAO_LISTEN}"
        return "${LIB_ERROR_INVALID_INPUT}"
    fi
    if (( 10#${BS_OPENBAO_LISTEN##*:} < 1 || 10#${BS_OPENBAO_LISTEN##*:} > 65534 )); then
        log::error "OpenBao: порт listener вне диапазона / listener port out of range: ${BS_OPENBAO_LISTEN}"
        return "${LIB_ERROR_INVALID_INPUT}"
    fi
    if [[ "${BS_OPENBAO_TLS_MODE}" != selfsigned && "${BS_OPENBAO_TLS_MODE}" != files && "${BS_OPENBAO_TLS_MODE}" != off ]]; then
        log::error "OpenBao: TLS mode должен быть selfsigned|files|off / TLS mode must be selfsigned|files|off"
        return "${LIB_ERROR_INVALID_INPUT}"
    fi
    if [[ ! "${BS_OPENBAO_INIT_SHARES}" =~ ^[0-9]+$ || ! "${BS_OPENBAO_INIT_THRESHOLD}" =~ ^[0-9]+$ ]] \
        || (( BS_OPENBAO_INIT_THRESHOLD > BS_OPENBAO_INIT_SHARES || BS_OPENBAO_INIT_THRESHOLD < 1 )); then
        log::error "OpenBao: неверные init shares/threshold / invalid init shares/threshold"
        return "${LIB_ERROR_INVALID_INPUT}"
    fi
    openbao_server::__safe_path "${BS_OPENBAO_BIN}" "binary path" || return $?
    openbao_server::__safe_path "${BS_OPENBAO_CONFIG}" "config path" || return $?
    openbao_server::__safe_path "${BS_OPENBAO_CONFIG_DIR}" "config directory" || return $?
    openbao_server::__safe_path "${BS_OPENBAO_DATA_DIR}" "data path" || return $?
    openbao_server::__safe_path "${BS_OPENBAO_TLS_DIR}" "TLS path" || return $?
    openbao_server::__safe_path "${BS_OPENBAO_TLS_CERT}" "TLS certificate" || return $?
    openbao_server::__safe_path "${BS_OPENBAO_TLS_KEY}" "TLS key" || return $?
    openbao_server::__safe_path "${BS_OPENBAO_TLS_CA}" "TLS CA" || return $?
    openbao_server::__safe_path "${BS_OPENBAO_INIT_FILE}" "init path" || return $?
    if [[ ! "${BS_OPENBAO_USER}" =~ ^[a-z_][a-z0-9_-]*$ || ! "${BS_OPENBAO_GROUP}" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        log::error "OpenBao: неверный пользователь/группа / invalid user or group"
        return "${LIB_ERROR_INVALID_INPUT}"
    fi
    if [[ ! "${BS_OPENBAO_SERVICE}" =~ ^[A-Za-z0-9_.@-]+$ ]]; then
        log::error "OpenBao: неверное имя сервиса / invalid service name: ${BS_OPENBAO_SERVICE}"
        return "${LIB_ERROR_INVALID_INPUT}"
    fi
    return 0
}

# @description Linux asset architecture / Архитектура ассета Linux
# @stdout amd64|arm64 / amd64|arm64
openbao_server::arch() {
    case "$(uname -m 2>/dev/null)" in
        x86_64|amd64) printf 'amd64' ;;
        aarch64|arm64) printf 'arm64' ;;
        *)
            log::error "OpenBao: неподдерживаемая архитектура / unsupported architecture: $(uname -m 2>/dev/null)"
            return "${LIB_ERROR_PLATFORM_UNSUPPORTED}"
            ;;
    esac
}

# @description Installed OpenBao version / Версия установленного OpenBao
# @stdout version without v / версия без v
openbao_server::version() {
    is::file "${BS_OPENBAO_BIN}" && is::executable "${BS_OPENBAO_BIN}" || return 1
    local out
    out="$("${BS_OPENBAO_BIN}" version 2>/dev/null)" || return 1
    local version
    version="$(printf '%s\n' "${out}" | sed -n 's/.*[vV]\([0-9][0-9.]*\).*/\1/p' | head -1)"
    [[ -n "${version}" ]] || return 1
    printf '%s' "${version}"
}

# @description Detect the binary: path and version / Найти бинарник: путь и версия
# @stdout path<TAB>version / path<TAB>version
openbao_server::detect() {
    local version
    version="$(openbao_server::version)" || return 1
    printf '%s\t%s\n' "${BS_OPENBAO_BIN}" "${version}"
}

# @private Resolve latest or explicit version / Определить latest или явную версию
# @param $1 Requested version / Запрошенная версия
# @stdout version without v / версия без v
openbao_server::__resolve_version() {
    local version="${1:-${BS_OPENBAO_VERSION}}"
    if [[ "${version}" == "latest" ]]; then
        if [[ -n "${BS_OPENBAO_LATEST_VERSION}" ]]; then
            version="${BS_OPENBAO_LATEST_VERSION}"
        else
            openbao_server::__need_http || return $?
            local json
            json="$(http::get "${BS_OPENBAO_API_BASE}")" || {
                log::error "OpenBao: не удалось узнать последнюю версию / cannot resolve latest version"
                return "${INTEGRATION_ERROR_HTTP}"
            }
            version="$(printf '%s\n' "${json}" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v\{0,1\}\([^"]*\)".*/\1/p' | head -1)"
        fi
    fi
    version="${version#v}"
    if [[ ! "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9]+)*$ ]]; then
        log::error "OpenBao: неверная версия / invalid version: ${version}"
        return "${LIB_ERROR_INVALID_INPUT}"
    fi
    printf '%s' "${version}"
}

# @private Release asset URL / URL ассета релиза
# @param $1 Version / Версия
openbao_server::asset_url() {
    local -r version="${1:?version required}"
    local arch
    arch="$(openbao_server::arch)" || return $?
    printf '%s/download/v%s/openbao_%s_linux_%s.tar.gz' \
        "${BS_OPENBAO_RELEASE_BASE%/}" "${version}" "${version}" "${arch}"
}

# @private Checksums URL / URL контрольных сумм
# @param $1 Version / Версия
openbao_server::checksums_url() {
    local -r version="${1:?version required}"
    printf '%s/download/v%s/checksums.txt' "${BS_OPENBAO_RELEASE_BASE%/}" "${version}"
}

# @description Install the OpenBao binary / Установить бинарник OpenBao
# @param [$1] Version or latest / Версия или latest
openbao_server::install() {
    openbao_server::init || return $?
    local wanted="${1:-${BS_OPENBAO_VERSION}}"
    local current=""
    current="$(openbao_server::version)" || current=""
    if [[ -x "${BS_OPENBAO_BIN}" ]] && { [[ "${wanted}" == "latest" ]] || [[ "${current}" == "${wanted#v}" ]]; }; then
        log::info "OpenBao уже установлен / already installed: ${BS_OPENBAO_BIN} (${current:-unknown})"
        return 0
    fi

    openbao_server::__need_http || return $?
    local tool
    for tool in sha256sum tar gzip; do
        is::command "${tool}" || {
            log::error "OpenBao: нужен ${tool} / ${tool} is required"
            return "${LIB_ERROR_DEPENDENCY_MISSING}"
        }
    done

    local version
    version="$(openbao_server::__resolve_version "${wanted}")" || return $?
    local url checksums name
    url="$(openbao_server::asset_url "${version}")" || return $?
    checksums="$(openbao_server::checksums_url "${version}")" || return $?
    name="$(basename -- "${url}")"

    if openbao_server::__dry; then
        log::warn "[DRY-RUN] download ${url}"
        log::warn "[DRY-RUN] verify ${checksums} and install ${BS_OPENBAO_BIN}"
        return 0
    fi

    local tmpdir
    io::files::tempdir tmpdir --cleanup || return "${LIB_ERROR_FILE_OPERATION}"
    local archive="${tmpdir}/${name}" sums="${tmpdir}/checksums.txt"
    http::download "${url}" "${archive}" --timeout 120 || return "${INTEGRATION_ERROR_HTTP}"
    http::download "${checksums}" "${sums}" --timeout 30 || return "${INTEGRATION_ERROR_HTTP}"

    local expected actual
    expected="$(awk -v n="${name}" '$2==n {print $1; exit}' "${sums}")"
    if [[ -z "${expected}" ]]; then
        log::error "OpenBao: ${name} нет в checksums.txt / not listed in checksums.txt"
        return "${LIB_ERROR_INVALID_INPUT}"
    fi
    actual="$(sha256sum "${archive}" | awk '{print $1}')"
    if [[ "${actual}" != "${expected}" ]]; then
        log::error "OpenBao: контрольная сумма не совпала / checksum mismatch for ${name}"
        return "${LIB_ERROR_INVALID_INPUT}"
    fi

    tar -xzf "${archive}" -C "${tmpdir}" || return "${LIB_ERROR_FILE_OPERATION}"
    local src="${tmpdir}/bao"
    if ! is::file "${src}" || ! is::executable "${src}"; then
        log::error "OpenBao: в архиве нет исполняемого bao / archive has no executable bao"
        return "${LIB_ERROR_FILE_OPERATION}"
    fi
    local -r bin_dir="$(dirname -- "${BS_OPENBAO_BIN}")"
    is::dir "${bin_dir}" || mkdir -p -- "${bin_dir}" || return "${LIB_ERROR_FILE_OPERATION}"
    local tmp_bin="${BS_OPENBAO_BIN}.tmp.$$"
    install -m 0755 -- "${src}" "${tmp_bin}" || return "${LIB_ERROR_FILE_OPERATION}"
    if ! mv -f -- "${tmp_bin}" "${BS_OPENBAO_BIN}"; then
        rm -f -- "${tmp_bin}"
        return "${LIB_ERROR_FILE_OPERATION}"
    fi
    log::info "OpenBao установлен / installed: ${BS_OPENBAO_BIN} (${version})"
    return 0
}

# @description Create the system user / Создать системного пользователя
openbao_server::ensure_user() {
    openbao_server::init || return $?
    if id "${BS_OPENBAO_USER}" >/dev/null 2>&1; then
        log::info "OpenBao: пользователь уже есть / user exists: ${BS_OPENBAO_USER}"
        return 0
    fi
    if openbao_server::__dry; then
        log::warn "[DRY-RUN] useradd --system ${BS_OPENBAO_USER}"
        return 0
    fi
    is::command useradd || {
        log::error "OpenBao: нужен useradd / useradd is required"
        return "${LIB_ERROR_DEPENDENCY_MISSING}"
    }
    if ! useradd --system --home-dir "${BS_OPENBAO_DATA_DIR}" --shell /usr/sbin/nologin \
        --user-group "${BS_OPENBAO_USER}"; then
        log::error "OpenBao: не удалось создать пользователя / cannot create user: ${BS_OPENBAO_USER}"
        return "${LIB_ERROR_FILE_OPERATION}"
    fi
    if is::command passwd; then
        passwd -l "${BS_OPENBAO_USER}" >/dev/null 2>&1 || log::warn "OpenBao: не удалось заблокировать пароль / cannot lock password"
    fi
    log::info "OpenBao: создан пользователь / user created: ${BS_OPENBAO_USER}"
}

# @private Build subjectAltName list / Собрать список subjectAltName
# @param $@ Hosts / Хосты
# @stdout comma-separated SAN / SAN через запятую
openbao_server::__san() {
    local -a hosts=("$@")
    (( ${#hosts[@]} > 0 )) || hosts=(localhost 127.0.0.1 ::1)
    local host seen="," out=""
    for host in "${hosts[@]}" localhost 127.0.0.1 ::1; do
        [[ -n "${host}" ]] || continue
        if [[ ! "${host}" =~ ^[A-Za-z0-9_.:-]+$ ]]; then
            log::error "OpenBao: недопустимый SAN / invalid SAN: ${host}"
            return "${LIB_ERROR_INVALID_INPUT}"
        fi
        [[ "${seen}" == *",${host},"* ]] && continue
        seen+="${host},"
        if [[ "${host}" =~ ^[0-9.]+$ || "${host}" == *:* ]]; then
            out+="IP:${host},"
        else
            out+="DNS:${host},"
        fi
    done
    printf '%s' "${out%,}"
}

# @description Generate a self-signed CA and server certificate /
# Сгенерировать самоподписанный CA и серверный сертификат
# @param $@ Hosts for SAN / Хосты для SAN
openbao_server::tls_selfsigned() {
    openbao_server::init || return $?
    is::command openssl || {
        log::error "OpenBao: нужен openssl / openssl is required"
        return "${LIB_ERROR_DEPENDENCY_MISSING}"
    }
    openbao_server::__dir "${BS_OPENBAO_TLS_DIR}" "0750" || return $?
    if openbao_server::__dry; then
        log::warn "[DRY-RUN] openssl: CA + server certificate in ${BS_OPENBAO_TLS_DIR}"
        return 0
    fi
    local -r ca_key="${BS_OPENBAO_TLS_DIR}/ca.key" ca_crt="${BS_OPENBAO_TLS_DIR}/ca.crt"
    local -r csr="${BS_OPENBAO_TLS_DIR}/server.csr" ext="${BS_OPENBAO_TLS_DIR}/server.ext"
    local san rc=0
    san="$(openbao_server::__san "$@")" || rc=$?
    (( rc == 0 )) || return "${rc}"
    if ! openssl genrsa -out "${ca_key}" 4096 >/dev/null 2>&1 \
        || ! openssl req -x509 -new -nodes -key "${ca_key}" -sha256 -days 3650 \
            -subj "/CN=BS OpenBao CA" -out "${ca_crt}" >/dev/null 2>&1 \
        || ! openssl genrsa -out "${BS_OPENBAO_TLS_KEY}" 4096 >/dev/null 2>&1 \
        || ! openssl req -new -key "${BS_OPENBAO_TLS_KEY}" -subj "/CN=openbao" -out "${csr}" >/dev/null 2>&1; then
        log::error "OpenBao: не удалось создать ключи/CSR / cannot create keys/CSR"
        return "${LIB_ERROR_FILE_OPERATION}"
    fi
    printf 'basicConstraints=CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=%s\n' \
        "${san}" > "${ext}" || return "${LIB_ERROR_FILE_OPERATION}"
    if ! openssl x509 -req -in "${csr}" -CA "${ca_crt}" -CAkey "${ca_key}" -CAcreateserial \
        -out "${BS_OPENBAO_TLS_CERT}" -days 825 -sha256 -extfile "${ext}" >/dev/null 2>&1; then
        log::error "OpenBao: не удалось подписать сертификат / cannot sign certificate"
        return "${LIB_ERROR_FILE_OPERATION}"
    fi
    rm -f -- "${csr}" "${ext}" "${BS_OPENBAO_TLS_DIR}/ca.srl"
    chmod 600 "${ca_key}" "${BS_OPENBAO_TLS_KEY}" || return "${LIB_ERROR_FILE_OPERATION}"
    chmod 644 "${ca_crt}" "${BS_OPENBAO_TLS_CERT}" || return "${LIB_ERROR_FILE_OPERATION}"
    if (( EUID == 0 )) && is::command chown; then
        chown root:"${BS_OPENBAO_GROUP}" "${BS_OPENBAO_TLS_KEY}" "${BS_OPENBAO_TLS_CERT}" 2>/dev/null || true
        chown root:root "${ca_key}" 2>/dev/null || true
    fi
    log::info "OpenBao: TLS создан / TLS created: ${BS_OPENBAO_TLS_DIR}"
}

# @description Render the HCL config / Отрисовать HCL-конфиг
# @param $1 dev|prod / dev|prod
# @stdout HCL / HCL
openbao_server::render_config() {
    local -r profile="${1:-prod}"
    openbao_server::init || return $?
    local tls_disable=0
    if [[ "${profile}" == "dev" || "${BS_OPENBAO_TLS_MODE}" == "off" ]]; then
        tls_disable=1
    fi
    local scheme="https"
    (( tls_disable == 1 )) && scheme="http"
    local host="${BS_OPENBAO_LISTEN%:*}" port="${BS_OPENBAO_LISTEN##*:}"
    [[ "${host}" == "0.0.0.0" || "${host}" == "::" ]] && host="127.0.0.1"
    local api_addr="${scheme}://${host}:${port}"
    local cluster_port=$(( 10#${port} + 1 ))
    local cluster_addr="${scheme}://${host}:${cluster_port}"

    printf 'ui = true\n'
    printf 'disable_mlock = true\n\n'
    printf 'storage "file" {\n  path = "%s/data"\n}\n\n' "${BS_OPENBAO_DATA_DIR}"
    printf 'listener "tcp" {\n  address     = "%s"\n  tls_disable = %d\n' \
        "${BS_OPENBAO_LISTEN}" "${tls_disable}"
    if (( tls_disable == 0 )); then
        printf '  tls_cert_file = "%s"\n  tls_key_file  = "%s"\n' \
            "${BS_OPENBAO_TLS_CERT}" "${BS_OPENBAO_TLS_KEY}"
    fi
    printf '}\n\n'
    printf 'api_addr = "%s"\n' "${api_addr}"
    printf 'cluster_addr = "%s"\n' "${cluster_addr}"
}

# @description Configure directories, TLS and config / Настроить каталоги, TLS и конфиг
# @param $1 dev|prod / dev|prod
openbao_server::configure() {
    local -r profile="${1:-prod}"
    openbao_server::init || return $?
    openbao_server::__dir "${BS_OPENBAO_DATA_DIR}" "0700" || return $?
    openbao_server::__dir "${BS_OPENBAO_DATA_DIR}/data" "0700" || return $?
    openbao_server::__dir "${BS_OPENBAO_CONFIG_DIR}" "0750" || return $?

    if [[ "${profile}" == "prod" && "${BS_OPENBAO_TLS_MODE}" == "selfsigned" ]]; then
        if [[ ! -f "${BS_OPENBAO_TLS_CERT}" || ! -f "${BS_OPENBAO_TLS_KEY}" ]]; then
            openbao_server::tls_selfsigned "localhost" "127.0.0.1" || return $?
        fi
    elif [[ "${profile}" == "prod" && "${BS_OPENBAO_TLS_MODE}" == "files" ]]; then
        if [[ ! -r "${BS_OPENBAO_TLS_CERT}" || ! -r "${BS_OPENBAO_TLS_KEY}" ]]; then
            log::error "OpenBao: TLS-файлы не найдены / TLS files not found"
            return "${LIB_ERROR_FILE_NOT_FOUND}"
        fi
    fi

    local config
    config="$(openbao_server::render_config "${profile}")" || return $?
    openbao_server::__backup "${BS_OPENBAO_CONFIG}" || return $?
    openbao_server::__write_file "${BS_OPENBAO_CONFIG}" "0640" "${config}" || return $?
    log::info "OpenBao: конфиг записан / config written: ${BS_OPENBAO_CONFIG}"
}

# @description Render the systemd unit / Отрисовать systemd-юнит
# @stdout unit file / unit file
openbao_server::unit_render() {
    openbao_server::init || return $?
    printf '[Unit]\n'
    printf 'Description=OpenBao server\n'
    printf 'After=network-online.target\nWants=network-online.target\n\n'
    printf '[Service]\n'
    printf 'Type=simple\n'
    printf 'User=%s\nGroup=%s\n' "${BS_OPENBAO_USER}" "${BS_OPENBAO_GROUP}"
    printf 'ExecStart=%s server -config=%s\n' "${BS_OPENBAO_BIN}" "${BS_OPENBAO_CONFIG}"
    printf 'Restart=on-failure\nRestartSec=5\nLimitNOFILE=65536\n'
    printf 'NoNewPrivileges=true\nPrivateTmp=true\nProtectSystem=strict\nProtectHome=true\n'
    printf 'ReadWritePaths=%s\n\n' "${BS_OPENBAO_DATA_DIR}"
    printf '[Install]\nWantedBy=multi-user.target\n'
}

# @description Write and start the systemd unit / Записать и запустить systemd-юнит
openbao_server::install_service() {
    openbao_server::init || return $?
    if ! systemd::available; then
        log::error "OpenBao: systemd недоступен / systemd is not available"
        return "${LIB_ERROR_DEPENDENCY_MISSING}"
    fi
    local unit
    unit="$(openbao_server::unit_render)" || return $?
    openbao_server::__backup "$(systemd::unit_path "${BS_OPENBAO_SERVICE}")" || return $?
    if openbao_server::__dry; then
        log::warn "[DRY-RUN] write unit ${BS_OPENBAO_SERVICE} and enable --now"
        return 0
    fi
    systemd::unit_write "${BS_OPENBAO_SERVICE}" "${unit}" || return "${LIB_ERROR_FILE_OPERATION}"
    systemd::daemon_reload || return "${LIB_ERROR_FILE_OPERATION}"
    systemd::unit_enable_now "${BS_OPENBAO_SERVICE}" || return "${LIB_ERROR_FILE_OPERATION}"
    log::info "OpenBao: сервис запущен / service started: ${BS_OPENBAO_SERVICE}"
}

# @private Local API address / Локальный адрес API
# @param [$1] dev|prod / dev|prod
# @stdout URL / URL
openbao_server::local_api_addr() {
    local -r profile="${1:-prod}"
    local scheme="https"
    [[ "${profile}" == "dev" || "${BS_OPENBAO_TLS_MODE}" == "off" ]] && scheme="http"
    local host="${BS_OPENBAO_LISTEN%:*}" port="${BS_OPENBAO_LISTEN##*:}"
    [[ "${host}" == "0.0.0.0" || "${host}" == "::" ]] && host="127.0.0.1"
    printf '%s://%s:%s' "${scheme}" "${host}" "${port}"
}

# @private Point the client module at this server / Направить клиент на этот сервер
openbao_server::__client_init() {
    BS_OPENBAO_ADDR="$(openbao_server::local_api_addr prod)"
    BS_OPENBAO_CACERT=""
    if [[ "${BS_OPENBAO_TLS_MODE}" == "selfsigned" ]]; then
        BS_OPENBAO_CACERT="${BS_OPENBAO_TLS_DIR}/ca.crt"
    elif [[ "${BS_OPENBAO_TLS_MODE}" == "files" ]]; then
        BS_OPENBAO_CACERT="${BS_OPENBAO_TLS_CA}"
    fi
    BS_OPENBAO_TOKEN=""
    BS_OPENBAO_TOKEN_FILE="/dev/null"
    openbao::init
}

# @description Initialize the cluster and save secrets / Инициализировать кластер и сохранить секреты
openbao_server::init_cluster() {
    openbao_server::init || return $?
    is::file "${BS_OPENBAO_INIT_FILE}" && {
        log::error "OpenBao: init-файл уже существует / init file already exists: ${BS_OPENBAO_INIT_FILE}"
        return "${LIB_ERROR_CONFLICT}"
    }
    is::executable "${BS_OPENBAO_BIN}" || {
        log::error "OpenBao: бинарник не найден / binary not found: ${BS_OPENBAO_BIN}"
        return "${LIB_ERROR_FILE_NOT_FOUND}"
    }
    if openbao_server::__dry; then
        log::warn "[DRY-RUN] bao operator init -> ${BS_OPENBAO_INIT_FILE}"
        return 0
    fi
    local api ca out
    api="$(openbao_server::local_api_addr prod)"
    ca=""
    [[ "${BS_OPENBAO_TLS_MODE}" == "selfsigned" ]] && ca="${BS_OPENBAO_TLS_DIR}/ca.crt"
    local -a env_args=("BAO_ADDR=${api}")
    [[ -n "${ca}" ]] && env_args+=("BAO_CACERT=${ca}")
    out="$(env "${env_args[@]}" "${BS_OPENBAO_BIN}" operator init \
        -key-shares="${BS_OPENBAO_INIT_SHARES}" -key-threshold="${BS_OPENBAO_INIT_THRESHOLD}" \
        -format=json 2>/dev/null)" || {
        log::error "OpenBao: operator init не удался / failed"
        return "${E_ERROR}"
    }
    if is::command jq; then
        printf '%s' "${out}" | jq empty >/dev/null 2>&1 || {
            log::error "OpenBao: operator init вернул не-JSON / returned invalid JSON"
            return "${OPENBAO_ERROR_JSON}"
        }
    fi
    openbao_server::__write_file "${BS_OPENBAO_INIT_FILE}" "0600" "${out}" || return $?
    log::info "OpenBao: ключи и root token сохранены / keys and root token saved: ${BS_OPENBAO_INIT_FILE}"
}

# @description Unseal from the init file / Разблокировать по init-файлу
openbao_server::unseal() {
    openbao_server::init || return $?
    is::file "${BS_OPENBAO_INIT_FILE}" || {
        log::error "OpenBao: init-файл не найден / init file not found: ${BS_OPENBAO_INIT_FILE}"
        return "${LIB_ERROR_FILE_NOT_FOUND}"
    }
    local jq_bin="${BS_OPENBAO_JQ:-jq}"
    is::command "${jq_bin}" || {
        log::error "OpenBao: нужен jq / jq is required"
        return "${LIB_ERROR_DEPENDENCY_MISSING}"
    }
    if openbao_server::__dry; then
        log::warn "[DRY-RUN] unseal from ${BS_OPENBAO_INIT_FILE}"
        return 0
    fi

    local old_addr="${BS_OPENBAO_ADDR-}" old_token="${BS_OPENBAO_TOKEN-}" old_ca="${BS_OPENBAO_CACERT-}"
    local old_ns="${BS_OPENBAO_NAMESPACE-}" old_tf="${BS_OPENBAO_TOKEN_FILE-}"
    local rc=0
    openbao_server::__client_init || rc=$?
    if (( rc == 0 )); then
        local key i=0
        while IFS= read -r key; do
            [[ -n "${key}" ]] || continue
            i=$((i + 1))
            openbao::unseal "${key}" >/dev/null || { rc=$?; break; }
            (( i >= BS_OPENBAO_INIT_THRESHOLD )) && break
        done < <("${jq_bin}" -r '.unseal_keys_b64[]' "${BS_OPENBAO_INIT_FILE}" 2>/dev/null)
        if (( rc == 0 )); then
            local status sealed
            status="$(openbao::seal_status)" || rc=$?
            sealed="$(printf '%s' "${status}" | "${jq_bin}" -r '.sealed' 2>/dev/null)"
            [[ "${sealed}" == "false" ]] || {
                log::error "OpenBao: сервер всё ещё sealed / server is still sealed"
                rc="${E_ERROR}"
            }
        fi
    fi

    BS_OPENBAO_ADDR="${old_addr}"
    BS_OPENBAO_TOKEN="${old_token}"
    BS_OPENBAO_CACERT="${old_ca}"
    BS_OPENBAO_NAMESPACE="${old_ns}"
    BS_OPENBAO_TOKEN_FILE="${old_tf}"
    openbao::init >/dev/null 2>&1 || true
    return "${rc}"
}

# @description Server status / Статус сервера
# @stdout JSON / JSON
openbao_server::status() {
    openbao_server::init || return $?
    local api ca
    api="$(openbao_server::local_api_addr prod)"
    ca=""
    [[ "${BS_OPENBAO_TLS_MODE}" == "selfsigned" ]] && ca="${BS_OPENBAO_TLS_DIR}/ca.crt"
    if is::executable "${BS_OPENBAO_BIN}"; then
        local -a env_args=("BAO_ADDR=${api}")
        [[ -n "${ca}" ]] && env_args+=("BAO_CACERT=${ca}")
        env "${env_args[@]}" "${BS_OPENBAO_BIN}" status -format=json 2>/dev/null && return 0
    fi
    openbao_server::__client_init || return $?
    openbao::health
}

# @description Wait until the API answers / Ждать ответа API
# @param [$1] Timeout in seconds / Таймаут в секундах
openbao_server::wait_ready() {
    local -r timeout="${1:-${BS_OPENBAO_TIMEOUT}}"
    openbao_server::__client_init || return $?
    local -i i=0
    while (( i < timeout )); do
        openbao::health >/dev/null 2>&1 && return 0
        sleep 1
        i=$((i + 1))
    done
    log::error "OpenBao: сервер не ответил за ${timeout}с / did not answer in ${timeout}s"
    return "${LIB_ERROR_TIMEOUT}"
}

# @description Print the dev server command / Напечатать команду dev-сервера
# @stdout command / команда
openbao_server::dev_command() {
    printf 'env BAO_DEV_ROOT_TOKEN_ID=%q BAO_ADDR=%q %q server -dev -dev-listen-address=%q' \
        "${BS_OPENBAO_DEV_TOKEN}" "http://${BS_OPENBAO_DEV_LISTEN}" \
        "${BS_OPENBAO_BIN}" "${BS_OPENBAO_DEV_LISTEN}"
}

# @description Start a foreground dev server (replaces the shell) /
# Запустить dev-сервер на переднем плане (заменяет shell)
openbao_server::dev_start() {
    openbao_server::init || return $?
    is::executable "${BS_OPENBAO_BIN}" || {
        log::error "OpenBao: бинарник не найден / binary not found: ${BS_OPENBAO_BIN}"
        return "${LIB_ERROR_FILE_NOT_FOUND}"
    }
    [[ -n "${BS_OPENBAO_DEV_TOKEN}" ]] || BS_OPENBAO_DEV_TOKEN="$(head -c 24 /dev/urandom | base64 | tr '+/' '_-' | tr -d '\n')"
    if openbao_server::__dry; then
        log::warn "[DRY-RUN] $(openbao_server::dev_command)"
        return 0
    fi
    log::info "OpenBao dev: остановить / stop — Ctrl-C"
    exec env "BAO_DEV_ROOT_TOKEN_ID=${BS_OPENBAO_DEV_TOKEN}" \
        "BAO_ADDR=http://${BS_OPENBAO_DEV_LISTEN}" \
        "${BS_OPENBAO_BIN}" server -dev -dev-listen-address="${BS_OPENBAO_DEV_LISTEN}"
}

# @description Full server apply / Полное применение сервера
# @param $1 dev|prod / dev|prod
openbao_server::apply() {
    local -r profile="${1:-prod}"
    openbao_server::init || return $?
    case "${profile}" in
        dev)
            openbao_server::install || return $?
            log::info "OpenBao dev готов / ready: $(openbao_server::dev_command)"
            return 0
            ;;
        prod)
            openbao_server::install || return $?
            openbao_server::ensure_user || return $?
            openbao_server::configure prod || return $?
            openbao_server::install_service || return $?
            if openbao_server::__dry; then
                log::warn "[DRY-RUN] init, unseal and health checks skipped"
                return 0
            fi
            openbao_server::wait_ready || return $?
            if ! is::file "${BS_OPENBAO_INIT_FILE}"; then
                openbao_server::init_cluster || return $?
            fi
            openbao_server::unseal || return $?
            openbao_server::wait_ready || return $?
            log::info "OpenBao prod готов / ready: $(openbao_server::local_api_addr prod)"
            return 0
            ;;
        *)
            log::error "OpenBao: профиль должен быть dev|prod / profile must be dev|prod"
            return "${LIB_ERROR_INVALID_INPUT}"
            ;;
    esac
}
