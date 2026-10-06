#!/usr/bin/env bs
# shellcheck shell=bash
# lib/system/sshd.sh — server-side sshd config: parameter catalog with Russian
# tips, validation, hardening profiles, rendering, safe install with rollback
# lib/system/sshd.sh — серверный конфиг sshd: каталог параметров с русскими
# подсказками, валидация, профили, рендер, безопасная установка с откатом
#
# @depends core/lang, core/const
# @tier core

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
    [AuthenticationMethods]='Authentication|string||publickey'
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
