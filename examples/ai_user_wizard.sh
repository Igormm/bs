#!/usr/bin/env bs
# shellcheck shell=bash
# examples/ai_user_wizard.sh — wizard: restricted AI-user (opencode) sandbox
# examples/ai_user_wizard.sh — визард: ограниченный пользователь для ИИ (opencode)
#
# Creates a system user with minimal privileges for an AI agent: locked
# login, scoped sudoers, resource limits, optional systemd sandbox and
# SELinux context. Run as root. Pure BS framework, no external TUI libs.
# Создаёт системного пользователя с минимумом привилегий для ИИ-агента:
# заблокированный вход, точечные sudoers, лимиты ресурсов, опциональная
# песочница systemd и SELinux-контекст. Запуск от root. Чистый BS.
#
# Запуск / Run:
#   sudo bs run examples/ai_user_wizard.sh
#   sudo ./examples/ai_user_wizard.sh
#
# Главный сценарий / Main scenario (все дефолты — просто Enter):
#   1. sudo bs run examples/ai_user_wizard.sh
#   2. opencode attach http://<IP>:4096 -u opencode -p '<пароль>'
#      (подключение с любого компьютера / connect from any machine)
#
# Структура / Structure:
#   0. вступление / intro       — что делает визард, что получите в конце
#   1. пользователь / username  — под этим пользователем работает сервер
#   2. порт / port              — по нему подключаетесь: http://IP:порт
#   3. пароль / password        — сгенерировать / ввести свой / без пароля
#   4. systemd-сервис / service — юнит /etc/systemd/system/<user>.service
#   5. усиление / hardening     — sudoers, песочница юнита, SELinux
#   6. сводка / summary         — подтверждение (включая предупреждение,
#                                 если юнит уже существует) → применение
#                                 → итоговая рамка «Что дальше / NEXT»
#
# Компоненты фреймворка / Framework components (всё в lib/):
#   lib/ui/wizard     — движок визарда: рамки, меню, чекбоксы, ввод
#                       (wizard::menu/multi_menu/yn/ask_input/ask_pass/
#                       intro/box/alert/fail) — общий для визардов BS
#   lib/ui/steplog    — журнал шагов: пишется при ЛЮБОМ завершении
#   lib/system/apply  — выполнение шагов с отчётом об ошибке (apply::run,
#                       apply::check_tools)
#   lib/system/user   — провижининг пользователя: useradd/passwd -l/
#                       группы/лимиты/sudoers с visudo -c (user::*)
#   lib/system/systemd— юниты: путь/наличие/запись/daemon-reload/
#                       enable/start/stop/restart/status (systemd::*)
#   lib/ui/presentation — финальные уведомления и таблица статусов

load "lib/ui/presentation"
load "lib/ui/steplog"
load "lib/ui/wizard"
load "lib/system/apply"
load "lib/system/systemd"
load "lib/system/user"

# ==========================================
# Application logic / Логика применения
# ==========================================

# @private Cancel: leave the alt screen and report the step.
# @private Отмена: выйти из alt-экрана и сообщить, на каком шаге остановились.
# @param $1 Step description / Описание шага
aiw::cancel() {
    steplog::warn "Отменено / Cancelled: ${1}"
    wizard::__restore
    printf '\n'
    presentation::warning "Отменено / Cancelled"
    presentation::info "Остановился на шаге / Stopped at step: ${1}"
    presentation::info "Ничего не изменено / Nothing was changed"
    exit 0
}

# @private Run an apply step; framed error with the command on failure.
#   Обёртка над apply::run (логирует шаг/команду/подсказку про журнал) —
#   визуальная часть остаётся у визарда: рамка ошибки + exit 1.
# @private Выполнить шаг применения; при ошибке — рамка с командой.
#   Wraps apply::run (logs step/command/journal hint); the visual part stays
#   with the wizard: an error frame + exit 1.
# @param $1 Description / Описание
# @param $@ Command / Команда
aiw::apply() {
    local -r desc="$1"
    shift
    if ! apply::run "${desc}" "$@"; then
        aiw::fail "Шаг не выполнен / Step failed: ${desc}
  Команда / Command: $*
  Журнал / Log: journalctl -xe"
    fi
}

# @private Check required tools; abort framed on missing ones.
# @private Проверить обязательные утилиты; при отсутствии — рамка ошибки.
# @param $@ Tool names / Имена утилит
aiw::check_tools() {
    if ! apply::check_tools "$@"; then
        aiw::fail "Отсутствуют зависимости / Missing dependencies.
Установите пакеты и повторите / Install the packages and retry."
    fi
}

# @private Abort with a framed error (logged first).
# @private Прервать с ошибкой в рамке (сначала — в журнал).
aiw::fail() {
    steplog::error "${1}"
    wizard::fail "${1}"
}

# ==========================================
# Progress indicators / Индикаторы прогресса
#   step_go/step_ok — вывод в терминал + запись в журнал шагов.
# ==========================================

step_go() {
    printf '  '
    wizard::__sgr 36
    printf '▶'
    wizard::__sgr_reset
    printf ' %s\n' "$1"
    steplog::step "$1"
}
step_ok() {
    printf '  '
    wizard::__sgr 32
    printf '✓'
    wizard::__sgr_reset
    printf ' %s\n' "$1"
    steplog::ok "$1"
}

main() {
    # Флаг подробного журнала / verbose flag: --verbose или verbose (без --)
    local verbose=0
    case "${1:-}" in
        --verbose|verbose)
            verbose=1
            shift
            ;;
    esac

    # -h/--help: справка без запуска визарда и БЕЗ создания журнала
    # (help не должен трогать /tmp/ai_user_wizard.log, оставшийся от
    # чужого запуска под root).
    # -h/--help: usage without starting the wizard and WITHOUT touching
    # the log (help must not poke /tmp/ai_user_wizard.log left by a
    # foreign root run).
    case "${1:-}" in
        -h|--help)
            printf 'Usage: sudo bs run examples/ai_user_wizard.sh\n'
            printf '       sudo ./examples/ai_user_wizard.sh\n\n'
            printf 'Что это / What is this:\n'
            printf '  Запускает opencode-сервер на этой машине в песочнице:\n'
            printf '  создаёт ограниченного системного пользователя (вход по паролю\n'
            printf '  запрещён) и запускает `opencode serve` как systemd-сервис.\n'
            printf '  В конце выдаёт команду подключения — вы подключаетесь к серверу\n'
            printf '  с любого компьютера.\n'
            printf '  Runs an opencode server on this machine in a sandbox: creates a\n'
            printf '  restricted system user (password login locked) and runs\n'
            printf '  `opencode serve` as a systemd service. The end prints the connect\n'
            printf '  command — you attach to the server from any machine.\n\n'
            printf 'Главный сценарий / Main scenario (все дефолты / all defaults):\n'
            printf '  1. sudo bs run examples/ai_user_wizard.sh   # Enter Enter ... Enter\n'
            printf '  2. opencode attach http://<IP>:4096 -u opencode -p '\''<пароль>'\''\n'
            printf '     # подключение с любого компьютера / connect from any machine\n\n'
            printf 'Шаги визарда / Wizard steps (все параметры — с дефолтом):\n'
            printf '  1. Имя пользователя / Username        (default: ai-agent)\n'
            printf '  2. Порт сервера / Server port          (default: 4096)\n'
            printf '  3. Пароль / Password                   сгенерировать / ввести свой / без пароля\n'
            printf '  4. systemd-сервис / Service            создать+запустить / только создать / не создавать\n'
            printf '     юнит: /etc/systemd/system/<user>.service; пароль — в /srv/<user>/opencode.env (root:600)\n'
            printf '     unit: /etc/systemd/system/<user>.service; password — in /srv/<user>/opencode.env (root:600)\n'
            printf '  5. Усиление / Hardening                sudo для сервиса+firewall, песочница, SELinux\n'
            printf '  6. Сводка / Summary → подтверждение → применение\n\n'
            printf 'Что делает / What it does:\n'
            printf '  • useradd -m -s /usr/sbin/nologin + passwd -l (вход по паролю запрещён)\n'
            printf '  • /srv/<user> с правами пользователя; лимиты nproc=128 nofile=4096 core=0\n'
            printf '  • sudoers (по выбору): systemctl сервиса + firewall-cmd\n'
            printf '  • systemd-unit opencode serve (порт из шага 2), пароль в env root:600\n'
            printf '  • песочница unit (ProtectSystem/PrivateTmp) и SELinux-контекст — по выбору\n\n'
            printf 'Если юнит уже существует — визард предупредит и покажет его текущий\n'
            printf 'ExecStart перед перезаписью / If the unit already exists the wizard\n'
            printf 'warns and shows its current ExecStart before rewriting it.\n\n'
            printf 'Клавиши / Keys: ↑/↓, 1-9 — выбор · Space — отметить · Enter — OK · q — отмена\n'
            printf '\nПодробный журнал / Verbose log: --verbose (или / or: verbose)\n'
            printf '  журнал всегда пишется в ${TMPDIR:-/tmp}/ai_user_wizard.log; --verbose\n'
            printf '  дополнительно выводит строки лога в stderr / the log is always\n'
            printf '  written to ${TMPDIR:-/tmp}/ai_user_wizard.log; --verbose also prints\n'
            printf '  log lines to stderr.\n'
            exit 0
            ;;
    esac

    # Журнал пишется при ЛЮБОМ завершении / the log is written on ANY exit
    steplog::init "${TMPDIR:-/tmp}/ai_user_wizard.log" "${verbose}"

    # Терминал восстанавливается при любом выходе (хук steplog + SIGINT)
    # The terminal is restored on ANY exit (steplog hook + SIGINT)
    steplog::on_exit wizard::__restore
    signal::on INT wizard::__restore

    # ---- root check / проверка прав
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        aiw::fail $'Требуются права root / Root required.\n  Запустите: sudo bs run examples/ai_user_wizard.sh\n  Run:        sudo bs run examples/ai_user_wizard.sh'
    fi

    # ---- 0. вступление / intro: что это и что получится в конце
    wizard::__enter_alt
    local -a intro_lines=(
        "Этот визард запускает opencode-сервер на этой машине:"
        "This wizard runs an opencode server on this machine:"
        ""
        "  • создаёт системного пользователя (вход по паролю запрещён)"
        "    creates a system user (password login locked)"
        "  • запускает opencode serve как systemd-сервис"
        "    runs opencode serve as a systemd service"
        "  • в конце выдаёт команду подключения — копируйте и работайте"
        "    prints the connect command at the end — copy and go"
        ""
        "Всё по умолчанию — просто жмите Enter."
        "All defaults — just press Enter."
    )
    wizard::intro "Что это / WHAT THIS IS" "${intro_lines[@]}" || aiw::cancel "0/6 — вступление / intro"

    # ---- 1-2. пользователь и порт / user and port
    # Пользователь: сервер будет работать ПОД этим пользователем; вход по
    # паролю запрещён (nologin) — зайти «как он» нельзя, только sudo-правила
    # из шага 5. Сервис systemd называется так же, как пользователь.
    # Username: the server runs AS this user; password login is locked
    # (nologin) — you cannot log in as them, only the sudo rules from step 5.
    # The systemd service is named after the user.
    local ai_user service port
    wizard::ask_input ai_user "1/6 — Имя пользователя / Username" "ai-agent" \
        "Под этим пользователем работает сервер / The server runs as this user"
    [[ "${ai_user}" == "q" ]] && aiw::cancel "1/6 — имя пользователя / username"
    service="${ai_user}"   # сервис называется как пользователь / service named after the user

    # Порт: по нему вы подключаетесь — http://IP:порт. Тот же порт попадает
    # в ExecStart юнита и в правило firewall из шага 5.
    # Port: you connect via http://IP:port. The same port goes into the unit
    # ExecStart and the firewall rule from step 5.
    wizard::ask_input port "2/6 — Порт сервера / Server port" "4096" \
        "По этому порту вы подключитесь: http://IP:порт / Connect via http://IP:port"
    [[ "${port}" == "q" ]] && aiw::cancel "2/6 — порт / port"
    [[ "${port}" =~ ^[0-9]+$ ]] || aiw::fail "Порт должен быть числом / Port must be a number: ${port}"
    (( port >= 1 && port <= 65535 )) || aiw::fail "Порт вне диапазона 1-65535 / Port out of range 1-65535: ${port}"

    # ---- 3. пароль / password
    # Пароль защищает подключение к серверу (basic auth); без него
    # подключиться сможет любой, кто дотянется до порта. Вариант «ввести
    # свой» — ask_pass с подтверждением и маской; «без пароля» помечен
    # НЕБЕЗОПАСНО. Пароль живёт в env-файле root:600 и показывается один раз.
    # Password protects server connections (basic auth); without it anyone
    # who can reach the port can connect. "Enter my own" — ask_pass with
    # confirmation and masking; "No password" is marked UNSECURED. The
    # password lives in a root:600 env file and is shown once.
    local pass_mode ai_pass=""
    wizard::menu pass_mode "3/6 — Пароль сервера / Server password" \
        "Пароль для подключения к серверу / Server access password" \
        "Сгенерировать / Generate" \
        "Ввести свой / Enter my own" \
        "Без пароля (НЕБЕЗОПАСНО / UNSECURED)"
    [[ "${pass_mode}" == "99" ]] && aiw::cancel "3/6 — пароль / password"
    case "${pass_mode}" in
        0) ai_pass="$(wizard::gen_pass)" ;;
        1) wizard::ask_pass ai_pass "Пароль для подключения к серверу / Password used to connect to the server"; [[ "${ai_pass}" == "q" ]] && aiw::cancel "3/6 — пароль / password" ;;
        2) ai_pass="" ;;
    esac

    # ---- 4. systemd-сервис / service
    # Юнит /etc/systemd/system/<user>.service: systemd сам запускает сервер,
    # в т.ч. после перезагрузки, и перезапускает при падении (Restart=always).
    # Пароль передаётся через EnvironmentFile (root:600), а не в ExecStart.
    # Unit /etc/systemd/system/<user>.service: systemd runs the server itself,
    # also after reboot, and restarts it on crash (Restart=always). The
    # password is passed via EnvironmentFile (root:600), not in ExecStart.
    local svc
    wizard::menu svc "4/6 — systemd-сервис / systemd service" \
        "systemd сам запускает сервер, в т.ч. после перезагрузки / systemd runs the server, also after reboot" \
        "Создать и запустить / Create and start" \
        "Только создать / Create only" \
        "Не создавать / Do not create"
    [[ "${svc}" == "99" ]] && aiw::cancel "4/6 — systemd-сервис / service"

    # ---- 5. усиление / hardening (checkboxes)
    # Всё необязательно: (0) sudoers — пользователь сможет сам управлять
    # сервисом и firewall-cmd без пароля; (1) песочница юнита — ProtectSystem/
    # PrivateTmp, сервер видит только свои каталоги; (2) SELinux-контекст.
    # All optional: (0) sudoers — the user can manage the service and
    # firewall-cmd without a password; (1) unit sandbox — ProtectSystem/
    # PrivateTmp, the server sees only its own dirs; (2) SELinux context.
    local hard_pick
    wizard::multi_menu hard_pick "5/6 — Усиление / Hardening" \
        "Дополнительная защита — всё необязательно / Extra protection — all optional" \
        "sudo: управление сервисом + firewall-cmd" \
        "Песочница systemd / systemd sandbox" \
        "SELinux-контекст / SELinux context"
    [[ "${hard_pick}" == "q" ]] && aiw::cancel "5/6 — усиление / hardening"
    # Индексы храним как массив (Torvalds: никакого substring-матчинга
    # цифр — "10" ложно матчит "1"). 
    # Keep indices as an array (Torvalds: no digit-substring matching —
    # "10" would falsely match "1").
    local -a hard_idx=()
    local idx
    for idx in ${hard_pick}; do
        hard_idx+=("${idx}")
    done
    local want_sudo=0 want_sandbox=0 want_selinux=0
    [[ " ${hard_idx[*]} " == *" 0 "* ]] && want_sudo=1
    [[ " ${hard_idx[*]} " == *" 1 "* ]] && want_sandbox=1
    [[ " ${hard_idx[*]} " == *" 2 "* ]] && want_selinux=1

    # sudoers: управление сервисом + firewall
    # Правила вида "<user> ALL=(root) NOPASSWD: <команда>" — пользователь
    # может запускать ТОЛЬКО эти команды от root, и без пароля.
    # Rules "<user> ALL=(root) NOPASSWD: <command>" — the user can run ONLY
    # these commands as root, and without a password.
    local -a sudo_lines=()
    if (( want_sudo == 1 )); then
        if [[ "${svc}" != "2" ]]; then
            sudo_lines+=("systemctl daemon-reload")
            sudo_lines+=("systemctl enable ${service}.service")
            sudo_lines+=("systemctl start ${service}.service")
            sudo_lines+=("systemctl stop ${service}.service")
            sudo_lines+=("systemctl restart ${service}.service")
            sudo_lines+=("systemctl status ${service}.service")
        fi
        sudo_lines+=("firewall-cmd *")
    fi

    # лимиты: фиксированные средние / fixed medium defaults (no question)
    local -r nproc=128 nofile=4096

    # ---- проверка зависимостей / dependency check
    # Проверяем ДО ввода пользователем — провал на середине применения
    # оставил бы систему в полуготовом состоянии.
    # Checked BEFORE apply — a mid-apply failure would leave a half-done state.
    local -a need=(id useradd passwd usermod mkdir chown)
    (( ${#sudo_lines[@]} > 0 )) && need+=(visudo)
    [[ "${svc}" != "2" ]] && need+=(systemctl)
    (( want_selinux == 1 )) && need+=(semanage restorecon)
    aiw::check_tools "${need[@]}"

    # Путь к opencode берём из PATH, не хардкодим /usr/local/bin:
    # сервис должен запускаться на этой машине, а не по догадке
    # (Torvalds: никаких спец-кейсов с магическими путями).
    # Resolve opencode from PATH, never hardcode /usr/local/bin:
    # the service must run on THIS machine, not on a guess
    # (Torvalds: no magic-path special cases).
    local opencode_bin=""
    if is::command opencode; then
        opencode_bin="$(command -v opencode)"
    fi

    # ---- 6. сводка / summary
    # Перед подтверждением — предупреждение, если юнит уже существует:
    # пользователь должен ЗНАТЬ, что файл перезапишется и что в нём сейчас
    # (текущий ExecStart) — иначе «перезаписал и забыл».
    # Before confirmation — a warning if the unit already exists: the user
    # must KNOW the file will be rewritten and what is in it now (current
    # ExecStart) — otherwise "rewrote and forgot".
    local -a unit_warn=()
    if [[ "${svc}" != "2" ]] && systemd::unit_exists "${service}"; then
        local -r unit_path="$(systemd::unit_path "${service}")"
        local -r cur_exec="$(systemd::unit_execstart "${service}")"
        unit_warn+=("${unit_path} уже существует / already exists")
        if is::not_empty "${cur_exec}"; then
            unit_warn+=("ExecStart сейчас / currently: ${cur_exec}")
        fi
        unit_warn+=("Файл будет ПЕРЕЗАПИСАН / the file will be REWRITTEN")
        if ! wizard::alert "$(printf '%s\n' "${unit_warn[@]}")" "Внимание / ATTENTION"; then
            aiw::cancel "6/6 — предупреждение о юните / unit warning"
        fi
    fi

    # Сводка — всё, что будет создано/изменено, одним списком.
    # The summary — everything that will be created/changed, in one list.
    local summary
    printf -v summary "%s\n" \
        "Пользователь / User:  ${ai_user}" \
        "Сервис / Service:     ${service}  (порт ${port})" \
        "Юнит / Unit:          /etc/systemd/system/${service}.service" \
        "Пароль:               $([[ -n "${ai_pass}" ]] && echo 'сгенерирован / generated' || echo 'без пароля / none')" \
        "sudo-команд:          ${#sudo_lines[@]}" \
        "Лимиты:               nproc=${nproc}, nofile=${nofile}, core=0" \
        "Песочница:            $([[ ${want_sandbox} == 1 ]] && echo 'да / yes' || echo 'нет / no')   SELinux: $([[ ${want_selinux} == 1 ]] && echo 'да / yes' || echo 'нет / no')" \
        "systemd-сервис:       $(case ${svc} in 0) echo 'создать+запустить';; 1) echo 'только создать';; 2) echo 'не создавать';; esac)"
    local apply
    wizard::yn apply "Применить настройки? / Apply settings?" "${summary}"
    [[ "${apply}" == "q" ]] && aiw::cancel "6/6 — сводка / summary"
    if [[ "${apply}" != "y" ]]; then
        aiw::fail "Отменено пользователем / Cancelled by user"
    fi

    # ==========================================
    # ---- применение / apply
    # Каждый шаг: step_go (▶ в терминал + журнал) → действие → step_ok (✓).
    # Every step: step_go (▶ to the terminal + log) → action → step_ok (✓).
    # ==========================================
    local -r w="$(wizard::__box_width)"
    wizard::box "Применение / APPLYING" "Выполняется… / Running…
Пароль будет показан один раз в конце / the password is shown once at the end."
    printf '\n'

    # passwd -l только для СОЗДАННОГО пользователя: блокировка пароля
    # существующего реального пользователя = потеря доступа (Thompson:
    # не трогай состояние, которое не создавал).
    # passwd -l only for a user WE created: locking an existing real
    # user's password is access loss (Thompson: never touch state you
    # didn't create).
    # Статусы для итоговой таблицы / state labels for the result table
    local state_user="создан / created" state_sudoers="не требуется / none" \
          state_limits="записаны / written" state_unit="не создан / skipped" \
          state_svc="не создан / skipped" state_pass="без пароля / none"
    case "${pass_mode}" in
        0) state_pass="сгенерирован / generated" ;;
        1) state_pass="введён / entered" ;;
    esac

    # ---- пользователь / user
    # useradd: системный пользователь с домашним каталогом и БЕЗ шелла
    # (/usr/sbin/nologin) — вход по паролю невозможен в принципе.
    # useradd: a system user with a home dir and NO shell (/usr/sbin/nologin)
    # — password login is impossible by design.
    local user_existed=0
    if ! user::exists "${ai_user}"; then
        step_go "useradd -m -s /usr/sbin/nologin ${ai_user}"
        aiw::apply "useradd ${ai_user}" user::create "${ai_user}"
        step_ok "пользователь создан / user created"
    else
        user_existed=1
        state_user="существовал / existed"
        step_ok "пользователь существует / user exists"
    fi

    # Блокировка пароля только для созданного нами пользователя.
    # Password locking only for the user WE created.
    if (( user_existed == 1 )); then
        step_go "ПРЕДУПРЕЖДЕНИЕ: ${ai_user} уже существует — вход НЕ блокируем / login NOT locked"
        step_ok "существующий пользователь оставлен как есть / existing user left untouched"
    else
        step_go "passwd -l ${ai_user}  (вход по паролю запрещён / password login locked)"
        aiw::apply "passwd -l ${ai_user}" user::lock_password "${ai_user}"
        step_ok "пароль заблокирован / password locked"
    fi

    # Группа systemd-journal: сервер сможет читать свой журнал (journalctl -u).
    # The systemd-journal group: the server can read its own journal.
    step_go "usermod -aG systemd-journal ${ai_user}"
    aiw::apply "usermod -aG systemd-journal ${ai_user}" user::add_group "${ai_user}" systemd-journal
    step_ok "journal-группа / journal group"

    # Рабочий каталог сервера: /srv/<user> принадлежит пользователю.
    # The server working dir: /srv/<user> owned by the user.
    local -i srv_existed=0
    [[ -d "/srv/${ai_user}" ]] && srv_existed=1
    aiw::apply "mkdir -p /srv/${ai_user}" mkdir -p "/srv/${ai_user}"
    aiw::apply "chown /srv/${ai_user}" chown "${ai_user}":"${ai_user}" "/srv/${ai_user}"
    if (( srv_existed == 1 )); then
        step_ok "/srv/${ai_user} уже существовал / already existed"
    else
        step_ok "/srv/${ai_user} готов / ready"
    fi

    # ---- sudoers / sudo-права
    # Файл /etc/sudoers.d/<user> (chmod 440) проверяется visudo -c; при
    # неудаче проверки модуль сам откатывает файл — sudo не сломается.
    # /etc/sudoers.d/<user> (chmod 440) is verified with visudo -c; the
    # user module reverts the file on failure — sudo will not break.
    local sudoers_file="${BS_SUDOERS_DIR}/${ai_user}"
    if (( ${#sudo_lines[@]} > 0 )); then
        local -i sudoers_existed=0
        [[ -f "${sudoers_file}" ]] && sudoers_existed=1
        if (( sudoers_existed == 1 )); then
            state_sudoers="перезаписан / rewritten"
        else
            state_sudoers="записан / written"
        fi
        step_go "запись sudoers / writing ${sudoers_file}"
        aiw::apply "запись sudoers / writing" user::write_sudoers "${ai_user}" "${sudo_lines[@]}"
        step_ok "sudoers записан и проверен / written and verified"
    else
        rm -f "${sudoers_file}"
        step_ok "sudoers не требуется / no sudoers needed"
    fi

    # ---- лимиты / limits (фиксированные средние / fixed medium defaults)
    # /etc/security/limits.d/<user>.conf: nproc=128, nofile=4096, core=0 —
    # сервер не сможет исчерпать ресурсы машины.
    # /etc/security/limits.d/<user>.conf: nproc=128, nofile=4096, core=0 —
    # the server cannot exhaust the machine's resources.
    local limits_file="${BS_LIMITS_DIR}/${ai_user}.conf"
    local -i limits_existed=0
    [[ -f "${limits_file}" ]] && limits_existed=1
    if (( limits_existed == 1 )); then
        state_limits="уже были / existed"
    fi
    step_go "запись лимитов / writing ${limits_file}"
        aiw::apply "запись лимитов / writing" user::write_limits "${ai_user}" "${nproc}" "${nofile}" >/dev/null
    step_ok "лимиты записаны / limits written"

    # ---- systemd-сервис / service unit
    # Юнит: [Unit] — порядок запуска; [Service] — под кем и как запускать;
    # песочница — отдельным блоком по выбору. ExecStart — opencode serve на
    # порту из шага 2; пароль — через EnvironmentFile, НЕ в командной строке.
    # Unit: [Unit] — boot ordering; [Service] — as whom and how to run; the
    # sandbox is a separate optional block. ExecStart — opencode serve on the
    # port from step 2; the password — via EnvironmentFile, NOT on the CLI.
    if [[ "${svc}" != "2" ]]; then
        if is::empty "${opencode_bin}"; then
            aiw::fail "opencode не найден в PATH / opencode not found in PATH — сервис не создан / service not created"
        fi
        local env_file="/srv/${ai_user}/opencode.env"
        local -i unit_existed=0
        [[ -f "${BS_SYSTEMD_UNIT_DIR}/${service}.service" ]] && unit_existed=1
        if (( unit_existed == 1 )); then
            state_unit="перезаписан / rewritten"
        else
            state_unit="создан / created"
        fi

        # env-файл: umask в subshell — права 600, пароль не утечёт в другие
        # процессы; владелец root (сервис читает его как root). Повторный
        # запуск ПЕРЕЗАПИСЫВАЕТ пароль — старый перестаёт действовать.
        # env file: umask in a subshell — mode 600, the password does not
        # leak into other processes; owned by root (the service reads it as
        # root). A re-run REPLACES the password — the old one stops working.
        if is::not_empty "${ai_pass}"; then
            local -i env_existed=0
            [[ -f "${env_file}" ]] && env_existed=1
            (
                umask 177
                printf 'OPENCODE_SERVER_PASSWORD=%s\n' "${ai_pass}" > "${env_file}"
            )
            chown root:root "${env_file}"
            chmod 600 "${env_file}"
            if (( env_existed == 1 )); then
                state_pass="${state_pass} / ПЕРЕЗАПИСАН / REPLACED"
                step_go "внимание: пароль ПЕРЕЗАПИСАН / note: password REPLACED (старый пароль недействителен / old password invalid)"
            fi
            step_ok "пароль в ${env_file} (root:root 600)"
        else
            rm -f "${env_file}"
        fi

        # Сборка содержимого юнита (без пароля в командной строке).
        # Unit content assembly (no password on the command line).
        local -a unit_lines=(
            '[Unit]'
            "Description=opencode server for ${ai_user}"
            'After=network.target'
            ''
            '[Service]'
            "User=${ai_user}"
            "Group=${ai_user}"
            "WorkingDirectory=/srv/${ai_user}"
        )
        if is::not_empty "${ai_pass}"; then
            unit_lines+=("EnvironmentFile=${env_file}")
        fi
        unit_lines+=("ExecStart=${opencode_bin} serve --hostname 0.0.0.0 --port ${port}")
        unit_lines+=('Restart=always')
        if (( want_sandbox == 1 )); then
            # Песочница: сервер видит только /srv/<user> и /home/<user>,
            # / — read-only, tmp — приватный.
            # Sandbox: the server sees only /srv/<user> and /home/<user>,
            # / is read-only, tmp is private.
            unit_lines+=(
                ''
                '# Песочница / Sandbox'
                'ProtectSystem=strict'
                'ProtectHome=read-only'
                "ReadWritePaths=/srv/${ai_user} /home/${ai_user}"
                'PrivateTmp=true'
                "LimitNOFILE=${nofile}"
            )
        fi
        local unit
        printf -v unit '%s\n' "${unit_lines[@]}"

        step_go "запись unit / writing ${BS_SYSTEMD_UNIT_DIR}/${service}.service"
        aiw::apply "запись unit / writing" systemd::unit_write "${service}" "${unit}"
        step_ok "unit записан / unit written"

        # Перезагрузка конфигурации systemd — без неё новый юнит не виден.
        # Reloading the systemd configuration — without it the new unit is
        # not visible.
        aiw::apply "systemctl daemon-reload" systemd::daemon_reload
        if [[ "${svc}" == "0" ]]; then
            if systemd::unit_running "${service}"; then
                state_svc="уже работал / was running"
                step_ok "сервис уже запущен / service already running"
            else
                aiw::apply "systemctl enable --now ${service}.service" systemd::unit_enable_now "${service}"
                state_svc="запущен / started"
                step_ok "сервис запущен / service started"
            fi
        else
            state_svc="создан, не запущен / created, not started"
            step_ok "сервис создан, не запущен / created, not started"
        fi
    else
        step_ok "сервис не создаётся / service skipped"
    fi

    # ---- SELinux / контекст
    # fcontext + restorecon: каталог /srv/<user> получает контекст, в котором
    # серверу разрешено писать (httpd_sys_rw_content_t — де-факто стандарт
    # для веб/серверных каталогов в SELinux).
    # fcontext + restorecon: /srv/<user> gets a context the server is
    # allowed to write (httpd_sys_rw_content_t — the de-facto standard for
    # web/server dirs under SELinux).
    if (( want_selinux == 1 )); then
        step_go "SELinux: fcontext + restorecon"
        if command -v semanage >/dev/null 2>&1; then
            aiw::apply "semanage fcontext ${ai_user}" semanage fcontext -a -t httpd_sys_rw_content_t "/srv/${ai_user}(/.*)?"
            aiw::apply "restorecon /srv/${ai_user}" restorecon -Rv "/srv/${ai_user}"
            step_ok "контекст применён / context applied"
        else
            step_go "semanage не найден — пропуск / not found, skipped"
        fi
    else
        step_ok "SELinux не трогаем / SELinux untouched"
    fi

    # ==========================================
    # ---- итог / final summary
    # Рамка «Что дальше / NEXT»: подключение первым, затем управление
    # сервисом и файлы. Пароль — один раз, отдельной строкой (не обрезается
    # рамкой).
    # The "NEXT" frame: connect first, then service control and files. The
    # password — once, on its own line (never clipped by the frame).
    # ==========================================
    printf '\n\n'
    # реальный IP машины для строки подключения / the machine IP for the connect line
    local -r machine_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    is::empty "${machine_ip}" && local -r machine_ip="<ip>"

    local -a final_lines=(
        "Готово! Сервер запущен / Done! The server is running"
        ""
        "Что дальше / NEXT — с любого компьютера / from any machine:"
        "  Подключение / Connect:"
    )
    if is::not_empty "${ai_pass}"; then
        final_lines+=(
            "    opencode attach http://${machine_ip}:${port} -u opencode"
            "      -p '${ai_pass}'"
        )
    else
        final_lines+=("    opencode attach http://${machine_ip}:${port}")
    fi

    if [[ "${svc}" != "2" ]]; then
        # Управление: все команды — от root (sudo) или по sudoers из шага 5.
        # Control: all commands as root (sudo) or via the step-5 sudoers.
        final_lines+=(
            ""
            "  Управление / Control (sudo):"
            "    systemctl status ${service}      # статус / status"
            "    systemctl restart ${service}     # перезапуск / restart"
            "    systemctl stop ${service}        # остановить / stop"
            "    systemctl start ${service}       # запустить / start"
            "    journalctl -u ${service} -f      # логи сервиса / service logs"
            ""
            "  Файлы / Files:"
            "    /etc/systemd/system/${service}.service   # юнит / unit"
        )
        if is::not_empty "${ai_pass}"; then
            final_lines+=("    ${env_file}                 # пароль root:600 / password")
        fi
    else
        final_lines+=(
            ""
            "  Сервис не создан — запустите вручную / no service: run manually:"
            "    opencode serve --hostname 0.0.0.0 --port ${port}"
        )
    fi
    if (( ${#sudo_lines[@]} > 0 )); then
        final_lines+=("    ${sudoers_file}            # sudo-права / sudo rules")
    fi
    final_lines+=("    ${limits_file}       # лимиты / limits")

    final_lines+=(
        ""
        "Пользователь / User:  ${ai_user} (вход запрещён / login locked)"
        "Каталог / Dir:        /srv/${ai_user}"
    )
    if is::not_empty "${ai_pass}"; then
        # Пароль показываем ОДИН раз в конце (Jobs: клиент должен мочь
        # завершить сценарий; дальше он живёт только в env-файле root:600).
        # Show the password ONCE at the end (Jobs: the customer must be
        # able to finish the scenario; after this it lives only in the
        # root:600 env file).
        final_lines+=(
            ""
            "ПАРОЛЬ / PASSWORD (показывается один раз / one-time):"
            "  ${ai_pass}"
            "  (также в /srv/${ai_user}/opencode.env, root:600)"
        )
    fi
    final_lines+=("" "sudo:  sudo -l -U ${ai_user}   # выданные права / granted rules")

    local final
    printf -v final '%s\n' "${final_lines[@]}"
    local -i fin_lines=0
    while IFS= read -r _; do fin_lines=$((fin_lines + 1)); done <<< "${final}"
    wizard::box "ИТОГ / RESULT" "${final}" "  Enter — завершить / to finish"
    wizard::__read_key >/dev/null

    # Выход из alt-экрана: итог и следующие шаги остаются в терминале.
    # Leave the alternate screen: the result and next steps stay visible.
    wizard::__restore
    printf '\n'
    presentation::success "Готово! / Done! ${ai_user} создан / created"
    printf '\n'
    presentation::boxed "${final}" round
    printf '\n'
    presentation::table "Компонент / Item:Статус / Status" \
        "пользователь / user:${state_user}" \
        "sudoers:${state_sudoers}" \
        "лимиты / limits:${state_limits}" \
        "unit:${state_unit}" \
        "сервис / service:${state_svc}" \
        "пароль / password:${state_pass}"
    printf '\n'
    presentation::info "Что дальше / NEXT — с любого компьютера / from any machine:"
    presentation::info "  1. Подключитесь / Connect:"
    presentation::info "     opencode attach http://${machine_ip}:${port}"
    if is::not_empty "${ai_pass}"; then
        presentation::info "         -u opencode -p '${ai_pass}'"
    fi
    presentation::info "  2. Управление / Manage:"
    if [[ "${svc}" != "2" ]]; then
        presentation::info "     sudo systemctl status ${service}   # статус / status"
        presentation::info "     sudo systemctl restart ${service}  # перезапуск / restart"
        presentation::info "     sudo systemctl stop ${service}     # остановить / stop"
        presentation::info "     sudo systemctl start ${service}    # запустить / start"
        presentation::info "     journalctl -u ${service} -f         # логи / logs"
    else
        presentation::info "     сервис не создан — запустите вручную / no service: run manually"
        presentation::info "     opencode serve --hostname 0.0.0.0 --port ${port}"
    fi
    presentation::info "  3. Файлы / Files:"
    if [[ "${svc}" != "2" ]]; then
        presentation::info "     /etc/systemd/system/${service}.service   # юнит / unit"
        if is::not_empty "${ai_pass}"; then
            presentation::info "     ${env_file}  # пароль root:600 / password"
        fi
    fi
    if (( ${#sudo_lines[@]} > 0 )); then
        presentation::info "     ${sudoers_file}  # sudo-права / sudo rules"
    fi
    presentation::info "     ${limits_file}  # лимиты / limits"
    presentation::info "  4. Файрвол (если нужно) / Firewall (if needed):"
    presentation::info "     sudo firewall-cmd --add-port=${port}/tcp --permanent && sudo firewall-cmd --reload"
    presentation::info "  5. Выданные права / Granted rules: sudo -l -U ${ai_user}"
    presentation::warning "Повторный запуск визарда перезапишет файлы и сгенерирует новый пароль / re-running the wizard rewrites files and generates a new password"
    presentation::info "Журнал / Log: ${STEPLOG_FILE}"
}

main "$@"