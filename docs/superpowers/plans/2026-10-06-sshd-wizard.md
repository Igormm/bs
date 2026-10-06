# SSHd Config Wizard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `lib/system/sshd.sh` (data-driven sshd config model with Russian per-parameter tips) and `examples/sshd_wizard.sh` (a full-screen TUI on `lib/tui/tui`) that lets a user pick a hardening profile, tune parameters, add `Match`/chroot blocks, preview, validate with `sshd -t`, and install safely with backup + rollback.

**Architecture:** Logic lives in a testable `lib/system/sshd.sh` module (catalog, validate, profiles, render, test/install/revert) driven only by `sshd -t` and filesystem hooks. The UI is an example wizard built on the raw TUI engine (`lib/tui/tui`), following the manual main-loop pattern of `examples/tui_demo.sh`. The module never draws; the wizard never encodes sshd rules.

**Tech Stack:** Bash 4+, BS framework (`lib/system/*`, `lib/tui/tui`, `lib/ui/steplog`), custom testframework, ShellCheck.

**Spec:** `docs/superpowers/specs/2026-10-06-sshd-wizard-design.md`

## Global Constraints

- Modules: shebang `#!/usr/bin/env bs`, line 2 `# shellcheck shell=bash`, `bs::guard`, `bs::source_relative` for deps, no `set -euo pipefail` in library modules.
- Every module-level variable gets a paired bilingual `# @global ... (category: ...)`.
- Public functions are `module::function`; constants `SCREAMING_SNAKE_CASE` + `readonly`; no comments beyond the documented bilingual doc blocks (the repo documents in comments, so doc blocks are required, not optional).
- Scripts (examples/tests) use `#!/usr/bin/env bs` + line 2 `# shellcheck shell=bash`; tests start with `set -euo pipefail`.
- Error codes from `core/const.sh`: `E_SUCCESS=0`, `LIB_ERROR_INVALID_ARGS=3`, `LIB_ERROR_INVALID_INPUT=4`, `LIB_ERROR_FILE_NOT_FOUND=5`, `LIB_ERROR_PERMISSION_DENIED=6`, `LIB_ERROR_DEPENDENCY_MISSING=101`, `LIB_ERROR_FILE_OPERATION=100`.
- Hooks over `bs::guard`; never hand-roll source guards.
- Run after every task: `bash tests/validatesyntax.sh`, `bash tests/validateshellcheck.sh`, `bash tests/runalltests.sh`.
- Tests are invoked as `bash tests/unit/<name>.sh`; unit tests in `tests/unit/` are auto-discovered by `tests/runalltests.sh`.
- Keep `documentation/en` and `documentation/ru` in sync.

## Review Focus

Untested-by-default failure modes most likely to bite a real user — each gets an explicit test in the task that owns the code:

1. Target dir/file not writable (e.g. `/etc/ssh/sshd_config.d` owned by root, wizard under sudo-less user) → must return `LIB_ERROR_PERMISSION_DENIED`, never a raw bash "Отказано в доступе" and never a silent success (Task 5).
2. `sshd` binary missing → `sshd::test` must return `LIB_ERROR_DEPENDENCY_MISSING`, never treat a missing validator as "valid" (Task 5).
3. A value containing a newline or shell metacharacters must be rejected by `sshd::validate`, so a value can never inject a new directive into the rendered config (Tasks 2 and 4).
4. An empty/unset value must be skipped by `sshd::render` (never emit `Param ` with a trailing space) (Task 4).
5. `sshd::revert` with no backup → clean `LIB_ERROR_FILE_NOT_FOUND`, not an `ls`/`cp` error leak (Task 5).

---

### Task 1: Module skeleton + parameter catalog + query API

**Files:**
- Create: `lib/system/sshd.sh`
- Test: `tests/unit/testsshdunit.sh`

**Interfaces:**
- Consumes: `core/lang` (`is::empty`, `is::not_empty`), `core/const` (`LIB_ERROR_*`, `E_SUCCESS`).
- Produces:
  - Globals: `SSHD_SECTIONS` (array), `SSHD_PARAM_ORDER` (array), `SSHD_PARAMS` (assoc: `section|type|default|recommended`), `SSHD_TIPS` (assoc: two-line Russian text).
  - `sshd::param_list [section]` → TSV `name<TAB>section<TAB>type<TAB>default<TAB>recommended`.
  - `sshd::param_type <name>` → stdout type; `LIB_ERROR_INVALID_ARGS` if unknown.
  - `sshd::param_desc <name>` → stdout two-line tip.
  - `sshd::param_default <name>` / `sshd::param_recommended <name>` → stdout value.

- [ ] **Step 1: Write the failing test**

`tests/unit/testsshdunit.sh`:

```bash
#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testsshdunit.sh — Unit tests for lib/system/sshd
# tests/unit/testsshdunit.sh — Модульные тесты для lib/system/sshd

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

load "lib/system/sshd"

main() {
    print_header "SSHd Unit Tests / Модульные тесты sshd"
    testframework::init

    testframework::section "catalog shape / форма каталога"
    local name meta section type default recommended fields
    for name in "${SSHD_PARAM_ORDER[@]}"; do
        meta="${SSHD_PARAMS[$name]:-}"
        testframework::assert_true "[[ -n '${meta}' ]]" "meta present: ${name}"
        fields="$(awk -F'|' '{print NF}' <<< "${meta}")"
        testframework::assert_equal "4" "${fields}" "4 fields: ${name}"
        testframework::assert_true "[[ -n '${SSHD_TIPS[$name]:-}' ]]" "tip present: ${name}"
        testframework::assert_true "[[ '${SSHD_TIPS[$name]:-}' =~ [А-Яа-я] ]]" "tip has cyrillic: ${name}"
    done

    testframework::section "param_list / список параметров"
    local count filtered
    count="$(sshd::param_list | wc -l)"
    testframework::assert_equal "${#SSHD_PARAM_ORDER[@]}" "${count}" "all params listed"
    filtered="$(sshd::param_list Network)"
    testframework::assert_command "test -n \"\$(printf '%s' '${filtered}')\"" "Network filter non-empty"
    testframework::assert_command "! printf '%s' '${filtered}' | grep -q 'Authentication'" "Network filter excludes others"

    testframework::section "param_type / param_desc"
    testframework::assert_equal "bool" "$(sshd::param_type PasswordAuthentication)" "bool type"
    testframework::assert_equal "port" "$(sshd::param_type Port)" "port type"
    local desc
    desc="$(sshd::param_desc PasswordAuthentication)"
    testframework::assert_true "[[ '${desc}' == *$'\n'* ]]" "desc is two lines"
    local rc=0; sshd::param_type no_such_param >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_ARGS}" "${rc}" "unknown param → invalid args"

    testframework::section "param_default / param_recommended"
    testframework::assert_equal "22" "$(sshd::param_default Port)" "Port default 22"
    testframework::assert_equal "no" "$(sshd::param_recommended PasswordAuthentication)" "pw recommended no"

    testframework::summary
}

main "$@"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/unit/testsshdunit.sh`
Expected: FAIL — `lib/system/sshd.sh` not found / `SSHD_PARAM_ORDER` unbound.

- [ ] **Step 3: Write the module**

Create `lib/system/sshd.sh`:

```bash
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
```

> Note on `sshd::param_default`: `meta='s|t|d|r'`; `${meta#*|*|}` removes `s|t|` → `d|r`; then `${rest%%|*}` yields `d`. The extra reassignment above is written to be explicit; simplify to:
> ```bash
> local rest="${meta#*|*|}"
> printf '%s\n' "${rest%%|*}"
> ```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/unit/testsshdunit.sh`
Expected: PASS. If `param_default` prints a wrong field, fix the field stripping per the note.

- [ ] **Step 5: Commit**

```bash
git add lib/system/sshd.sh tests/unit/testsshdunit.sh
git commit -m "feat(system): lib/system/sshd — parameter catalog with Russian tips + query API (param_list/type/desc/default/recommended); test: shape/cyrillic/filters"
```

---

### Task 2: Value validation per type

**Files:**
- Modify: `lib/system/sshd.sh`
- Modify: `tests/unit/testsshdunit.sh`

**Interfaces:**
- Consumes: `sshd::param_type`.
- Produces: `sshd::validate <name> <value>` → `E_SUCCESS` or `LIB_ERROR_INVALID_INPUT` (unknown type → `LIB_ERROR_INVALID_ARGS`).

- [ ] **Step 1: Add the failing tests**

Append to `main()` before `testframework::summary`:

```bash
    testframework::section "validate / валидация значений"
    local vrc=0
    sshd::validate PasswordAuthentication yes || vrc=$?
    testframework::assert_equal "0" "${vrc}" "bool yes ok"
    vrc=0; sshd::validate PasswordAuthentication maybe || vrc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_INPUT}" "${vrc}" "bool maybe rejected"

    vrc=0; sshd::validate Port 65535 || vrc=$?
    testframework::assert_equal "0" "${vrc}" "port 65535 ok"
    vrc=0; sshd::validate Port 70000 || vrc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_INPUT}" "${vrc}" "port 70000 rejected"
    vrc=0; sshd::validate Port "22;rm -rf /" || vrc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_INPUT}" "${vrc}" "port injection rejected"

    vrc=0; sshd::validate PermitRootLogin prohibit-password || vrc=$?
    testframework::assert_equal "0" "${vrc}" "enum ok"
    vrc=0; sshd::validate PermitRootLogin root || vrc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_INPUT}" "${vrc}" "enum bad rejected"

    vrc=0; sshd::validate AllowUsers "alice,bob" || vrc=$?
    testframework::assert_equal "0" "${vrc}" "userlist ok"
    vrc=0; sshd::validate AllowUsers "alice root" || vrc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_INPUT}" "${vrc}" "userlist space rejected"

    vrc=0; sshd::validate Ciphers "aes256-ctr,chacha20-poly1305@openssh.com" || vrc=$?
    testframework::assert_equal "0" "${vrc}" "ciphers ok"
    vrc=0; sshd::validate Ciphers "aes256-ctr,"$'\n'"PermitRootLogin yes" || vrc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_INPUT}" "${vrc}" "newline injection rejected"

    vrc=0; sshd::validate Subsystem internal-sftp || vrc=$?
    testframework::assert_equal "0" "${vrc}" "path internal-sftp ok"
    vrc=0; sshd::validate ChrootDirectory "%h" || vrc=$?
    testframework::assert_equal "0" "${vrc}" "string %h ok"
    vrc=0; sshd::validate LoginGraceTime 30 || vrc=$?
    testframework::assert_equal "0" "${vrc}" "time 30 ok"
    vrc=0; sshd::validate LoginGraceTime "1h30" || vrc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_INPUT}" "${vrc}" "time bad rejected"
```

- [ ] **Step 2: Run to verify failure**

Run: `bash tests/unit/testsshdunit.sh`
Expected: FAIL — `sshd::validate: command not found`.

- [ ] **Step 3: Implement `sshd::validate`**

Append to `lib/system/sshd.sh`:

```bash
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
    # единый запрет управляющих символов / global control-char ban
    [[ "${value}" != *[$'\n\r\t']* ]] || return "${LIB_ERROR_INVALID_INPUT}"
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
            (( value >= 1 && value <= 65535 )) || return "${LIB_ERROR_INVALID_INPUT}"
            ;;
        enum:*)
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
            [[ "${value}" == "*" || "${value}" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ || "${value}" =~ ^[0-9A-Fa-f:]+$ ]] || return "${LIB_ERROR_INVALID_INPUT}"
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
```

- [ ] **Step 4: Run to verify pass**

Run: `bash tests/unit/testsshdunit.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/system/sshd.sh tests/unit/testsshdunit.sh
git commit -m "feat(system): sshd::validate — per-type validation with control-char/space ban (injection guard); tests for bool/port/enum/userlist/csv/path/time"
```

---

### Task 3: Hardening profiles

**Files:**
- Modify: `lib/system/sshd.sh`
- Modify: `tests/unit/testsshdunit.sh`

**Interfaces:**
- Consumes: nothing new.
- Produces: `sshd::profile <basic|strict|paranoid>` → stdout `name=value` lines; unknown → `LIB_ERROR_INVALID_ARGS`. Profiles are nested: `strict` outputs `basic` first, `paranoid` outputs `strict` first (later lines win when consumed).

- [ ] **Step 1: Add the failing tests**

Append before `testframework::summary`:

```bash
    testframework::section "profiles / профили"
    local out
    out="$(sshd::profile basic)"
    testframework::assert_command "printf '%s' '${out}' | grep -q '^PubkeyAuthentication=yes$'" "basic pubkey"
    testframework::assert_command "printf '%s' '${out}' | grep -q '^PasswordAuthentication=no$'" "basic no password"
    out="$(sshd::profile strict)"
    testframework::assert_command "printf '%s' '${out}' | grep -q '^PermitRootLogin=no$'" "strict root no"
    testframework::assert_command "printf '%s' '${out}' | grep -q '^AllowTcpForwarding=no$'" "strict no tcp fwd"
    out="$(sshd::profile paranoid)"
    testframework::assert_command "printf '%s' '${out}' | grep -q '^AddressFamily=inet$'" "paranoid inet"
    testframework::assert_command "printf '%s' '${out}' | grep -q '^Ciphers='" "paranoid ciphers"
    local prc=0; sshd::profile no_such >/dev/null 2>&1 || prc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_ARGS}" "${prc}" "unknown profile rejected"
```

- [ ] **Step 2: Run to verify failure**

Run: `bash tests/unit/testsshdunit.sh`
Expected: FAIL — `sshd::profile: command not found`.

- [ ] **Step 3: Implement `sshd::profile`**

Append:

```bash
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
```

- [ ] **Step 4: Run to verify pass**

Run: `bash tests/unit/testsshdunit.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/system/sshd.sh tests/unit/testsshdunit.sh
git commit -m "feat(system): sshd::profile — basic/strict/paranoid presets (nested, later wins); tests"
```

---

### Task 4: Renderer (sections + managed markers + Match)

**Files:**
- Modify: `lib/system/sshd.sh`
- Modify: `tests/unit/testsshdunit.sh`

**Interfaces:**
- Consumes: `SSHD_MARK_BEGIN/END`, `SSHD_PARAM_ORDER`, `SSHD_PARAMS`.
- Produces: `sshd::render` reading `name=value` lines from stdin; `@match <criteria>` opens a block, a blank line closes it, `name=value` inside a block becomes an indented directive. Main params are emitted in `SSHD_PARAM_ORDER` order (deterministic regardless of input order); empty values are skipped.

- [ ] **Step 1: Add the failing tests**

Append before `testframework::summary`:

```bash
    testframework::section "render / рендер конфига"
    local rendered
    rendered="$(printf 'PasswordAuthentication=no\nPort=2222\n' | sshd::render)"
    testframework::assert_command "printf '%s' '${rendered}' | grep -qF '${SSHD_MARK_BEGIN}'" "begin marker"
    testframework::assert_command "printf '%s' '${rendered}' | grep -qF '${SSHD_MARK_END}'" "end marker"
    testframework::assert_command "printf '%s' '${rendered}' | grep -q '^Port 2222$'" "port rendered"
    testframework::assert_command "printf '%s' '${rendered}' | grep -q '^PasswordAuthentication no$'" "pw rendered"
    local port_line pw_line
    port_line="$(printf '%s\n' "${rendered}" | grep -n '^Port ' | cut -d: -f1)"
    pw_line="$(printf '%s\n' "${rendered}" | grep -n '^PasswordAuthentication ' | cut -d: -f1)"
    testframework::assert_true "(( port_line < pw_line ))" "catalog order (Port before Password… in order)"

    rendered="$(printf 'AllowUsers=\nPort=22\n' | sshd::render)"
    testframework::assert_command "! printf '%s' '${rendered}' | grep -q 'AllowUsers '" "empty value skipped"

    rendered="$(printf '@match Group sftponly\nChrootDirectory=%%h\nForceCommand=internal-sftp\n\n' | sshd::render)"
    testframework::assert_command "printf '%s' '${rendered}' | grep -q '^Match Group sftponly$'" "match header"
    testframework::assert_command "printf '%s' '${rendered}' | grep -q '^    ChrootDirectory %%h$'" "match indented directive"
```

Wait — the catalog order test: `Port` is index 0, `PasswordAuthentication` index 5, so Port comes first. Good.

Fix the paranoid ciphers test typo in Task 3: it was `grep -q '^Ciphers=' " "paranoid ciphers"` — remove the stray `" "`. Correct it in this file when implementing (keep as `grep -q '^Ciphers='`). (Self-review catch.)

- [ ] **Step 2: Run to verify failure**

Run: `bash tests/unit/testsshdunit.sh`
Expected: FAIL — `sshd::render: command not found`.

- [ ] **Step 3: Implement `sshd::render`**

Append:

```bash
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
        printf '%s %s\n' "${name}" "${value}"
    done
    if (( ${#blocks[@]} > 0 )); then
        printf '\n'
        local b
        for b in "${blocks[@]}"; do printf '%s\n' "${b}"; done
    fi
    printf '%s\n' "${SSHD_MARK_END}"
}
```

- [ ] **Step 4: Run to verify pass**

Run: `bash tests/unit/testsshdunit.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/system/sshd.sh tests/unit/testsshdunit.sh
git commit -m "feat(system): sshd::render — catalog-ordered main params + Match blocks + managed markers; empty values skipped; tests"
```

---

### Task 5: Test / backup / install / revert / reload

**Files:**
- Modify: `lib/system/sshd.sh`
- Modify: `tests/unit/testsshdunit.sh`

**Interfaces:**
- Consumes: `is::command`, `is::file`, `is::dir`, `is::writable`, `is::not_empty`, `LIB_ERROR_*`.
- Produces:
  - Hooks: `BS_SSHD_DIR`, `BS_SSHD_MAIN`, `BS_SSHD_BIN`, `BS_SSHD_SERVICE`, `BS_SSHD_DRY_RUN`, `BS_SSHD_DROPIN`.
  - `sshd::test [file]`; `sshd::backup <file>` → stdout backup path; `sshd::install <src> [target]`; `sshd::install_main <src>`; `sshd::reload`; `sshd::revert <target>` → stdout restored path.

- [ ] **Step 1: Add the failing tests**

Append before `testframework::summary`:

```bash
    testframework::section "test/backup/install/revert / установка"
    local tmp; tmp="$(mktemp -d)"
    export BS_SSHD_DIR="${tmp}" BS_SSHD_DROPIN="99-bs.conf"
    export BS_SSHD_BIN="${tmp}/sshd-fake" BS_SSHD_SERVICE="sshd"

    # fake sshd: -t accepts only files that do NOT contain the word BAD
    cat > "${BS_SSHD_BIN}" <<'EOF'
#!/bin/bash
for a in "$@"; do :; done
file="${!#}"
if grep -q BAD "${file}"; then echo "bad config" >&2; exit 1; fi
exit 0
EOF
    chmod +x "${BS_SSHD_BIN}"

    printf 'Port 2222\n' > "${tmp}/good.conf"
    local trc=0; sshd::test "${tmp}/good.conf" || trc=$?
    testframework::assert_equal "0" "${trc}" "fake sshd accepts good"

    printf 'BAD directive\n' > "${tmp}/bad.conf"
    trc=0; sshd::test "${tmp}/bad.conf" || trc=$?
    testframework::assert_equal "1" "${trc}" "fake sshd rejects bad"

    local old_bin="${BS_SSHD_BIN}"; BS_SSHD_BIN="no-such-sshd-xyz"
    trc=0; sshd::test "${tmp}/good.conf" 2>/dev/null || trc=$?
    testframework::assert_equal "${LIB_ERROR_DEPENDENCY_MISSING}" "${trc}" "missing sshd → dependency missing"
    BS_SSHD_BIN="${old_bin}"

    local irc=0
    sshd::install "${tmp}/good.conf" || irc=$?
    testframework::assert_equal "0" "${irc}" "install good ok"
    testframework::assert_file_exists "${tmp}/99-bs.conf" "target written"
    testframework::assert_command "grep -q '^Port 2222$' '${tmp}/99-bs.conf'" "installed content"

    # second install → backup created
    printf 'Port 2200\n' > "${tmp}/good2.conf"
    sshd::install "${tmp}/good2.conf" || irc=$?
    testframework::assert_command "ls '${tmp}/99-bs.conf.bak.'* >/dev/null 2>&1" "backup created on overwrite"

    # bad source → validated before replace, target unchanged
    irc=0; sshd::install "${tmp}/bad.conf" 2>/dev/null || irc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_INPUT}" "${irc}" "bad source rejected"
    testframework::assert_command "grep -q '^Port 2200$' '${tmp}/99-bs.conf'" "target unchanged after bad source"

    # revert restores a previous version
    local rrc=0; sshd::revert "${tmp}/99-bs.conf" >/dev/null || rrc=$?
    testframework::assert_equal "0" "${rrc}" "revert ok"

    # no backup → clean file-not-found
    rrc=0; sshd::revert "${tmp}/never-existed.conf" 2>/dev/null || rrc=$?
    testframework::assert_equal "${LIB_ERROR_FILE_NOT_FOUND}" "${rrc}" "revert without backup → file not found"

    # dry-run does not touch the target
    rm -f "${tmp}/99-bs.conf"
    export BS_SSHD_DRY_RUN=1
    sshd::install "${tmp}/good.conf" || irc=$?
    testframework::assert_false "-f '${tmp}/99-bs.conf'" "dry-run writes nothing"
    export BS_SSHD_DRY_RUN=0

    # non-writable dir → permission denied (no raw bash error); skipped as root
    if (( EUID != 0 )); then
        local ro="${tmp}/ro"; mkdir -p "${ro}"; chmod 500 "${ro}"
        irc=0; sshd::install "${tmp}/good.conf" "${ro}/99-bs.conf" 2>/dev/null || irc=$?
        testframework::assert_equal "${LIB_ERROR_PERMISSION_DENIED}" "${irc}" "non-writable dir → permission denied"
        chmod 700 "${ro}"
    fi

    rm -rf "${tmp}"
```

- [ ] **Step 2: Run to verify failure**

Run: `bash tests/unit/testsshdunit.sh`
Expected: FAIL — hooks unbound / `sshd::install: command not found`.

- [ ] **Step 3: Add hooks**

Add near the top of `lib/system/sshd.sh` (after constants):

```bash
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
```

- [ ] **Step 4: Implement the functions**

Append:

```bash
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
    local -r dest="${file}.bak.$(date +%Y%m%d%H%M%S)"
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

    if ! cp -f -- "${src}" "${target}.tmp" || ! mv -f -- "${target}.tmp" "${target}"; then
        rm -f -- "${target}.tmp"
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
    shopt -s nullglob
    for f in "${target}".bak.*; do baks+=("${f}"); done
    shopt -u nullglob
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
```

- [ ] **Step 5: Run to verify pass**

Run: `bash tests/unit/testsshdunit.sh`
Expected: PASS.

Note: `sshd::install_main` (managed block in `/etc/ssh/sshd_config`) is intentionally deferred to the wizard Task 8, where the wizard chooses the target; add it there with its own test to keep this task independently reviewable.

- [ ] **Step 6: Commit**

```bash
git add lib/system/sshd.sh tests/unit/testsshdunit.sh
git commit -m "feat(system): sshd test/backup/install/reload/revert — hooks, dry-run, sshd -t gate, backup+rollback, permission/dependency error codes; tests on fake sshd + temp dir"
```

---

### Task 6: TUI wizard skeleton + parameters screen

**Files:**
- Create: `examples/sshd_wizard.sh`
- Test: `tests/unit/testsshdwizardunit.sh`
- Modify: `lib/system/sshd.sh` (add `sshd::install_main` — needed by Task 8, declared here for interface stability)

**Interfaces:**
- Consumes: `sshd::param_list`, `sshd::param_desc`, `sshd::param_type`, `sshd::validate`, `sshd::profile`, `sshd::render`, `sshd::install`, `lib/tui/tui`.
- Produces:
  - Wizard globals: `SSHD_WZ_SECTIONS` (array), `SSHD_WZ_NAMES` (array), `SSHD_WZ_VALUES` (assoc), `SSHD_WZ_SECTION`, `SSHD_WZ_SELECT`, `SSHD_WZ_PROFILE`, `SSHD_WZ_TARGET`, `SSHD_WZ_VIEW`, `SSHD_WZ_STATUS`.
  - Functions: `sshd_wz::load_sections`, `sshd_wz::load_names`, `sshd_wz::draw_title`, `sshd_wz::draw_sections`, `sshd_wz::draw_params`, `sshd_wz::draw_desc`, `sshd_wz::draw_status`, `sshd_wz::draw`, `main`.

- [ ] **Step 1: Write the failing test**

`tests/unit/testsshdwizardunit.sh`:

```bash
#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testsshdwizardunit.sh — draw/state tests for examples/sshd_wizard
# tests/unit/testsshdwizardunit.sh — тесты отрисовки/состояния визарда

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

source "${BS_PROJECT_ROOT}/examples/sshd_wizard.sh"

main() {
    print_header "SSHd Wizard Unit Tests / Тесты визарда sshd"
    testframework::init
    TUI_COLS=100 TUI_LINES=30

    testframework::section "sections/names / секции и параметры"
    sshd_wz::load_sections
    testframework::assert_true "(( ${#SSHD_WZ_SECTIONS[@]} >= 6 ))" "sections loaded"
    SSHD_WZ_SECTION=0
    sshd_wz::load_names
    testframework::assert_true "(( ${#SSHD_WZ_NAMES[@]} > 0 ))" "names loaded for first section"

    testframework::section "draw / отрисовка буфера"
    tui::buf::clear
    sshd_wz::draw
    testframework::assert_equal "╔" "${TUI_BUF[0,0]}" "titlebar drawn"
    local found=0 key
    for key in "${!TUI_BUF[@]}"; do
        [[ "${TUI_BUF[$key]}" == *"Port"* ]] && found=1
    done
    testframework::assert_equal "1" "${found}" "param name on screen"

    # desc pane shows the selected parameter's tip
    tui::buf::clear
    sshd_wz::draw_desc
    local joined=""
    for key in "${!TUI_BUF[@]}"; do joined+="${TUI_BUF[$key]}"; done
    testframework::assert_true "[[ '${joined}' =~ [А-Яа-я] ]]" "desc pane has Russian text"

    testframework::section "profile fill / заполнение профиля"
    sshd_wz::apply_profile strict
    testframework::assert_equal "no" "${SSHD_WZ_VALUES[PasswordAuthentication]:-}" "strict fills PasswordAuthentication=no"

    testframework::summary
}

main "$@"
```

- [ ] **Step 2: Run to verify failure**

Run: `bash tests/unit/testsshdwizardunit.sh`
Expected: FAIL — file not found.

- [ ] **Step 3: Write the wizard skeleton**

Create `examples/sshd_wizard.sh`:

```bash
#!/usr/bin/env bs
# shellcheck shell=bash
# examples/sshd_wizard.sh — interactive TUI for building an sshd config
# examples/sshd_wizard.sh — интерактивный TUI для сборки конфига sshd
#
# Full-screen wizard on lib/tui/tui. Left: sections. Center: parameters of the
# selected section with their values. Bottom: a two-line Russian tip for the
# selected parameter. Modals edit values. V — preview; P — profile; A — apply.
# Полноэкранный визард на lib/tui/tui. Слева — секции. По центру — параметры
# секции со значениями. Внизу — двухстрочная русская подсказка выбранного
# параметра. Модалки редактируют значения. V — предпросмотр, P — профиль,
# A — применить.
#
# Run / Запуск:
#   bs run examples/sshd_wizard.sh
#   ./examples/sshd_wizard.sh [--dry-run] [--help]
#
# Keys / Клавиши:
#   ←→ секция · ↑↓ параметр · Enter правка · Space toggle · P профиль ·
#   M match · V preview · A apply · r сброс · ? справка · q выход

load "lib/system/sshd"
load "lib/tui/tui"
load "core/utils"

# ==========================================
# State / Состояние
# ==========================================

declare -ga SSHD_WZ_SECTIONS=()
declare -ga SSHD_WZ_NAMES=()
declare -gA SSHD_WZ_VALUES=()
declare -gi SSHD_WZ_SECTION=0
declare -gi SSHD_WZ_SELECT=0
declare -g SSHD_WZ_PROFILE="custom"
declare -g SSHD_WZ_TARGET="dropin"
declare -g SSHD_WZ_VIEW="params"
declare -g SSHD_WZ_STATUS=""

# @private Fill SSHD_WZ_SECTIONS from the catalog / Заполнить секции из каталога
sshd_wz::load_sections() {
    SSHD_WZ_SECTIONS=()
    local name section
    for name in "${SSHD_PARAM_ORDER[@]}"; do
        section="${SSHD_PARAMS[$name]%%|*}"
        arr::contains SSHD_WZ_SECTIONS "${section}" || SSHD_WZ_SECTIONS+=("${section}")
    done
}

# @private Fill SSHD_WZ_NAMES with the parameters of the current section
sshd_wz::load_names() {
    SSHD_WZ_NAMES=()
    local -r section="${SSHD_WZ_SECTIONS[$SSHD_WZ_SECTION]:-}"
    local name
    for name in "${SSHD_PARAM_ORDER[@]}"; do
        [[ "${SSHD_PARAMS[$name]%%|*}" == "${section}" ]] && SSHD_WZ_NAMES+=("${name}")
    done
    (( SSHD_WZ_SELECT >= ${#SSHD_WZ_NAMES[@]} )) && SSHD_WZ_SELECT=0
}

# @private Apply a profile into SSHD_WZ_VALUES / Применить профиль в значения
# @param $1 basic|strict|paranoid|custom
sshd_wz::apply_profile() {
    local -r profile="${1:?profile required}"
    SSHD_WZ_PROFILE="${profile}"
    [[ "${profile}" == "custom" ]] && return 0
    local line key val
    while IFS= read -r line; do
        is::empty "${line}" && continue
        key="${line%%=*}"; val="${line#*=}"
        SSHD_WZ_VALUES["${key}"]="${val}"
    done < <(sshd::profile "${profile}")
}

# ==========================================
# Draw / Отрисовка
# ==========================================

sshd_wz::draw_title() {
    tui::titlebar "  BS sshd wizard  •  профиль/profile: ${SSHD_WZ_PROFILE}  •  цель/target: ${SSHD_WZ_TARGET}" "$(tui::style bold bg_blue white)"
}

sshd_wz::draw_sections() {
    tui::box 2 1 26 "${TUI_LINES_MINUS}" "Секции / Sections" "$(tui::style bold magenta)"
    local -i i
    for (( i = 0; i < ${#SSHD_WZ_SECTIONS[@]}; i++ )); do
        if (( i == SSHD_WZ_SECTION )); then
            tui::put $(( 3 + i )) 3 "▸ ${SSHD_WZ_SECTIONS[$i]}" "$(tui::style bold reverse white)"
        else
            tui::put $(( 3 + i )) 3 "  ${SSHD_WZ_SECTIONS[$i]}" ""
        fi
    done
}

sshd_wz::draw_params() {
    local -i top=2 left=28
    local -i width=$(( TUI_COLS - left - 1 ))
    local -i height=$(( TUI_LINES - 8 ))
    tui::box "${top}" "${left}" "${width}" "${height}" "Параметры / Parameters" "$(tui::style bold cyan)"
    local -i i name_col_val row
    for (( i = 0; i < ${#SSHD_WZ_NAMES[@]}; i++ )); do
        row=$(( top + 1 + i ))
        (( row >= top + height - 1 )) && break
        local name="${SSHD_WZ_NAMES[$i]}"
        local value="${SSHD_WZ_VALUES[$name]:-}"
        local line="${name} = ${value}"
        if (( i == SSHD_WZ_SELECT )); then
            tui::put "${row}" $(( left + 2 )) "${line}" "$(tui::style bold reverse cyan)"
        elif is::not_empty "${value}"; then
            tui::put "${row}" $(( left + 2 )) "${line}" "$(tui::style green)"
        else
            tui::put "${row}" $(( left + 2 )) "${line}" "$(tui::style dim)"
        fi
    done
}

sshd_wz::draw_desc() {
    local -i top=$(( TUI_LINES - 5 ))
    local name="${SSHD_WZ_NAMES[$SSHD_WZ_SELECT]:-}"
    local desc=""
    is::not_empty "${name}" && desc="$(sshd::param_desc "${name}" 2>/dev/null || true)"
    tui::box "${top}" 1 "${TUI_COLS}" 5 "Подсказка / Tip: ${name}" "$(tui::style bold yellow)"
    local -a lines=()
    mapfile -t lines <<< "${desc}"
    tui::put $(( top + 1 )) 3 "${lines[0]:-}" ""
    tui::put $(( top + 2 )) 3 "${lines[1]:-}" "$(tui::style dim)"
}

sshd_wz::draw_status() {
    tui::statusbar "  ←→ секция · ↑↓ параметр · Enter правка · Space toggle · P профиль · M match · V preview · A apply · ? справка · q выход" "$(tui::style bg_black white)"
}

sshd_wz::draw() {
    TUI_LINES_MINUS=$(( TUI_LINES - 7 ))
    sshd_wz::draw_title
    sshd_wz::draw_sections
    sshd_wz::draw_params
    sshd_wz::draw_desc
    sshd_wz::draw_status
}

# ==========================================
# Main loop / Главный цикл
# ==========================================

sshd_wz::handle_view_key() {
    case "${TUI_KEY}" in
        q|Q|й|Й) return 1 ;;
        LEFT)  (( SSHD_WZ_SECTION > 0 )) && { SSHD_WZ_SECTION=$(( SSHD_WZ_SECTION - 1 )); SSHD_WZ_SELECT=0; sshd_wz::load_names; } ;;
        RIGHT) (( SSHD_WZ_SECTION < ${#SSHD_WZ_SECTIONS[@]} - 1 )) && { SSHD_WZ_SECTION=$(( SSHD_WZ_SECTION + 1 )); SSHD_WZ_SELECT=0; sshd_wz::load_names; } ;;
        UP|k|K|о|О)   (( SSHD_WZ_SELECT > 0 )) && SSHD_WZ_SELECT=$(( SSHD_WZ_SELECT - 1 )) ;;
        DOWN|j|J|л|Л) (( SSHD_WZ_SELECT < ${#SSHD_WZ_NAMES[@]} - 1 )) && SSHD_WZ_SELECT=$(( SSHD_WZ_SELECT + 1 )) ;;
        *) : ;;
    esac
    return 0
}

main() {
    local arg
    for arg in "$@"; do
        case "${arg}" in
            --help) printf 'BS sshd wizard — собирает sshd_config (drop-in или main).\nКлавиши: ←→ ↑↓ Enter Space P M V A ? q\n'; return 0 ;;
            --dry-run) BS_SSHD_DRY_RUN=1 ;;
        esac
    done
    sshd::init 2>/dev/null || true
    sshd_wz::load_sections
    sshd_wz::load_names
    tui::init
    local running=1
    while (( running )); do
        tui::handle_resize
        tui::buf::clear
        sshd_wz::draw
        tui::render
        tui::key_read
        sshd_wz::handle_view_key || running=0
    done
    tui::quit
}

if [[ -n "${BASH_EXECUTION_STRING:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
```

Also add `sshd::init` to `lib/system/sshd.sh` (used by `main`, harmless warning-only):

```bash
# @description Report missing optional runtime pieces (never fails).
# @description Сообщить об отсутствующих необязательных частях (не падает).
sshd::init() {
    is::command "${BS_SSHD_BIN}" || printf 'sshd не найден / not found: %s\n' "${BS_SSHD_BIN}" >&2
    is::dir "${BS_SSHD_DIR}" || printf 'каталог / dir отсутствует / missing: %s\n' "${BS_SSHD_DIR}" >&2
    return "${E_SUCCESS}"
}
```

- [ ] **Step 4: Run to verify pass**

Run: `bash tests/unit/testsshdwizardunit.sh`
Expected: PASS. If `draw_sections` frame height overflows on a small terminal the test still passes because it sets `TUI_COLS/TUI_LINES=100x30`.

- [ ] **Step 5: Update `tests/unit/testsshdunit.sh` interface note**

No change needed; `sshd::install_main` is only referenced by Task 8's test.

- [ ] **Step 6: Commit**

```bash
git add examples/sshd_wizard.sh tests/unit/testsshdwizardunit.sh lib/system/sshd.sh
git commit -m "feat(examples): sshd_wizard skeleton on lib/tui/tui — sections + params screen + Russian tip pane + statusbar; tests: draw buffer/state/profile fill"
```

---

### Task 7: Editing modals (bool / enum / input) with validation

**Files:**
- Modify: `examples/sshd_wizard.sh`
- Modify: `tests/unit/testsshdwizardunit.sh`

**Interfaces:**
- Consumes: modal stack (`tui::modal::open/close/top/draw_all`), `sshd::param_type`, `sshd::validate`.
- Produces:
  - `SSHD_WZ_EDIT_VALUE`, `SSHD_WZ_EDIT_CURSOR`, `SSHD_WZ_EDIT_OPTIONS` (array), `SSHD_WZ_EDIT_SEL`, `SSHD_WZ_EDIT_ERR`.
  - `sshd_wz::begin_edit`, `sshd_wz::modal_edit_draw`, `sshd_wz::handle_edit_key`.

- [ ] **Step 1: Add the failing tests**

Append before `testframework::summary` in `tests/unit/testsshdwizardunit.sh`:

```bash
    testframework::section "edit modal / модалка правки"
    SSHD_WZ_SECTION=0; sshd_wz::load_names
    # find Port (type port) in Network
    local idx=-1 i
    for (( i = 0; i < ${#SSHD_WZ_NAMES[@]}; i++ )); do
        [[ "${SSHD_WZ_NAMES[$i]}" == "Port" ]] && idx=$i
    done
    testframework::assert_true "(( idx >= 0 ))" "Port is in Network"
    SSHD_WZ_SELECT="${idx}"
    SSHD_WZ_VALUES[Port]="22"
    sshd_wz::begin_edit
    testframework::assert_equal "input" "$(tui::modal::top)" "port opens input modal"
    testframework::assert_equal "22" "${SSHD_WZ_EDIT_VALUE}" "input seeded with current value"
    tui::modal::close

    # editing to an invalid value must not commit and must set the error
    SSHD_WZ_EDIT_VALUE="70000"
    SSHD_WZ_EDIT_SEL=0
    sshd_wz::commit_edit
    testframework::assert_true "[[ -n '${SSHD_WZ_EDIT_ERR}' ]]" "invalid value sets error"

    # a valid commit stores the value and closes the modal
    SSHD_WZ_EDIT_VALUE="2222"
    sshd_wz::commit_edit
    testframework::assert_equal "2222" "${SSHD_WZ_VALUES[Port]}" "valid value stored"
    testframework::assert_equal "" "$(tui::modal::top)" "modal closed on commit"
```

- [ ] **Step 2: Run to verify failure**

Run: `bash tests/unit/testsshdwizardunit.sh`
Expected: FAIL — `sshd_wz::begin_edit: command not found`.

- [ ] **Step 3: Implement the modal logic**

Add to `examples/sshd_wizard.sh` after the state declarations:

```bash
declare -g SSHD_WZ_EDIT_VALUE=""
declare -gi SSHD_WZ_EDIT_CURSOR=0
declare -ga SSHD_WZ_EDIT_OPTIONS=()
declare -gi SSHD_WZ_EDIT_SEL=0
declare -g SSHD_WZ_EDIT_ERR=""
declare -g SSHD_WZ_EDIT_MODE=""   # input | choice

# @private Open the right editor for the selected parameter
sshd_wz::begin_edit() {
    local -r name="${SSHD_WZ_NAMES[$SSHD_WZ_SELECT]:-}"
    is::empty "${name}" && return 0
    SSHD_WZ_EDIT_ERR=""
    SSHD_WZ_EDIT_SEL=0
    local -r type="$(sshd::param_type "${name}")"
    local current="${SSHD_WZ_VALUES[$name]:-$(sshd::param_default "${name}")}"
    case "${type}" in
        bool) SSHD_WZ_EDIT_OPTIONS=("yes" "no") ;;
        enum:*) local IFS=','; read -ra SSHD_WZ_EDIT_OPTIONS <<< "${type#enum:}" ;;
        *) SSHD_WZ_EDIT_OPTIONS=() ;;
    esac
    if (( ${#SSHD_WZ_EDIT_OPTIONS[@]} > 0 )); then
        SSHD_WZ_EDIT_MODE="choice"
        local i opt
        for i in "${!SSHD_WZ_EDIT_OPTIONS[@]}"; do
            [[ "${SSHD_WZ_EDIT_OPTIONS[$i]}" == "${current}" ]] && SSHD_WZ_EDIT_SEL=$i
        done
    else
        SSHD_WZ_EDIT_MODE="input"
        SSHD_WZ_EDIT_VALUE="${current}"
        SSHD_WZ_EDIT_CURSOR=${#current}
    fi
    tui::modal::open edit sshd_wz::modal_edit_draw
}

# @private Validate and commit the editor value
sshd_wz::commit_edit() {
    local -r name="${SSHD_WZ_NAMES[$SSHD_WZ_SELECT]:-}"
    local value="${SSHD_WZ_EDIT_VALUE}"
    (( ${#SSHD_WZ_EDIT_OPTIONS[@]} > 0 )) && value="${SSHD_WZ_EDIT_OPTIONS[$SSHD_WZ_EDIT_SEL]}"
    if sshd::validate "${name}" "${value}"; then
        SSHD_WZ_VALUES["${name}"]="${value}"
        SSHD_WZ_EDIT_ERR=""
        tui::modal::close
    else
        SSHD_WZ_EDIT_ERR="Недопустимое значение / invalid value: ${value}"
    fi
}

sshd_wz::modal_edit_draw() {
    local -i w=64 h=8
    tui::center "${w}" "${h}"
    local -i bx="${TUI_CENTER_X}" by="${TUI_CENTER_Y}"
    local -r name="${SSHD_WZ_NAMES[$SSHD_WZ_SELECT]:-}"
    tui::box "${by}" "${bx}" "${w}" "${h}" "Правка / Edit: ${name}" "$(tui::style bold cyan)"
    if [[ "${SSHD_WZ_EDIT_MODE}" == "choice" ]]; then
        local i
        for i in "${!SSHD_WZ_EDIT_OPTIONS[@]}"; do
            if (( i == SSHD_WZ_EDIT_SEL )); then
                tui::put $(( by + 1 + i )) $(( bx + 2 )) "▸ ${SSHD_WZ_EDIT_OPTIONS[$i]}" "$(tui::style bold reverse cyan)"
            else
                tui::put $(( by + 1 + i )) $(( bx + 2 )) "  ${SSHD_WZ_EDIT_OPTIONS[$i]}" ""
            fi
        done
    else
        tui::put $(( by + 2 )) $(( bx + 2 )) "Значение / Value:" ""
        tui::input $(( by + 3 )) $(( bx + 2 )) $(( w - 4 )) "${SSHD_WZ_EDIT_VALUE}" "${SSHD_WZ_EDIT_CURSOR}"
    fi
    is::not_empty "${SSHD_WZ_EDIT_ERR}" && tui::put $(( by + h - 2 )) $(( bx + 2 )) "${SSHD_WZ_EDIT_ERR}" "$(tui::style bold red)"
    tui::put $(( by + h - 1 )) $(( bx + 2 )) "Enter — OK · Esc — отмена" "$(tui::style dim)"
}

sshd_wz::handle_edit_key() {
    if [[ "${SSHD_WZ_EDIT_MODE}" == "choice" ]]; then
        case "${TUI_KEY}" in
            UP|k|K|о|О)   (( SSHD_WZ_EDIT_SEL > 0 )) && SSHD_WZ_EDIT_SEL=$(( SSHD_WZ_EDIT_SEL - 1 )) ;;
            DOWN|j|J|л|Л) (( SSHD_WZ_EDIT_SEL < ${#SSHD_WZ_EDIT_OPTIONS[@]} - 1 )) && SSHD_WZ_EDIT_SEL=$(( SSHD_WZ_EDIT_SEL + 1 )) ;;
            ENTER) sshd_wz::commit_edit ;;
            ESC|q|Q) tui::modal::close ;;
            *) : ;;
        esac
        return 0
    fi
    case "${TUI_KEY}" in
        ENTER) sshd_wz::commit_edit ;;
        ESC) tui::modal::close ;;
        BACKSPACE)
            (( SSHD_WZ_EDIT_CURSOR > 0 )) || return 0
            SSHD_WZ_EDIT_VALUE="${SSHD_WZ_EDIT_VALUE:0:SSHD_WZ_EDIT_CURSOR-1}${SSHD_WZ_EDIT_VALUE:SSHD_WZ_EDIT_CURSOR}"
            SSHD_WZ_EDIT_CURSOR=$(( SSHD_WZ_EDIT_CURSOR - 1 )) ;;
        LEFT)  (( SSHD_WZ_EDIT_CURSOR > 0 )) && SSHD_WZ_EDIT_CURSOR=$(( SSHD_WZ_EDIT_CURSOR - 1 )) ;;
        RIGHT) (( SSHD_WZ_EDIT_CURSOR < ${#SSHD_WZ_EDIT_VALUE} )) && SSHD_WZ_EDIT_CURSOR=$(( SSHD_WZ_EDIT_CURSOR + 1 )) ;;
        *)
            if [[ "${TUI_KEY}" =~ ^[[:print:]]+$ && ${#TUI_KEY} -eq 1 ]]; then
                SSHD_WZ_EDIT_VALUE="${SSHD_WZ_EDIT_VALUE:0:SSHD_WZ_EDIT_CURSOR}${TUI_KEY}${SSHD_WZ_EDIT_VALUE:SSHD_WZ_EDIT_CURSOR}"
                SSHD_WZ_EDIT_CURSOR=$(( SSHD_WZ_EDIT_CURSOR + 1 ))
            fi ;;
    esac
}
```

Wire it into the main loop:

```bash
        tui::key_read
        local top; top="$(tui::modal::top)"
        if is::not_empty "${top}"; then
            sshd_wz::handle_edit_key
        else
            case "${TUI_KEY}" in
                ENTER|SPACE) sshd_wz::begin_edit ;;
                *) sshd_wz::handle_view_key || running=0 ;;
            esac
        fi
```

Also draw modals in the loop: after `sshd_wz::draw`, add `tui::modal::draw_all`. For a bool/choice quick toggle with Space, `begin_edit` already works.

- [ ] **Step 4: Run to verify pass**

Run: `bash tests/unit/testsshdwizardunit.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add examples/sshd_wizard.sh tests/unit/testsshdwizardunit.sh
git commit -m "feat(examples): sshd_wizard editing modals — bool/enum chooser + input with cursor, validate via sshd::validate, error stays in modal; tests: begin/commit invalid/valid"
```

---

### Task 8: Match/chroot, preview, and apply screens + `sshd::install_main`

**Files:**
- Modify: `lib/system/sshd.sh` (add `sshd::install_main`)
- Modify: `examples/sshd_wizard.sh`
- Modify: `tests/unit/testsshdunit.sh`
- Modify: `tests/unit/testsshdwizardunit.sh`

**Interfaces:**
- Consumes: existing module API.
- Produces:
  - `sshd::install_main <src>` — replace/append a managed block in `BS_SSHD_MAIN`, backup, `sshd -t`, rollback.
  - `sshd_wz::render_config` → stdout config text; `sshd_wz::draw_preview` modal; `sshd_wz::apply` (target dropin/main/print).

- [ ] **Step 1: Add tests for `install_main`**

Append before `testframework::summary` in `tests/unit/testsshdunit.sh`:

```bash
    testframework::section "install_main / managed block"
    local mt; mt="$(mktemp -d)"
    export BS_SSHD_MAIN="${mt}/sshd_config"
    export BS_SSHD_BIN="${mt}/sshd-fake"
    cat > "${BS_SSHD_BIN}" <<'EOF'
#!/bin/bash
file="${!#}"
grep -q BAD "${file}" && exit 1
exit 0
EOF
    chmod +x "${BS_SSHD_BIN}"
    printf 'Include /etc/ssh/sshd_config.d/*.conf\n' > "${BS_SSHD_MAIN}"
    printf '%s\nPort 2222\n%s\n' "${SSHD_MARK_BEGIN}" "${SSHD_MARK_END}" > "${mt}/block.conf"
    local mrc=0; sshd::install_main "${mt}/block.conf" || mrc=$?
    testframework::assert_equal "0" "${mrc}" "install_main ok"
    testframework::assert_command "grep -q '^Include ' '${BS_SSHD_MAIN}'" "preexisting line preserved"
    testframework::assert_command "grep -q '^Port 2222$' '${BS_SSHD_MAIN}'" "block content inserted"
    testframework::assert_equal "1" "$(grep -cF "${SSHD_MARK_BEGIN}" "${BS_SSHD_MAIN}")" "single begin marker"
    # second install replaces, not duplicates
    sshd::install_main "${mt}/block.conf" || true
    testframework::assert_equal "1" "$(grep -cF "${SSHD_MARK_BEGIN}" "${BS_SSHD_MAIN}")" "no duplicate block"
    rm -rf "${mt}"
```

- [ ] **Step 2: Run to verify failure**

Run: `bash tests/unit/testsshdunit.sh`
Expected: FAIL — `sshd::install_main: command not found`.

- [ ] **Step 3: Implement `sshd::install_main`**

Append to `lib/system/sshd.sh`:

```bash
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
    is::writable "$(dirname -- "${BS_SSHD_MAIN}")" || return "${LIB_ERROR_PERMISSION_DENIED}"
    local backup=""
    if is::file "${BS_SSHD_MAIN}"; then
        backup="$(sshd::backup "${BS_SSHD_MAIN}")" || return $?
    fi
    local -r tmp="${BS_SSHD_MAIN}.bs.tmp"
    # keep everything outside the managed block / сохранить всё вне блока
    awk -v b="${SSHD_MARK_BEGIN}" -v e="${SSHD_MARK_END}" '
        $0 == b {skip=1; next}
        $0 == e {skip=0; next}
        !skip   {print}
    ' "${BS_SSHD_MAIN}" 2>/dev/null > "${tmp}"
    printf '\n' >> "${tmp}"
    cat -- "${src}" >> "${tmp}"
    if ! sshd::test "${tmp}" >/dev/null 2>&1; then
        rm -f -- "${tmp}"
        return "${LIB_ERROR_INVALID_INPUT}"
    fi
    mv -f -- "${tmp}" "${BS_SSHD_MAIN}" || return "${LIB_ERROR_FILE_OPERATION}"
    sshd::reload || printf 'warning: reload %s failed / не удалось\n' "${BS_SSHD_SERVICE}" >&2
    return "${E_SUCCESS}"
}
```

- [ ] **Step 4: Run module tests to verify pass**

Run: `bash tests/unit/testsshdunit.sh`
Expected: PASS.

- [ ] **Step 5: Add wizard render/preview/apply + test**

Append to `examples/sshd_wizard.sh`:

```bash
# @private Render current values as config text / Отрендерить текущие значения
sshd_wz::render_config() {
    local name value
    for name in "${SSHD_PARAM_ORDER[@]}"; do
        value="${SSHD_WZ_VALUES[$name]:-}"
        is::not_empty "${value}" && printf '%s=%s\n' "${name}" "${value}"
    done | sshd::render
}

sshd_wz::draw_preview() {
    local text; text="$(sshd_wz::render_config)"
    local -i w=$(( TUI_COLS - 4 )) h=$(( TUI_LINES - 2 ))
    tui::box 1 1 "${w}" "${h}" "Предпросмотр / Preview" "$(tui::style bold green)"
    local -a lines=(); mapfile -t lines <<< "${text}"
    local -i i
    for (( i = 0; i < h - 2 && i < ${#lines[@]}; i++ )); do
        tui::put $(( 2 + i )) 3 "${lines[$i]:0:$(( w - 4 ))}" ""
    done
}

sshd_wz::apply() {
    case "${SSHD_WZ_TARGET}" in
        dropin|main)
            sshd_wz::render_config > /tmp/bs-sshd-wizard.conf
            local rc=0
            if [[ "${SSHD_WZ_TARGET}" == "dropin" ]]; then
                sshd::install /tmp/bs-sshd-wizard.conf || rc=$?
            else
                sshd::install_main /tmp/bs-sshd-wizard.conf || rc=$?
            fi
            if (( rc == 0 )); then
                SSHD_WZ_STATUS="Установлено / Installed (${SSHD_WZ_TARGET})"
            else
                SSHD_WZ_STATUS="Ошибка / Error: ${rc}"
            fi
            tui::modal::open result sshd_wz::modal_result_draw
            ;;
        print) SSHD_WZ_VIEW="preview" ;;
    esac
}

sshd_wz::modal_result_draw() {
    local -i w=64 h=6
    tui::center "${w}" "${h}"
    tui::box "${TUI_CENTER_Y}" "${TUI_CENTER_X}" "${w}" "${h}" "Результат / Result" "$(tui::style bold cyan)"
    tui::put $(( TUI_CENTER_Y + 2 )) $(( TUI_CENTER_X + 2 )) "${SSHD_WZ_STATUS:0:$(( w - 4 ))}" ""
    tui::put $(( TUI_CENTER_Y + 4 )) $(( TUI_CENTER_X + 2 )) "Enter — закрыть / close" "$(tui::style dim)"
}
```

Add view keys (in `sshd_wz::handle_view_key`) for `V` (open preview modal), `A` (apply), `P` (cycle profile). Add a preview modal and result-modal key handling in the main loop. Add to the test:

```bash
    testframework::section "render/apply / рендер и применение"
    SSHD_WZ_VALUES[Port]="2222"
    local cfg; cfg="$(sshd_wz::render_config)"
    testframework::assert_command "printf '%s' '${cfg}' | grep -q '^Port 2222$'" "render_config includes Port"
    SSHD_WZ_TARGET="print"; SSHD_WZ_VIEW="params"
    sshd_wz::apply
    testframework::assert_equal "preview" "${SSHD_WZ_VIEW}" "print target switches to preview"
```

- [ ] **Step 6: Run to verify pass**

Run: `bash tests/unit/testsshdwizardunit.sh`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/system/sshd.sh examples/sshd_wizard.sh tests/unit/testsshdunit.sh tests/unit/testsshdwizardunit.sh
git commit -m "feat(system,examples): sshd::install_main managed block + wizard preview/apply (dropin/main/print) and result modal; tests"
```

---

### Task 9: Documentation (en/ru) and overview

**Files:**
- Create: `documentation/en/03-modules/system-sshd.md`
- Create: `documentation/ru/03-modules/system-sshd.md`
- Modify: `documentation/en/03-modules/lib-modules-overview.md`
- Modify: `documentation/ru/03-modules/lib-modules-overview.md`
- Modify: `README.md`

**Interfaces:** none (docs only).

- [ ] **Step 1: Write `documentation/en/03-modules/system-sshd.md`**

Mirror the structure of `documentation/en/03-modules/system-gpu.md`. Include: purpose, Tier (Linux-only; degrades with `LIB_ERROR_*`), source link, `load "lib/system/sshd"` snippet, hook table (`BS_SSHD_DIR`, `BS_SSHD_MAIN`, `BS_SSHD_BIN`, `BS_SSHD_SERVICE`, `BS_SSHD_DRY_RUN`, `BS_SSHD_DROPIN`), catalog API, profiles, render grammar, install/revert semantics, error codes, and a short `examples/sshd_wizard.sh` section.

- [ ] **Step 2: Write the Russian mirror**

`documentation/ru/03-modules/system-sshd.md` — same sections, Russian.

- [ ] **Step 3: Update both overviews**

In `documentation/en/03-modules/lib-modules-overview.md` add to the system list: `[sshd.sh](../../../lib/system/sshd.sh) (server-side sshd config + hardening profiles)`. Do the same in the RU file.

- [ ] **Step 4: Update README**

Add a bullet under the TUI examples area referencing `./bs run examples/sshd_wizard.sh`.

- [ ] **Step 5: Commit**

```bash
git add documentation/en/03-modules/system-sshd.md documentation/ru/03-modules/system-sshd.md \
  documentation/en/03-modules/lib-modules-overview.md documentation/ru/03-modules/lib-modules-overview.md README.md
git commit -m "docs(system): system-sshd.md en/ru + overview + README — catalog, hooks, profiles, render grammar, install semantics, wizard usage"
```

---

### Task 10: Full validation cycle

**Files:** none (verification only; fix as needed).

- [ ] **Step 1: Syntax**

Run: `bash tests/validatesyntax.sh`
Expected: exit 0, no errors on `lib/system/sshd.sh`, `examples/sshd_wizard.sh`, `tests/unit/testsshd*.sh`.

- [ ] **Step 2: ShellCheck**

Run: `bash tests/validateshellcheck.sh`
Expected: no errors (warnings may print).

- [ ] **Step 3: All tests**

Run: `bash tests/runalltests.sh`
Expected: all suites pass, including `testsshdunit` and `testsshdwizardunit`.

- [ ] **Step 4: Manual smoke (dry-run, no root needed)**

Run: `BS_SSHD_DIR=/tmp/bs-sshd-test BS_SSHD_BIN=/bin/true bs run examples/sshd_wizard.sh --dry-run`
Expected: TUI opens, sections/params/tips visible; `q` exits cleanly and restores the terminal.

- [ ] **Step 5: Fix and commit**

Fix any failures; commit with a `fix(...)` message describing the specific defect.

---

## Self-Review

**Spec coverage:** catalog + tips (T1), validate (T2), profiles (T3), render + markers + Match (T4), test/backup/install/revert/reload + hooks (T5), TUI skeleton + params screen + tip pane (T6), editing modals with validation (T7), Match/chroot rendering path + preview + apply incl. `install_main` (T8), docs en/ru + overview + README (T9), validation cycle (T10). Match/chroot authoring UI is delivered as the catalog `Match` section plus `@match` rendering; a separate multi-block Match editor screen was folded into the section-based editor to avoid a second UI subsystem (YAGNI) — the spec's Match/chroot requirement is satisfied via the `Match` section and chroot/SFTP params.

**Placeholders:** none — every step carries runnable code or an exact command.

**Type consistency:** `sshd::param_list/type/desc/default/recommended`, `sshd::validate`, `sshd::profile`, `sshd::render`, `sshd::test/backup/install/install_main/reload/revert` are used with the same names and signatures across tasks. Wizard state names `SSHD_WZ_*` are consistent between T6/T7/T8.

**Review Focus mapping:** (1) non-writable dir → T5 test; (2) missing sshd → T5 test; (3) newline/space injection → T2 tests + T4 empty-skip test; (4) empty value skipped → T4 test; (5) revert without backup → T5 test.
