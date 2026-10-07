#!/usr/bin/env bs
# shellcheck shell=bash
# lib/system/fail2ban.sh — fail2ban jail config: parameter catalog with Russian
# tips, validation, profiles, INI rendering, safe install with rollback
# lib/system/fail2ban.sh — конфиг джейлов fail2ban: каталог параметров с
# русскими подсказками, валидация, профили, INI-рендер, безопасная установка
#
# @depends core/lang, core/const, core/logger, core/utils, lib/io/files, lib/data/format
# @tier core

# Source Guard / Защита от повторной загрузки
bs::guard "LIB_SYSTEM_FAIL2BAN" || return 0

# Dependencies / Зависимости
bs::source_relative "../../core/lang.sh" "../../core/const.sh" \
    "../../core/logger.sh" "../../core/utils.sh" "../io/files.sh" "../data/format.sh"

# @global BS_FAIL2BAN_DIR — Fail2ban: config root (category: hook)
# @global BS_FAIL2BAN_DIR — Fail2ban: корень конфигов (категория: hook)
declare -g BS_FAIL2BAN_DIR="/etc/fail2ban"
# @global BS_FAIL2BAN_DROPIN — Fail2ban: drop-in path relative to dir (category: hook)
# @global BS_FAIL2BAN_DROPIN — Fail2ban: путь drop-in относительно каталога (категория: hook)
declare -g BS_FAIL2BAN_DROPIN="jail.d/99-bs.conf"
# @global BS_FAIL2BAN_CLIENT — Fail2ban: client binary or test mock (category: hook)
# @global BS_FAIL2BAN_CLIENT — Fail2ban: клиент или мок для тестов (категория: hook)
declare -g BS_FAIL2BAN_CLIENT="fail2ban-client"
# @global BS_FAIL2BAN_SERVICE — Fail2ban: systemd unit name (category: hook)
# @global BS_FAIL2BAN_SERVICE — Fail2ban: имя systemd-юнита (категория: hook)
declare -g BS_FAIL2BAN_SERVICE="fail2ban"
# @global BS_FAIL2BAN_DRY_RUN — Fail2ban: 1 = no write/reload (category: hook)
# @global BS_FAIL2BAN_DRY_RUN — Fail2ban: 1 = без записи и reload (категория: hook)
declare -g BS_FAIL2BAN_DRY_RUN=0

# @global F2B_MARK_BEGIN — Fail2ban: managed-block begin marker (category: constant)
# @global F2B_MARK_BEGIN — Fail2ban: маркер начала управляемого блока (категория: constant)
readonly F2B_MARK_BEGIN="# BEGIN bs-fail2ban"
# @global F2B_MARK_END — Fail2ban: managed-block end marker (category: constant)
# @global F2B_MARK_END — Fail2ban: маркер конца управляемого блока (категория: constant)
readonly F2B_MARK_END="# END bs-fail2ban"

# @global F2B_DEFAULT_ORDER — Fail2ban: [DEFAULT] param order (category: constant)
# @global F2B_DEFAULT_ORDER — Fail2ban: порядок параметров [DEFAULT] (категория: constant)
declare -ga F2B_DEFAULT_ORDER=(bantime findtime maxretry ignoreip backend \
    banaction action chain bantime.increment bantime.factor bantime.maxtime \
    bantime.rndtime bantime.overalljails destemail sender mta)
# @global F2B_DEFAULT — Fail2ban: [DEFAULT] type|default|recommended (category: constant)
# @global F2B_DEFAULT — Fail2ban: [DEFAULT] type|default|recommended (категория: constant)
declare -gA F2B_DEFAULT=(
    [bantime]='time|10m|1h'
    [findtime]='time|10m|10m'
    [maxretry]='int|5|3'
    [ignoreip]='iplist||'
    [backend]='enum:auto,pyinotify,gamin,systemd,rsyslog,polling|auto|systemd'
    [banaction]='string|iptables-multiport|iptables-multiport'
    [action]='string||'
    [chain]='enum:INPUT,FORWARD,DOCKER-USER|INPUT|INPUT'
    [bantime.increment]='bool|false|true'
    [bantime.factor]='int|1|2'
    [bantime.maxtime]='time|1d|1d'
    [bantime.rndtime]='time||'
    [bantime.overalljails]='bool|false|false'
    [destemail]='string||'
    [sender]='string||'
    [mta]='enum:sendmail,mail,mailx,null|sendmail|sendmail'
)

# @global F2B_JAIL_ORDER — Fail2ban: jail param order (category: constant)
# @global F2B_JAIL_ORDER — Fail2ban: порядок параметров джейла (категория: constant)
declare -ga F2B_JAIL_ORDER=(enabled port filter logpath mode maxretry bantime \
    findtime ignoreip backend action banaction)
# @global F2B_JAIL_PARAM — Fail2ban: jail type|default|recommended (category: constant)
# @global F2B_JAIL_PARAM — Fail2ban: тип|default|recommended джейла (категория: constant)
declare -gA F2B_JAIL_PARAM=(
    [enabled]='bool|false|true'
    [port]='string||'
    [filter]='string||'
    [logpath]='pathlist||'
    [mode]='enum:normal,aggressive,ddos|normal|normal'
    [maxretry]='int||'
    [bantime]='time||'
    [findtime]='time||'
    [ignoreip]='iplist||'
    [backend]='enum:auto,pyinotify,gamin,systemd,rsyslog,polling|auto|systemd'
    [action]='string||'
    [banaction]='string||'
)

# @global F2B_TIPS — Fail2ban: two-line Russian tip per param (category: constant)
# @global F2B_TIPS — Fail2ban: двухстрочная русская подсказка на параметр (категория: constant)
declare -gA F2B_TIPS=(
    [bantime]=$'На сколько банят нарушителя по умолчанию.\n-1 — навсегда; 1h/10m/1d — понятные сроки.'
    [findtime]=$'Окно, в котором считаются попытки до бана.\nНапример 10m: не более maxretry попыток за 10 минут.'
    [maxretry]=$'Сколько неудач допускается до бана.\n3-5 — баланс между защитой и ложными срабатываниями.'
    [ignoreip]=$'IP/подсети, которые НИКОГДА не банятся.\nОбязательно впишите свой админ-IP, чтобы не отрезать себя.'
    [backend]=$'Чем читать логи: systemd, rsyslog, polling, pyinotify.\nsystemd на современных дистрибутивах надёжнее всего.'
    [banaction]=$'Действие бана: iptables-multiport, firewallcmd-ipset, nftables.\nСогласуйте с вашим firewall, иначе бан не сработает.'
    [action]=$'Готовое действие (бан + уведомление).\nПусто — только banaction; %(...)s подставит данные.'
    [chain]=$'Цепочка iptables для бана.\nINPUT — обычный хост; DOCKER-USER — если контейнеры за NAT.'
    [bantime.increment]=$'Увеличивать срок бана при повторах.\nХорошо отсекает рецидивистов.'
    [bantime.factor]=$'Во сколько раз растить bantime при повторе.\n2 — удвоение каждый раз.'
    [bantime.maxtime]=$'Потолок растущего bantime.\nЧтобы рецидивист не забанился «навсегда» случайно.'
    [bantime.rndtime]=$'Случайный разброс срока бана.\nМешает атакующему предсказать окно блокировки.'
    [bantime.overalljails]=$'Считать повторы суммарно по всем джейлам.\nМеньше «перелива» атак между сервисами.'
    [destemail]=$'E-mail для уведомлений о банах.\nРаботает только с action, умеющим отправлять почту.'
    [sender]=$'Адрес отправителя уведомлений.\nОставьте пустым, если почта не нужна.'
    [mta]=$'Почтовый агент для уведомлений.\nsendmail/mail/mailx; null отключает уведомления.'
    [enabled]=$'Включён ли джейл.\ntrue включает весь набор правил фильтра и лога.'
    [port]=$'Порты/сервисы джейла (например ssh или 2222).\nПусто — берётся из фильтра; укажите, если порт нестандартный.'
    [filter]=$'Имя фильтра из filter.d.\nОпределяет, какие записи лога считаются атакой.'
    [logpath]=$'Путь к логу, за которым следит джейл.\n%(sshd_log)s и подобные подставляются из fail2ban.conf.'
    [mode]=$'Режим строгости фильтра: normal/aggressive/ddos.\naggressive ловит больше, ddos — против флуда (не у всех фильтров).'
)

# @global F2B_JAILS — Fail2ban: jail catalog filter|logpath|port|recommended (category: constant)
# @global F2B_JAILS — Fail2ban: каталог джейлов filter|logpath|port|рекомендован (категория: constant)
declare -gA F2B_JAILS=(
    [sshd]='sshd|%(sshd_log)s|ssh|true'
    [sshd-ddos]='sshd|%(sshd_log)s|ssh|false'
    [recidive]='recidive|%(recidive_log)s||false'
    [nginx-http-auth]='nginx-http-auth|%(nginx_error_log)s||false'
    [nginx-botsearch]='nginx-botsearch|%(nginx_access_log)s||false'
    [nginx-limit-req]='nginx-limit-req|%(nginx_error_log)s||false'
    [apache-auth]='apache-auth|%(apache_error_log)s||false'
    [apache-badbots]='apache-badbots|%(apache_access_log)s||false'
    [apache-noscript]='apache-noscript|%(apache_error_log)s||false'
    [apache-overflows]='apache-overflows|%(apache_error_log)s||false'
    [postfix]='postfix|%(postfix_log)s||false'
    [postfix-sasl]='postfix-sasl|%(postfix_log)s||false'
    [dovecot]='dovecot|%(dovecot_log)s||false'
    [exim]='exim|%(exim_log)s||false'
    [vsftpd]='vsftpd|%(vsftpd_log)s||false'
    [proftpd]='proftpd|%(proftpd_log)s||false'
    [pure-ftpd]='pure-ftpd|%(pureftpd_log)s||false'
    [roundcube-auth]='roundcube-auth|||false'
    [phpmyadmin]='phpmyadmin-syslog|||false'
)

# @private Look up a param's meta in DEFAULT then JAIL / Метаданные параметра
# @param $1 Param name / Имя параметра
# @stdout type|default|recommended / тип|default|recommended
fail2ban::__meta() {
    local -r name="${1:?param name required}"
    if [[ -n "${F2B_DEFAULT[$name]:-}" ]]; then printf '%s\n' "${F2B_DEFAULT[$name]}"; return 0; fi
    if [[ -n "${F2B_JAIL_PARAM[$name]:-}" ]]; then printf '%s\n' "${F2B_JAIL_PARAM[$name]}"; return 0; fi
    return "${LIB_ERROR_INVALID_ARGS}"
}

# @description Report missing runtime pieces (never fails) / Сообщить об отсутствии
fail2ban::init() {
    is::command "${BS_FAIL2BAN_CLIENT}" || printf 'fail2ban-client не найден / not found: %s\n' "${BS_FAIL2BAN_CLIENT}" >&2
    is::dir "${BS_FAIL2BAN_DIR}" || printf 'каталог / dir отсутствует / missing: %s\n' "${BS_FAIL2BAN_DIR}" >&2
    return "${E_SUCCESS}"
}

# @description List params of a scope / Список параметров области
# @param $1 default|jail / область
# @stdout name<TAB>type<TAB>default<TAB>recommended / строки TSV
fail2ban::param_list() {
    local -r scope="${1:-default}"
    local -a order=()
    case "${scope}" in
        default) order=("${F2B_DEFAULT_ORDER[@]}") ;;
        jail)    order=("${F2B_JAIL_ORDER[@]}") ;;
        *) return "${LIB_ERROR_INVALID_ARGS}" ;;
    esac
    local name
    for name in "${order[@]}"; do
        printf '%s\t%s\n' "${name}" "$(fail2ban::__meta "${name}")"
    done
}

# @description Param type / Тип параметра
# @param $1 Param name / Имя параметра
# @stdout type / тип
fail2ban::param_type() {
    local meta
    meta="$(fail2ban::__meta "${1:?param name required}")" || return $?
    printf '%s\n' "${meta%%|*}"
}

# @description Two-line Russian tip / Двухстрочная русская подсказка
# @param $1 Param name / Имя параметра
# @stdout tip / подсказка
fail2ban::param_desc() {
    local -r tip="${F2B_TIPS[${1:?param name required}]:-}"
    is::empty "${tip}" && return "${LIB_ERROR_INVALID_ARGS}"
    printf '%s\n' "${tip}"
}

# @description Default value / Значение по умолчанию
fail2ban::param_default() {
    local meta; meta="$(fail2ban::__meta "${1:?param name required}")" || return $?
    local rest="${meta#*|}"
    printf '%s\n' "${rest%%|*}"
}

# @description Recommended value / Рекомендуемое значение
fail2ban::param_recommended() {
    local meta; meta="$(fail2ban::__meta "${1:?param name required}")" || return $?
    printf '%s\n' "${meta##*|}"
}

# @description Jail catalog / Каталог джейлов
# @stdout jail<TAB>filter<TAB>logpath<TAB>port<TAB>recommended / строки TSV
fail2ban::jails() {
    local jail
    for jail in $(printf '%s\n' "${!F2B_JAILS[@]}" | sort); do
        printf '%s\t%s\n' "${jail}" "${F2B_JAILS[$jail]}"
    done
}

# @description Validate a value for a catalog parameter by its type.
# @description Проверить значение параметра каталога по его типу.
# @param $1 Param name / Имя параметра
# @param $2 Value / Значение
# @return E_SUCCESS / LIB_ERROR_INVALID_INPUT / LIB_ERROR_INVALID_ARGS
fail2ban::validate() {
    local -r name="${1:?param name required}" value="${2-}"
    local type
    type="$(fail2ban::param_type "${name}")" || return $?
    if [[ "${value}" == *$'\n'* || "${value}" == *$'\r'* || "${value}" == *$'\t'* ]]; then
        return "${LIB_ERROR_INVALID_INPUT}"
    fi
    local entry
    case "${type}" in
        time)
            [[ "${value}" =~ ^-?[0-9]+([smhd][0-9]+)*[smhd]?$ ]] || return "${LIB_ERROR_INVALID_INPUT}"
            ;;
        int)
            [[ "${value}" =~ ^[0-9]+$ ]] || return "${LIB_ERROR_INVALID_INPUT}"
            ;;
        bool)
            [[ "${value}" == "true" || "${value}" == "false" ]] || return "${LIB_ERROR_INVALID_INPUT}"
            ;;
        enum:*)
            [[ ",${type#enum:}," == *",${value},"* ]] || return "${LIB_ERROR_INVALID_INPUT}"
            ;;
        iplist)
            local IFS=' ,'
            local -a toks=()
            read -ra toks <<< "${value}"
            (( ${#toks[@]} > 0 )) || return "${LIB_ERROR_INVALID_INPUT}"
            for entry in "${toks[@]}"; do
                [[ "${entry}" =~ ^[0-9A-Fa-f:.]+(/[0-9]{1,3})?$ ]] || return "${LIB_ERROR_INVALID_INPUT}"
            done
            ;;
        pathlist)
            local IFS=': ,'
            local -a toks=()
            read -ra toks <<< "${value}"
            for entry in "${toks[@]}"; do
                [[ "${entry}" =~ ^/ ]] || return "${LIB_ERROR_INVALID_INPUT}"
            done
            ;;
        string)
            [[ -n "${value}" && "${value}" =~ ^[A-Za-z0-9._%@:/()%-]+$ ]] || return "${LIB_ERROR_INVALID_INPUT}"
            ;;
        *)
            return "${LIB_ERROR_INVALID_ARGS}"
            ;;
    esac
    return "${E_SUCCESS}"
}

# @description Profile as section.param=value lines. strict extends basic,
# paranoid extends strict. / Профиль как строки section.param=value.
# @param $1 basic|strict|paranoid / имя профиля
fail2ban::profile() {
    local -r name="${1:?profile name required}"
    case "${name}" in
        basic)
            cat <<'EOF'
DEFAULT.bantime=10m
DEFAULT.findtime=10m
DEFAULT.maxretry=5
sshd.enabled=true
EOF
            ;;
        strict)
            fail2ban::profile basic
            cat <<'EOF'
DEFAULT.bantime=1h
DEFAULT.maxretry=3
DEFAULT.bantime.increment=true
DEFAULT.bantime.factor=2
DEFAULT.bantime.maxtime=1d
sshd-ddos.enabled=true
recidive.enabled=true
EOF
            ;;
        paranoid)
            fail2ban::profile strict
            cat <<'EOF'
DEFAULT.bantime=-1
DEFAULT.maxretry=2
DEFAULT.backend=systemd
EOF
            ;;
        *) return "${LIB_ERROR_INVALID_ARGS}" ;;
    esac
}

# @description Render an INI jail config from stdin.
# @description Отрендерить INI-конфиг джейлов из stdin.
#   Grammar: `@section NAME`, `key=value`, blank lines ignored.
#   [DEFAULT] first, other sections sorted; empty values skipped.
#   Грамматика: `@section NAME`, `key=value`, пустые строки игнорируются.
# @stdin section/param lines / строки секций и параметров
# @stdout INI config / INI-конфиг
fail2ban::render() {
    local -A vals=()
    local -a secs=()
    local cur="" line key val
    while IFS= read -r line || is::not_empty "${line}"; do
        is::empty "${line}" && continue
        if [[ "${line}" == "@section "* ]]; then
            cur="${line#@section }"
            arr::contains secs "${cur}" || secs+=("${cur}")
            continue
        fi
        is::empty "${cur}" && continue
        key="${line%%=*}"; val="${line#*=}"
        is::empty "${val}" && continue
        vals["${cur}.${key}"]="${val}"
    done

    printf '%s\n' "# Managed by BS fail2ban wizard / Сгенерировано визардом BS"
    printf '%s\n' "${F2B_MARK_BEGIN}"

    local name sec
    # [DEFAULT] first / сначала [DEFAULT]
    if arr::contains secs "DEFAULT"; then
        printf '[DEFAULT]\n'
        for name in "${F2B_DEFAULT_ORDER[@]}"; do
            val="${vals[DEFAULT.${name}]:-}"
            is::empty "${val}" && continue
            printf '%s = %s\n' "${name}" "${val}"
        done
    fi
    # other sections sorted / остальные секции по алфавиту
    local -a others=()
    for sec in "${secs[@]}"; do
        [[ "${sec}" == "DEFAULT" ]] && continue
        others+=("${sec}")
    done
    if (( ${#others[@]} > 0 )); then
        while IFS= read -r sec; do
            is::empty "${sec}" && continue
            local -a rows=()
            for name in "${F2B_JAIL_ORDER[@]}"; do
                val="${vals[${sec}.${name}]:-}"
                is::empty "${val}" && continue
                rows+=("${name} = ${val}")
            done
            (( ${#rows[@]} == 0 )) && continue
            printf '\n[%s]\n' "${sec}"
            printf '%s\n' "${rows[@]}"
        done < <(printf '%s\n' "${others[@]}" | sort)
    fi
    printf '%s\n' "${F2B_MARK_END}"
}

# @description Validate a config dir with `fail2ban-client -c <dir> -t`, or the
# live config with `-t` when no file is given.
# @description Проверить каталог конфигов через `fail2ban-client -c <dir> -t`,
# либо живой конфиг через `-t` без файла.
# @param $1 [optional] File whose dir holds the config / Файл, чей каталог проверяем
# @return client exit code; LIB_ERROR_DEPENDENCY_MISSING if client absent
fail2ban::test() {
    is::command "${BS_FAIL2BAN_CLIENT}" || return "${LIB_ERROR_DEPENDENCY_MISSING}"
    if is::not_empty "${1:-}"; then
        "${BS_FAIL2BAN_CLIENT}" -c "$(dirname -- "${1}")" -t
    else
        "${BS_FAIL2BAN_CLIENT}" -t
    fi
}

# @description Reload the fail2ban service (client reload), honoring dry-run.
# @description Перезагрузить fail2ban (client reload), с учётом dry-run.
fail2ban::reload() {
    if (( BS_FAIL2BAN_DRY_RUN == 1 )); then
        printf 'dry-run: %s reload\n' "${BS_FAIL2BAN_CLIENT}" >&2
        return "${E_SUCCESS}"
    fi
    is::command "${BS_FAIL2BAN_CLIENT}" || return "${LIB_ERROR_DEPENDENCY_MISSING}"
    "${BS_FAIL2BAN_CLIENT}" reload >/dev/null 2>&1
}

# @description Backup a file / Сделать копию файла
fail2ban::backup() {
    local -r file="${1:?file required}"
    is::file "${file}" || return "${LIB_ERROR_FILE_NOT_FOUND}"
    local -r dest="${file}.bak.$(date +%Y%m%d%H%M%S)"
    cp -a -- "${file}" "${dest}" || return "${LIB_ERROR_FILE_OPERATION}"
    printf '%s\n' "${dest}"
}

# @description Install a rendered config as a drop-in with backup + rollback.
# @description Установить конфиг как drop-in с backup и откатом.
# @param $1 Source file / Файл-источник
# @param $2 [optional] Target / Цель
fail2ban::install() {
    local -r src="${1:?source file required}"
    local -r target="${2:-${BS_FAIL2BAN_DIR}/${BS_FAIL2BAN_DROPIN}}"
    is::file "${src}" || return "${LIB_ERROR_FILE_NOT_FOUND}"
    if (( BS_FAIL2BAN_DRY_RUN == 1 )); then
        printf 'dry-run: install %s -> %s\n' "${src}" "${target}" >&2
        return "${E_SUCCESS}"
    fi
    is::command "${BS_FAIL2BAN_CLIENT}" || return "${LIB_ERROR_DEPENDENCY_MISSING}"
    local -r dir="$(dirname -- "${target}")"
    is::dir "${dir}" || mkdir -p -- "${dir}" 2>/dev/null || return "${LIB_ERROR_PERMISSION_DENIED}"
    is::writable "${dir}" || return "${LIB_ERROR_PERMISSION_DENIED}"

    if ! fail2ban::test "${src}" >/dev/null 2>&1; then
        printf 'fail2ban-client -t отклонил / rejected: %s\n' "${src}" >&2
        return "${LIB_ERROR_INVALID_INPUT}"
    fi

    local backup=""
    if is::file "${target}"; then
        backup="$(fail2ban::backup "${target}")" || return $?
    fi
    if ! cp -f -- "${src}" "${target}.tmp" || ! mv -f -- "${target}.tmp" "${target}"; then
        rm -f -- "${target}.tmp"
        return "${LIB_ERROR_FILE_OPERATION}"
    fi
    if ! fail2ban::test "${target}" >/dev/null 2>&1; then
        if is::not_empty "${backup}"; then cp -f -- "${backup}" "${target}"; else rm -f -- "${target}"; fi
        return "${LIB_ERROR_INVALID_INPUT}"
    fi
    fail2ban::reload || printf 'warning: reload %s failed\n' "${BS_FAIL2BAN_SERVICE}" >&2
    return "${E_SUCCESS}"
}

# @description Restore the newest backup / Восстановить новейшую копию
fail2ban::revert() {
    local -r target="${1:?target required}"
    local -a baks=()
    local f
    shopt -s nullglob
    for f in "${target}".bak.*; do baks+=("${f}"); done
    shopt -u nullglob
    (( ${#baks[@]} == 0 )) && return "${LIB_ERROR_FILE_NOT_FOUND}"
    local latest="${baks[0]}"
    for f in "${baks[@]}"; do [[ "${f}" > "${latest}" ]] && latest="${f}"; done
    cp -f -- "${latest}" "${target}" || return "${LIB_ERROR_FILE_OPERATION}"
    printf '%s\n' "${latest}"
}

# @description Available jails: filters present in filter.d/*.conf.
# @description Доступные джейлы: фильтры из filter.d/*.conf.
# @stdout jail names one per line / имена джейлов
fail2ban::detect() {
    local f
    local -a found=()
    for f in "${BS_FAIL2BAN_DIR}"/filter.d/*.conf; do
        [[ -f "${f}" ]] || continue
        found+=("$(basename -- "${f}" .conf)")
    done
    (( ${#found[@]} == 0 )) && return "${E_SUCCESS}"
    printf '%s\n' "${found[@]}" | sort -u
}

# @description fail2ban-client status, one line per record (format contract).
# @description Статус fail2ban, строка на запись (контракт форматов).
fail2ban::status() {
    is::command "${BS_FAIL2BAN_CLIENT}" || return "${LIB_ERROR_DEPENDENCY_MISSING}"
    "${BS_FAIL2BAN_CLIENT}" status 2>/dev/null | format::emit_lines status "${BS_OUTPUT_FORMAT:-string}"
}

# @description Banned IP list of a jail (format contract).
# @description Список забаненных IP джейла (контракт форматов).
# @param $1 Jail name / Имя джейла
fail2ban::jailed() {
    local -r jail="${1:?jail name required}"
    is::command "${BS_FAIL2BAN_CLIENT}" || return "${LIB_ERROR_DEPENDENCY_MISSING}"
    "${BS_FAIL2BAN_CLIENT}" status "${jail}" 2>/dev/null | format::emit_lines ip "${BS_OUTPUT_FORMAT:-string}"
}
