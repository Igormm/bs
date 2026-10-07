#!/usr/bin/env bs
# shellcheck shell=bash
# lib/system/sshd.sh — server-side sshd config: parameter catalog with Russian
# tips, validation, hardening profiles, rendering, safe install with rollback
# lib/system/sshd.sh — серверный конфиг sshd: каталог параметров с русскими
# подсказками, валидация, профили, рендер, безопасная установка с откатом
#
# @depends core/lang, core/const
# @tier gnu-linux

# Source Guard / Защита от повторной загрузки
bs::guard "LIB_SYSTEM_SSHD" || return 0

# Dependencies / Зависимости
bs::source_relative "../../core/lang.sh" "../../core/const.sh"

# @global SSHD_MARK_BEGIN — Sshd: managed-block begin marker (category: constant)
# @global SSHD_MARK_BEGIN — Sshd: маркер начала управляемого блока (категория: constant)
readonly SSHD_MARK_BEGIN="# BEGIN bs-sshd"
# @global SSHD_MARK_END — Sshd: managed-block end marker (category: constant)
# @global SSHD_MARK_END — Sshd: маркер конца управляемого блока (категория: constant)
readonly SSHD_MARK_END="# END bs-sshd"

# @global SSHD_SECTIONS — Sshd: ordered section names (category: constant)
# @global SSHD_SECTIONS — Sshd: упорядоченные имена секций (категория: constant)
declare -ga SSHD_SECTIONS=("Network" "Authentication" "Access Control" \
    "Forwarding" "Logging" "Cryptography" "SFTP" "Match")

# @global SSHD_PARAM_ORDER — Sshd: ordered catalog keys (category: constant)
# @global SSHD_PARAM_ORDER — Sshd: упорядоченные ключи каталога (категория: constant)
declare -ga SSHD_PARAM_ORDER=(Port ListenAddress AddressFamily LoginGraceTime \
    PermitRootLogin PasswordAuthentication PubkeyAuthentication \
    PermitEmptyPasswords KbdInteractiveAuthentication AuthenticationMethods \
    MaxAuthTries MaxSessions AllowUsers AllowGroups DenyUsers DenyGroups \
    X11Forwarding AllowTcpForwarding AllowAgentForwarding GatewayPorts \
    PermitTunnel SyslogFacility LogLevel Ciphers MACs KexAlgorithms \
    HostKeyAlgorithms UsePAM Subsystem ChrootDirectory ForceCommand PermitTTY)

# @global SSHD_PARAMS — Sshd: section|type|default|recommended per param (category: constant)
# @global SSHD_PARAMS — Sshd: section|type|default|recommended на параметр (категория: constant)
declare -gA SSHD_PARAMS=(
    [Port]='Network|port|22|22'
    [ListenAddress]='Network|addr|0.0.0.0|0.0.0.0'
    [AddressFamily]='Network|enum:any,inet,inet6|any|inet'
    [LoginGraceTime]='Network|time|120|30'
    [PermitRootLogin]='Authentication|enum:yes,no,prohibit-password,forced-commands-only|prohibit-password|no'
    [PasswordAuthentication]='Authentication|bool|yes|no'
    [PubkeyAuthentication]='Authentication|bool|yes|yes'
    [PermitEmptyPasswords]='Authentication|bool|no|no'
    [KbdInteractiveAuthentication]='Authentication|bool|yes|no'
    [AuthenticationMethods]='Authentication|csv||publickey'
    [MaxAuthTries]='Authentication|int|6|3'
    [MaxSessions]='Authentication|int|10|5'
    [AllowUsers]='Access Control|userlist||'
    [AllowGroups]='Access Control|grouplist||sshusers'
    [DenyUsers]='Access Control|userlist||'
    [DenyGroups]='Access Control|grouplist||'
    [X11Forwarding]='Forwarding|bool|no|no'
    [AllowTcpForwarding]='Forwarding|enum:yes,no,all,local,remote|yes|no'
    [AllowAgentForwarding]='Forwarding|bool|yes|no'
    [GatewayPorts]='Forwarding|bool|no|no'
    [PermitTunnel]='Forwarding|enum:yes,no,point-to-point,ethernet|no|no'
    [SyslogFacility]='Logging|enum:AUTH,DAEMON,USER,AUTHPRIV,LOCAL0,LOCAL1,LOCAL2,LOCAL3,LOCAL4,LOCAL5,LOCAL6,LOCAL7|AUTH|AUTH'
    [LogLevel]='Logging|enum:QUIET,FATAL,ERROR,INFO,VERBOSE,DEBUG1,DEBUG2,DEBUG3|INFO|VERBOSE'
    [Ciphers]='Cryptography|csv||chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr'
    [MACs]='Cryptography|csv||hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-64-etm@openssh.com'
    [KexAlgorithms]='Cryptography|csv||curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256'
    [HostKeyAlgorithms]='Cryptography|csv||'
    [UsePAM]='Cryptography|bool|yes|yes'
    [Subsystem]='SFTP|path|internal-sftp|internal-sftp'
    [ChrootDirectory]='Match|string||%h'
    [ForceCommand]='Match|string||internal-sftp'
    [PermitTTY]='Match|bool|yes|no'
)

# @global SSHD_TIPS — Sshd: two-line Russian tip per param (category: constant)
# @global SSHD_TIPS — Sshd: двухстрочная русская подсказка на параметр (категория: constant)
declare -gA SSHD_TIPS=(
    [Port]=$'Сетевой порт sshd; 22 — стандарт, смена порта убирает часть шума ботов из логов.\nНе защита, а снижение шума; настраивайте firewall отдельно.'
    [ListenAddress]=$'На каких адресах слушать; 0.0.0.0 — все интерфейсы.\nСузьте до внешнего адреса, если сервер смотрит в несколько сетей.'
    [AddressFamily]=$'Семейство адресов: any/inet/inet6.\ninet отключает IPv6 — меньше поверхности, если IPv6 не нужен.'
    [LoginGraceTime]=$'Сколько секунд даётся на аутентификацию.\nКороче — быстрее рвутся «висящие» попытки входа.'
    [PermitRootLogin]=$'Разрешить вход root напрямую по SSH.\nno — самое строгое, prohibit-password — только по ключу.'
    [PasswordAuthentication]=$'Вход по паролю.\nno оставляет только ключи и закрывает перебор паролей.'
    [PubkeyAuthentication]=$'Вход по SSH-ключам; основной безопасный способ.\nДержите yes, если не используете только внешние методы входа.'
    [PermitEmptyPasswords]=$'Пустые пароли.\nno обязательно: пустой пароль — фактически вход без пароля.'
    [KbdInteractiveAuthentication]=$'Интерактивная аутентификация (PAM, OTP).\nno закрывает лишний путь, если PAM-вход не нужен.'
    [AuthenticationMethods]=$'Какие методы обязательны и в каком порядке.\npublickey требует ключ; можно комбинировать publickey,password.'
    [MaxAuthTries]=$'Сколько попыток аутентификации на соединение.\n3-5 заметно замедляет перебор паролей.'
    [MaxSessions]=$'Сколько сессий в одном SSH-соединении.\nМеньше — меньше возможностей для злоупотребления мультиплексированием.'
    [AllowUsers]=$'Белый список пользователей (через запятую).\nВсё, что не указано, не сможет войти — самый прямой контроль доступа.'
    [AllowGroups]=$'Белый список групп (через запятую).\nУдобнее списка пользователей при большой команде.'
    [DenyUsers]=$'Чёрный список пользователей.\nИспользуйте, когда проще запретить несколько имён, чем перечислять разрешённые.'
    [DenyGroups]=$'Чёрный список групп.\nДополняет белые списки, если часть групп входить не должна.'
    [X11Forwarding]=$'Проброс X11-графики через SSH.\nno закрывает лишний канал; включайте только при реальной необходимости.'
    [AllowTcpForwarding]=$'Проброс TCP-портов через соединение.\nno мешает использовать сервер как туннель — частая причина ужесточения.'
    [AllowAgentForwarding]=$'Проброс ssh-agent.\nno не даёт чужому процессу на сервере использовать ваши ключи.'
    [GatewayPorts]=$'Разрешить проброс портов не только на localhost.\nno безопаснее: туннели не открываются наружу.'
    [PermitTunnel]=$'Разрешить tun/tap-туннели (VPN через SSH).\nno закрывает превращение SSH в VPN.'
    [SyslogFacility]=$'Категория syslog для логов sshd.\nAUTH/AUTHPRIV удобны для отдельного разбора ssh-событий.'
    [LogLevel]=$'Подробность логов.\nVERBOSE фиксирует отпечатки ключей и помогает разбирать входы.'
    [Ciphers]=$'Разрешённые шифры (через запятую).\nСписок короче — только современные AEAD-шифры.'
    [MACs]=$'Разрешённые коды аутентификации сообщений.\nETM-варианты (…-etm) предпочтительнее.'
    [KexAlgorithms]=$'Алгоритмы обмена ключами.\nОставьте современные (curve25519, group-exchange-sha256).'
    [HostKeyAlgorithms]=$'Алгоритмы подписи ключа хоста.\nПусто — значение по умолчанию; заполняйте только при требованиях политики.'
    [UsePAM]=$'Использовать PAM для сессий и аутентификации.\nyes нужен для большинства дистрибутивов и управления ограничениями.'
    [Subsystem]=$'Определение подсистемы sftp.\ninternal-sftp не требует отдельного бинарника и поддерживает chroot.'
    [ChrootDirectory]=$'Каталог-тюрьма внутри Match-блока.\n%h — домашний каталог; требует владельца root и прав 755.'
    [ForceCommand]=$'Принудительная команда внутри Match.\ninternal-sftp превращает доступ в чистый SFTP-доступ.'
    [PermitTTY]=$'Выдавать ли псевдотерминал внутри Match.\nno для SFTP-тюрьмы: терминал не нужен.'
)

# @description List catalog entries as TSV; optional section filter.
# @description Вывести записи каталога как TSV; опциональный фильтр по секции.
# @param $1 [optional] Section / Секция
# @stdout name<TAB>section<TAB>type<TAB>default<TAB>recommended
sshd::param_list() {
    local -r filter="${1:-}"
    local name section
    for name in "${SSHD_PARAM_ORDER[@]}"; do
        section="${SSHD_PARAMS[$name]%%|*}"
        if is::not_empty "${filter}" && [[ "${section}" != "${filter}" ]]; then
            continue
        fi
        printf '%s\t%s\n' "${name}" "${SSHD_PARAMS[$name]}"
    done
}

# @description Parameter type / Тип параметра
# @param $1 Param name / Имя параметра
# @stdout type / тип
sshd::param_type() {
    local -r name="${1:?param name required}"
    local -r meta="${SSHD_PARAMS[$name]:-}"
    is::empty "${meta}" && return "${LIB_ERROR_INVALID_ARGS}"
    local rest="${meta#*|}"
    printf '%s\n' "${rest%%|*}"
}

# @description Two-line Russian tip / Двухстрочная русская подсказка
# @param $1 Param name / Имя параметра
# @stdout tip / подсказка
sshd::param_desc() {
    local -r name="${1:?param name required}"
    local -r tip="${SSHD_TIPS[$name]:-}"
    is::empty "${tip}" && return "${LIB_ERROR_INVALID_ARGS}"
    printf '%s\n' "${tip}"
}

# @description Default value / Значение по умолчанию
# @param $1 Param name / Имя параметра
# @stdout value / значение
sshd::param_default() {
    local -r name="${1:?param name required}"
    local -r meta="${SSHD_PARAMS[$name]:-}"
    is::empty "${meta}" && return "${LIB_ERROR_INVALID_ARGS}"
    local rest="${meta#*|*|}"
    printf '%s\n' "${rest%%|*}"
}

# @description Recommended value / Рекомендуемое значение
# @param $1 Param name / Имя параметра
# @stdout value / значение
sshd::param_recommended() {
    local -r name="${1:?param name required}"
    local -r meta="${SSHD_PARAMS[$name]:-}"
    is::empty "${meta}" && return "${LIB_ERROR_INVALID_ARGS}"
    printf '%s\n' "${meta##*|}"
}

# @description Validate a value for a catalog parameter by its type.
# @description Проверить значение параметра каталога по его типу.
#   Rejects control characters and shell/space input: a value can never
#   inject a new directive into the rendered config.
#   Отклоняет управляющие символы и пробелы: значение не может внедрить
#   новую директиву в отрендеренный конфиг.
# @param $1 Param name / Имя параметра
# @param $2 Value / Значение
# @return E_SUCCESS or LIB_ERROR_INVALID_INPUT / LIB_ERROR_INVALID_ARGS
sshd::validate() {
    local -r name="${1:?param name required}" value="${2-}"
    local type
    type="$(sshd::param_type "${name}")" || return $?
    if [[ "${value}" == *$'\n'* || "${value}" == *$'\r'* || "${value}" == *$'\t'* ]]; then
        return "${LIB_ERROR_INVALID_INPUT}"
    fi
    local entry
    case "${type}" in
        bool)
            [[ "${value}" == "yes" || "${value}" == "no" ]] || return "${LIB_ERROR_INVALID_INPUT}"
            ;;
        int)
            [[ "${value}" =~ ^[0-9]+$ ]] || return "${LIB_ERROR_INVALID_INPUT}"
            ;;
        port)
            [[ "${value}" =~ ^[0-9]{1,5}$ ]] || return "${LIB_ERROR_INVALID_INPUT}"
            # 10#: без этого "08" парсился бы как восьмеричное число / without
            # it "08" would parse as octal and spam stderr
            local -i port_num=$(( 10#${value} ))
            (( port_num >= 1 && port_num <= 65535 )) || return "${LIB_ERROR_INVALID_INPUT}"
            ;;
        enum:*)
            # Запятая — разделитель вариантов, значение с ней матчилось бы как
            # подстрока всего списка / a comma is the variant separator, a value
            # containing one would match the whole list as a substring
            [[ "${value}" != *,* ]] || return "${LIB_ERROR_INVALID_INPUT}"
            [[ ",${type#enum:}," == *",${value},"* ]] || return "${LIB_ERROR_INVALID_INPUT}"
            ;;
        string)
            [[ -n "${value}" && "${value}" =~ ^[A-Za-z0-9._@%/-]+$ ]] || return "${LIB_ERROR_INVALID_INPUT}"
            ;;
        userlist|grouplist)
            local IFS=','
            local -a parts=()
            read -ra parts <<< "${value}"
            (( ${#parts[@]} > 0 )) || return "${LIB_ERROR_INVALID_INPUT}"
            for entry in "${parts[@]}"; do
                [[ "${entry}" =~ ^[A-Za-z_][A-Za-z0-9_.@-]*$ ]] || return "${LIB_ERROR_INVALID_INPUT}"
            done
            ;;
        csv)
            [[ -n "${value}" ]] || return "${LIB_ERROR_INVALID_INPUT}"
            local IFS=','
            local -a toks=()
            read -ra toks <<< "${value}"
            for entry in "${toks[@]}"; do
                [[ "${entry}" =~ ^[A-Za-z0-9@._+-]+$ ]] || return "${LIB_ERROR_INVALID_INPUT}"
            done
            ;;
        path)
            [[ "${value}" =~ ^/[^[:space:]]*$ || "${value}" == "internal-sftp" ]] || return "${LIB_ERROR_INVALID_INPUT}"
            ;;
        addr)
            # IPv4 с октетами ≤255; IPv6 — hex+двоеточия, минимум одно ":",
            # без ":::". Тонкая форма: финальный гейт всё равно sshd -t /
            # IPv4 with octets ≤255; IPv6 — hex+colons, at least one ":",
            # no ":::". Shape only: sshd -t is the final gate anyway
            if [[ "${value}" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
                local IFS='.'
                local -a octets=()
                read -ra octets <<< "${value}"
                # Без -i: присваивание "08" в integer-переменную само по себе
                # упало бы с octal-ошибкой / no -i: assigning "08" into an
                # integer variable would itself fail with an octal error
                local octet
                for octet in "${octets[@]}"; do
                    (( 10#${octet} <= 255 )) || return "${LIB_ERROR_INVALID_INPUT}"
                done
            elif [[ "${value}" != "*" && ( "${value}" != *:* || ! "${value}" =~ ^[0-9A-Fa-f:]+$ || "${value}" == *:::* ) ]]; then
                return "${LIB_ERROR_INVALID_INPUT}"
            fi
            ;;
        time)
            [[ "${value}" =~ ^[0-9]+[smhd]?$ ]] || return "${LIB_ERROR_INVALID_INPUT}"
            ;;
        *)
            return "${LIB_ERROR_INVALID_ARGS}"
            ;;
    esac
    return "${E_SUCCESS}"
}

# @description Hardening profile as name=value lines. strict extends basic,
# paranoid extends strict (later lines win on consume).
# @description Профиль ужесточения как строки name=value. strict включает
# basic, paranoid включает strict (при потреблении побеждают поздние строки).
# @param $1 Profile name / Имя профиля
# @stdout name=value lines / строки name=value
sshd::profile() {
    local -r name="${1:?profile name required}"
    case "${name}" in
        basic)
            cat <<'EOF'
PubkeyAuthentication=yes
PasswordAuthentication=no
PermitRootLogin=prohibit-password
X11Forwarding=no
MaxAuthTries=5
LoginGraceTime=60
EOF
            ;;
        strict)
            sshd::profile basic
            cat <<'EOF'
PermitRootLogin=no
AllowTcpForwarding=no
AllowAgentForwarding=no
PermitEmptyPasswords=no
KbdInteractiveAuthentication=no
MaxAuthTries=3
LoginGraceTime=30
LogLevel=VERBOSE
AuthenticationMethods=publickey
EOF
            ;;
        paranoid)
            sshd::profile strict
            cat <<'EOF'
AddressFamily=inet
GatewayPorts=no
PermitTunnel=no
MaxSessions=3
SyslogFacility=AUTHPRIV
Ciphers=chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr
MACs=hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-64-etm@openssh.com
KexAlgorithms=curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256
EOF
            ;;
        *)
            return "${LIB_ERROR_INVALID_ARGS}"
            ;;
    esac
}

# @description Render a config from stdin; parameters are ordered by the
# catalog, Match blocks are emitted verbatim and indented.
# @description Отрендерить конфиг из stdin; параметры упорядочены по
# каталогу, Match-блоки выводятся дословно с отступом.
#   Grammar / Грамматика:
#     name=value        main parameter / основной параметр
#     @match C          open Match block with criteria C / открыть Match-блок
#     <blank>           close the current Match block / закрыть Match-блок
# @stdin name=value lines / строки name=value
# @stdout config text / текст конфига
sshd::render() {
    local -A main=()
    local -a blocks=()
    local -i in_match=0
    local line
    while IFS= read -r line || is::not_empty "${line}"; do
        if [[ "${line}" == "@match "* ]]; then
            in_match=1
            blocks+=("Match ${line#@match }")
            continue
        fi
        if is::empty "${line}"; then
            if (( in_match )); then blocks+=(""); in_match=0; fi
            continue
        fi
        if (( in_match )); then
            blocks+=("    ${line/=/ }")
        else
            main["${line%%=*}"]="${line#*=}"
        fi
    done

    printf '%s\n' "# Managed by BS sshd wizard / Сгенерировано визардом BS"
    printf '%s\n' "${SSHD_MARK_BEGIN}"
    local name value section last_section=""
    for name in "${SSHD_PARAM_ORDER[@]}"; do
        value="${main[$name]:-}"
        is::empty "${value}" && continue
        section="${SSHD_PARAMS[$name]%%|*}"
        [[ "${section}" == "Match" ]] && continue
        if [[ "${section}" != "${last_section}" ]]; then
            printf '\n# --- %s ---\n' "${section}"
            last_section="${section}"
        fi
        if [[ "${name}" == "Subsystem" ]]; then
            printf 'Subsystem sftp %s\n' "${value}"
        else
            printf '%s %s\n' "${name}" "${value}"
        fi
    done
    if (( ${#blocks[@]} > 0 )); then
        printf '\n'
        local b
        for b in "${blocks[@]}"; do printf '%s\n' "${b}"; done
    fi
    printf '%s\n' "${SSHD_MARK_END}"
}

# @global BS_SSHD_DIR — Sshd: drop-in config dir (category: hook)
# @global BS_SSHD_DIR — Sshd: каталог drop-in конфигов (категория: hook)
declare -g BS_SSHD_DIR="/etc/ssh/sshd_config.d"
# @global BS_SSHD_MAIN — Sshd: main sshd config path (category: hook)
# @global BS_SSHD_MAIN — Sshd: путь к основному конфигу sshd (категория: hook)
declare -g BS_SSHD_MAIN="/etc/ssh/sshd_config"
# @global BS_SSHD_BIN — Sshd: sshd binary or test mock (category: hook)
# @global BS_SSHD_BIN — Sshd: бинарник sshd или мок для тестов (категория: hook)
declare -g BS_SSHD_BIN="sshd"
# @global BS_SSHD_SERVICE — Sshd: systemd service name (category: hook)
# @global BS_SSHD_SERVICE — Sshd: имя systemd-сервиса (категория: hook)
declare -g BS_SSHD_SERVICE="sshd"
# @global BS_SSHD_DRY_RUN — Sshd: 1 = no writes/reload (category: hook)
# @global BS_SSHD_DRY_RUN — Sshd: 1 = без записи и reload (категория: hook)
declare -g BS_SSHD_DRY_RUN=0
# @global BS_SSHD_DROPIN — Sshd: drop-in file name (category: hook)
# @global BS_SSHD_DROPIN — Sshd: имя drop-in файла (категория: hook)
declare -g BS_SSHD_DROPIN="99-bs.conf"

# @description Report missing optional runtime pieces (never fails).
# @description Сообщить об отсутствующих необязательных частях (не падает).
sshd::init() {
    is::command "${BS_SSHD_BIN}" || printf 'sshd не найден / not found: %s\n' "${BS_SSHD_BIN}" >&2
    is::dir "${BS_SSHD_DIR}" || printf 'каталог / dir отсутствует / missing: %s\n' "${BS_SSHD_DIR}" >&2
    return "${E_SUCCESS}"
}

# @description Validate a config file with `sshd -t`.
# @description Проверить конфиг через `sshd -t`.
# @param $1 Config file / Файл конфига
# @return sshd exit code; LIB_ERROR_DEPENDENCY_MISSING if sshd absent
sshd::test() {
    local -r file="${1:?config file required}"
    is::file "${file}" || return "${LIB_ERROR_FILE_NOT_FOUND}"
    if ! is::command "${BS_SSHD_BIN}"; then
        return "${LIB_ERROR_DEPENDENCY_MISSING}"
    fi
    "${BS_SSHD_BIN}" -t -f "${file}"
}

# @description Copy a file to `<file>.bak.<timestamp>`; print the backup path.
# @description Скопировать файл в `<file>.bak.<timestamp>`; вывести путь копии.
# @param $1 File / Файл
# @stdout Backup path / Путь копии
sshd::backup() {
    local -r file="${1:?file required}"
    is::file "${file}" || return "${LIB_ERROR_FILE_NOT_FOUND}"
    # Разрешение по секундам: два backup подряд не должны молча перезаписать
    # друг друга / second resolution: two backups in a row must not silently
    # overwrite each other
    local -r base="${file}.bak.$(date +%Y%m%d%H%M%S)"
    local dest="${base}"
    local -i n=1
    while [[ -e "${dest}" ]]; do
        dest="${base}.${n}"
        (( n += 1 ))
    done
    cp -a -- "${file}" "${dest}" || return "${LIB_ERROR_FILE_OPERATION}"
    printf '%s\n' "${dest}"
}

# @description Reload the sshd service (systemctl), honoring dry-run.
# @description Перезагрузить сервис sshd (systemctl), с учётом dry-run.
# @return 0 ok; LIB_ERROR_DEPENDENCY_MISSING if systemctl absent
sshd::reload() {
    if (( BS_SSHD_DRY_RUN == 1 )); then
        printf 'dry-run: systemctl reload %s\n' "${BS_SSHD_SERVICE}" >&2
        return "${E_SUCCESS}"
    fi
    is::command systemctl || return "${LIB_ERROR_DEPENDENCY_MISSING}"
    systemctl reload "${BS_SSHD_SERVICE}" >/dev/null 2>&1
}

# @description Install a rendered config as a drop-in: ensure dir, back up an
# existing target, validate, atomically replace, validate again, reload; on
# any validation failure restore the backup (or remove the new file).
# @description Установить конфиг как drop-in: каталог, backup существующего,
# валидация, атомарная замена, повторная валидация, reload; при провале —
# восстановить backup (или удалить новый файл).
# @param $1 Source file / Файл-источник
# @param $2 [optional] Target / Цель (default dir/dropin)
# @return E_SUCCESS / LIB_ERROR_*
sshd::install() {
    local -r src="${1:?source file required}"
    local -r target="${2:-${BS_SSHD_DIR}/${BS_SSHD_DROPIN}}"
    is::file "${src}" || return "${LIB_ERROR_FILE_NOT_FOUND}"
    if (( BS_SSHD_DRY_RUN == 1 )); then
        printf 'dry-run: install %s -> %s\n' "${src}" "${target}" >&2
        return "${E_SUCCESS}"
    fi
    is::command "${BS_SSHD_BIN}" || return "${LIB_ERROR_DEPENDENCY_MISSING}"
    local -r dir="$(dirname -- "${target}")"
    if ! is::dir "${dir}"; then
        mkdir -p -- "${dir}" 2>/dev/null || return "${LIB_ERROR_PERMISSION_DENIED}"
    fi
    is::writable "${dir}" || return "${LIB_ERROR_PERMISSION_DENIED}"

    local backup=""
    if is::file "${target}"; then
        backup="$(sshd::backup "${target}")" || return $?
    fi

    if ! sshd::test "${src}" >/dev/null 2>&1; then
        printf 'sshd -t отклонил / rejected: %s\n' "${src}" >&2
        return "${LIB_ERROR_INVALID_INPUT}"
    fi

    local tmp
    tmp="$(mktemp "${target}.tmp.XXXXXX")" || return "${LIB_ERROR_FILE_OPERATION}"
    if ! cp -f -- "${src}" "${tmp}" || ! mv -f -- "${tmp}" "${target}"; then
        rm -f -- "${tmp}"
        return "${LIB_ERROR_FILE_OPERATION}"
    fi

    if ! sshd::test "${target}" >/dev/null 2>&1; then
        printf 'sshd -t отклонил / rejected after install: %s\n' "${target}" >&2
        if is::not_empty "${backup}"; then
            cp -f -- "${backup}" "${target}"
        else
            rm -f -- "${target}"
        fi
        return "${LIB_ERROR_INVALID_INPUT}"
    fi

    sshd::reload || printf 'warning: reload %s failed / не удалось\n' "${BS_SSHD_SERVICE}" >&2
    return "${E_SUCCESS}"
}

# @description Restore the newest `<target>.bak.*` over the target.
# @description Восстановить новейший `<target>.bak.*` поверх цели.
# @param $1 Target / Цель
# @stdout Restored backup path / Путь восстановленной копии
sshd::revert() {
    local -r target="${1:?target required}"
    local -a baks=()
    local f
    # Сохраняем чужой nullglob: модуль не вправе менять опции вызывающего шелла
    # Save the caller's nullglob: a module must not change the caller's options
    local nullglob_was=0
    shopt -q nullglob && nullglob_was=1
    shopt -s nullglob
    for f in "${target}".bak.*; do baks+=("${f}"); done
    (( nullglob_was == 1 )) || shopt -u nullglob
    if (( ${#baks[@]} == 0 )); then
        return "${LIB_ERROR_FILE_NOT_FOUND}"
    fi
    local latest="${baks[0]}"
    for f in "${baks[@]}"; do
        [[ "${f}" > "${latest}" ]] && latest="${f}"
    done
    cp -f -- "${latest}" "${target}" || return "${LIB_ERROR_FILE_OPERATION}"
    printf '%s\n' "${latest}"
}

# @description Install a rendered config as a managed block inside the main
# config: strip any previous block between the markers, append the new one,
# validate with sshd -t, and roll back on failure.
# @description Установить конфиг управляемым блоком в основной конфиг:
# удалить прежний блок между маркерами, добавить новый, проверить sshd -t и
# откатиться при неудаче.
# @param $1 Source file (with markers) / Файл-источник (с маркерами)
# @return E_SUCCESS / LIB_ERROR_*
sshd::install_main() {
    local -r src="${1:?source file required}"
    is::file "${src}" || return "${LIB_ERROR_FILE_NOT_FOUND}"
    if (( BS_SSHD_DRY_RUN == 1 )); then
        printf 'dry-run: install main block %s -> %s\n' "${src}" "${BS_SSHD_MAIN}" >&2
        return "${E_SUCCESS}"
    fi
    is::command "${BS_SSHD_BIN}" || return "${LIB_ERROR_DEPENDENCY_MISSING}"
    is::writable "$(dirname -- "${BS_SSHD_MAIN}")" || return "${LIB_ERROR_PERMISSION_DENIED}"
    local backup=""
    if is::file "${BS_SSHD_MAIN}"; then
        backup="$(sshd::backup "${BS_SSHD_MAIN}")" || return $?
    fi
    local tmp
    tmp="$(mktemp "${BS_SSHD_MAIN}.bs.XXXXXX")" || return "${LIB_ERROR_FILE_OPERATION}"
    if is::file "${BS_SSHD_MAIN}"; then
        # awk должен отработать: молчаливый провал чтения дал бы конфиг только
        # из нашего блока / awk must succeed: a silent read failure would leave
        # a config with only our managed block
        if ! awk -v b="${SSHD_MARK_BEGIN}" -v e="${SSHD_MARK_END}" '
            $0 == b {skip=1; next}
            $0 == e {skip=0; next}
            !skip   {print}
        ' "${BS_SSHD_MAIN}" > "${tmp}" 2>/dev/null; then
            rm -f -- "${tmp}"
            return "${LIB_ERROR_FILE_OPERATION}"
        fi
    fi
    printf '\n' >> "${tmp}"
    cat -- "${src}" >> "${tmp}"
    if ! sshd::test "${tmp}" >/dev/null 2>&1; then
        rm -f -- "${tmp}"
        return "${LIB_ERROR_INVALID_INPUT}"
    fi
    if ! mv -f -- "${tmp}" "${BS_SSHD_MAIN}"; then
        rm -f -- "${tmp}"
        return "${LIB_ERROR_FILE_OPERATION}"
    fi
    sshd::reload || printf 'warning: reload %s failed / не удалось\n' "${BS_SSHD_SERVICE}" >&2
    return "${E_SUCCESS}"
}
