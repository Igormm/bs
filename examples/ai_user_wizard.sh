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

# Запуск / Run:
#   sudo bs run examples/ai_user_wizard.sh
#   sudo ./examples/ai_user_wizard.sh

load "lib/ui/presentation"

# ==========================================
# Wizard engine / Движок визарда
# ==========================================

# @private Restore the terminal on any exit (panic-safe).
# @private Восстановить терминал при любом выходе.
wiz::__restore() {
    printf '\033[?25h\033[0m\033[?1049l'
}

# @private Enter the alternate screen buffer (clean full-screen redraws).
# @private Войти в альтернативный буфер (чистая перерисовка на весь экран).
wiz::__enter_alt() {
    printf '\033[?1049h\033[?25l\033[2J'
}

# @private Terminal width from the real tty (ioctl), clamped to the box range.
# @private Ширина терминала из реального tty (ioctl), ограничена диапазоном рамки.
wiz::__box_width() {
    local -i tw=80
    local size
    if is::command stty && size="$(stty size 2>/dev/null)"; then
        tw="${size##* }"
    elif is::command tput; then
        tw="$(tput cols 2>/dev/null || printf 80)"
    fi
    (( tw = tw - 4 ))
    (( tw < 44 )) && tw=44
    (( tw > 76 )) && tw=76
    printf '%d' "${tw}"
}

# @private Frame column (0-based) and terminal size (lines, cols).
# @private Столбец рамки (с 0) и размер терминала (строки, колонки).
declare -g __WIZ_COL=0 __WIZ_LINES=24 __WIZ_COLS=80

wiz::__term_size() {
    local size
    __WIZ_LINES=24
    __WIZ_COLS=80
    if is::command stty && size="$(stty size 2>/dev/null)"; then
        __WIZ_LINES="${size%% *}"
        __WIZ_COLS="${size##* }"
    elif is::command tput; then
        __WIZ_COLS="$(tput cols 2>/dev/null || printf 80)"
        __WIZ_LINES="$(tput lines 2>/dev/null || printf 24)"
    fi
}

# @private Clear and position the cursor at the center of a frame.
# @private Очистить экран и поставить курсор в центр рамки.
# @param $1 Frame width / Ширина рамки
# @param $2 Frame height / Высота рамки
wiz::__frame_begin() {
    local -r width="$1" height="$2"
    wiz::__term_size
    (( __WIZ_COL = (__WIZ_COLS - width) / 2 ))
    (( __WIZ_COL < 0 )) && __WIZ_COL=0
    local -i row=$(( (__WIZ_LINES - height) / 2 ))
    (( row < 0 )) && row=0
    printf '\033[2J\033[%d;%dH' "$((row + 1))" "$((__WIZ_COL + 1))"
}

# @private Display width of a string (wide chars count as 2 cells).
#   Pure bash: ${#var} counts UTF-8 CHARACTERS (not bytes) with no fork at
#   all — the earlier wc -m version still forked once per row, and the
#   original per-char `printf|wc -c` loop forked per character (~5-15 ms
#   per row). Box glyphs (▶ ○ ● ✓ ╭ ╰) are 3-byte, 1-cell chars, so
#   chars == cells. Wide East-Asian chars would need a table lookup.
# @private Ширина строки на экране (широкие символы — 2 клетки).
#   Чистый bash: ${#var} считает UTF-8 СИМВОЛЫ (не байты) вообще без
#   форков — wc -m всё ещё форкал раз на строку, а исходный цикл
#   `printf|wc -c` — на каждый символ (~5-15 мс на строку). Символы рамки
#   (▶ ○ ● ✓ ╭ ╰) — 3-байтные, 1 клетка: символы == клетки.
wiz::__disp_width() {
    printf '%d' "${#1}"
}

# @private Frame rule: ╭────╮ / ├────┤ / ╰────╯
# @private Линия рамки: ╭────╮ / ├────┤ / ╰────╯
wiz::__rule() {
    local -r inner="$1" left="$2" right="$3"
    local line
    printf -v line '%*s' "${inner}" ''
    printf '\033[%dG\033[34m%s%s%s\033[0m\n' "$((__WIZ_COL + 1))" "${left}" "${line// /─}" "${right}"
}

# @private Frame row with padding (ANSI-aware width). Content longer than the
#   inner width is truncated with "…" so the frame never breaks.
# @private Строка рамки с паддингом (ширина с учётом ANSI). Контент длиннее
#   внутренней ширины обрезается с "…" — рамка никогда не рвётся.
# @param $1 Inner width, $2 Content, $3 [optional] ANSI color code
wiz::__row() {
    local -r inner="$1" content="$2" color="${3:-}"
    local text="${content}"
    if (( ${#text} > inner )); then
        # Truncate by char count (chars == cells for box glyphs).
        # Обрезаем по числу символов (символы == клетки для глифов рамки).
        text="${text:0:$((inner - 1))}…"
    fi
    # One printf per row: frame edges, optional color, padding.
    # Один printf на строку: края рамки, опциональный цвет, паддинг.
    if is::not_empty "${color}"; then
        printf '\033[%dG\033[34m│\033[0m\033[%sm%s\033[0m%*s\033[34m│\033[0m\n' \
            "$((__WIZ_COL + 1))" "${color}" "${text}" "$((inner - ${#text}))" ''
    else
        printf '\033[%dG\033[34m│\033[0m%s%*s\033[34m│\033[0m\n' \
            "$((__WIZ_COL + 1))" "${text}" "$((inner - ${#text}))" ''
    fi
}

# @private Multi-line text inside a frame.
# @private Многострочный текст внутри рамки.
wiz::__text() {
    local -r inner="$1"
    local line
    while IFS= read -r line; do
        wiz::__row "${inner}" "${line}"
    done <<< "${2}"
}

# @private Green title row.
# @private Строка-заголовок зелёным.
wiz::__title_row() {
    local -r inner="$1" title="$2"
    wiz::__row "${inner}" "${title}" "1;32"
}

# @private Dim hint row.
# @private Затемнённая подсказка.
wiz::__hint() {
    wiz::__row "$1" "$2" "90"
}

# @private Read one key, decoding arrows + digits + q.
# @private Прочитать клавишу: стрелки + цифры + q.
# @stdout up|down|enter|space|q|1..9|other
wiz::__read_key() {
    local key
    IFS= read -rsn1 key
    if [[ "${key}" == $'\e' ]]; then
        local seq
        IFS= read -rsn2 -t 0.1 seq || true
        case "${seq}" in
            '[A') printf 'up' ;;
            '[B') printf 'down' ;;
            *) printf 'esc' ;;
        esac
        return
    fi
    case "${key}" in
        '') printf 'enter' ;;
        ' ') printf 'space' ;;
        q|Q) printf 'q' ;;
        [1-9]) printf '%s' "${key}" ;;
        *) printf '%s' "${key}" ;;
    esac
}

# @description Single-choice menu with arrows, digits 1-9, q to cancel.
# @description Меню с одним выбором: стрелки, цифры 1-9, q — отмена.
# @param $1 Output variable: selected index (0-based), 99 = cancelled
# @param $2 Title / Заголовок
# @param $@ Items / Пункты
wiz::menu() {
    local -n __wiz_out="${1:?output variable required}"
    local -r title="${2:?title required}"
    shift 2
    local -a items=("$@")
    local -r inner="$(wiz::__box_width)"

    local selected=0
    while true; do
        wiz::__frame_begin $((inner + 2)) $(( ${#items[@]} + 5 ))
        wiz::__rule "${inner}" '╭' '╮'
        wiz::__title_row "${inner}" "${title}"
        wiz::__rule "${inner}" '├' '┤'
        for i in "${!items[@]}"; do
            if (( i == selected )); then
                wiz::__row "${inner}" "  ▶ ${items[i]}" "36"
            else
                wiz::__row "${inner}" "    ${items[i]}"
            fi
        done
        wiz::__rule "${inner}" '╰' '╯'
        wiz::__hint "${inner}" "  ↑/↓, 1-9 — выбор, Enter — OK, q — отмена"

        local key
        key="$(wiz::__read_key)"
        case "${key}" in
            up)   selected=$(( (selected - 1 + ${#items[@]}) % ${#items[@]} )) ;;
            down) selected=$(( (selected + 1) % ${#items[@]} )) ;;
            enter) break ;;
            q)    __wiz_out=99; return 0 ;;
            [1-9])
                if (( key >= 1 && key <= ${#items[@]} )); then
                    __wiz_out=$((key - 1)); return 0
                fi
                ;;
        esac
    done

    __wiz_out=${selected}
}

# @description Multi-choice menu (checkboxes): Space toggles, Enter confirms.
# @description Меню множественного выбора (чекбоксы): Space — выбор, Enter — ОК.
# @param $1 Output variable: indices joined by space, "q" = cancelled
# @param $2 Title / Заголовок
# @param $@ Items / Пункты
wiz::multi_menu() {
    local -n __wiz_out="${1:?output variable required}"
    local -r title="${2:?title required}"
    shift 2
    local -a items=("$@")
    local -a checked=()
    local i
    for i in "${!items[@]}"; do checked+=(0); done
    local -r inner="$(wiz::__box_width)"

    local selected=0
    while true; do
        wiz::__frame_begin $((inner + 2)) $(( ${#items[@]} + 5 ))
        wiz::__rule "${inner}" '╭' '╮'
        wiz::__title_row "${inner}" "${title}"
        wiz::__rule "${inner}" '├' '┤'
        for i in "${!items[@]}"; do
            local mark='○'
            (( checked[i] == 1 )) && mark='●'
            if (( i == selected )); then
                wiz::__row "${inner}" "  ${mark} ${items[i]}" "36"
            else
                wiz::__row "${inner}" "  ${mark} ${items[i]}"
            fi
        done
        wiz::__rule "${inner}" '╰' '╯'
        wiz::__hint "${inner}" "  ↑/↓ — ход, Space — выбор, Enter — ОК, q — отмена"

        case "$(wiz::__read_key)" in
            up)    selected=$(( (selected - 1 + ${#items[@]}) % ${#items[@]} )) ;;
            down)  selected=$(( (selected + 1) % ${#items[@]} )) ;;
            space) checked[selected]=$(( 1 - checked[selected] )) ;;
            enter) break ;;
            q)     __wiz_out="q"; return 0 ;;
        esac
    done

    local -a picked_idx=()
    for i in "${!items[@]}"; do
        (( checked[i] == 1 )) && picked_idx+=("${i}")
    done
    __wiz_out="${picked_idx[*]:-}"
}

# @description Yes/No question inside a frame.
# @description Вопрос Да/Нет в рамке.
# @param $1 Output variable: y|n|q
# @param $2 Question / Вопрос
wiz::yn() {
    local -n __wiz_out="${1:?output variable required}"
    local -r question="$2"
    local -r inner="$(wiz::__box_width)"

    while true; do
        wiz::__frame_begin $((inner + 2)) 6
        wiz::__rule "${inner}" '╭' '╮'
        wiz::__title_row "${inner}" "${question}"
        wiz::__row "${inner}" "    Да / Yes"
        wiz::__row "${inner}" "    Нет / No"
        wiz::__rule "${inner}" '╰' '╯'
        wiz::__hint "${inner}" "  y/n или 1/2 — ответ, q — отмена"

        case "$(wiz::__read_key)" in
            y|Y|1) __wiz_out="y"; return 0 ;;
            n|N|2) __wiz_out="n"; return 0 ;;
            q)     __wiz_out="q"; return 0 ;;
        esac
    done
}

# @description Text input with a default value.
# @description Текстовый ввод со значением по умолчанию.
# @param $1 Output variable / Выходная переменная
# @param $2 Prompt / Приглашение
# @param $3 Default / Значение по умолчанию
wiz::ask_input() {
    local -n __wiz_out="${1:?output variable required}"
    local -r prompt="$2" default="${3:-}"
    local -r inner="$(wiz::__box_width)"
    local answer

    wiz::__frame_begin $((inner + 2)) 8
    wiz::__rule "${inner}" '╭' '╮'
    wiz::__title_row "${inner}" "${prompt}"
    wiz::__row "${inner}" ""
    wiz::__row "${inner}" "  Введите / Enter [${default}]: " "33"
    wiz::__row "${inner}" ""
    # строка ввода — внутри рамки, до нижней границы / input line inside the frame
    printf '\033[%dG\033[34m│\033[0m \033[33m' "$((__WIZ_COL + 1))"
    IFS= read -r answer || true
    printf '\033[0m\n'
    wiz::__row "${inner}" "  Enter — принять по умолчанию · q — отмена" "90"
    wiz::__rule "${inner}" '╰' '╯' 

    case "${answer}" in
        q|Q) __wiz_out="q" ;;
        '')  __wiz_out="${default}" ;;
        *)   __wiz_out="${answer}" ;;
    esac
}

# @description Hidden password input with confirmation (retries until match).
# @description Скрытый ввод пароля с подтверждением (до совпадения).
# @param $1 Output variable / Выходная переменная
wiz::ask_pass() {
    local -n __wiz_out="${1:?output variable required}"
    local -r inner="$(wiz::__box_width)"
    local pass1 pass2

    while true; do
        wiz::__frame_begin $((inner + 2)) 9
        wiz::__rule "${inner}" '╭' '╮'
        wiz::__title_row "${inner}" "Пароль сервера / Server password"
        wiz::__row "${inner}" ""
        wiz::__hint "${inner}" "  Ввод скрыт / Input is hidden"
        wiz::__row "${inner}" ""
        printf '\033[%dG\033[34m│\033[0m \033[33m' "$((__WIZ_COL + 1))"
        IFS= read -rs pass1 || true
        printf '\033[0m\n'
        printf '\033[%dG\033[34m│\033[0m \033[33m' "$((__WIZ_COL + 1))"
        IFS= read -rs -p '  Повторите / Repeat: ' pass2 || true
        printf '\033[0m\n'
        wiz::__rule "${inner}" '╰' '╯' 

        if [[ "${pass1}" == "${pass2}" && -n "${pass1}" ]]; then
            __wiz_out="${pass1}"
            return 0
        fi
        if is::empty "${pass1}"; then
            __wiz_out=""
            return 0
        fi
        wiz::__row "${inner}" "  Пароли не совпали / Passwords do not match" "31"
        wiz::__row "${inner}" "  Enter — повторить / to retry" "90"
        IFS= read -rsn1 || true
    done
}

# ==========================================
# @private Generate a password / Сгенерировать пароль
# @stdout password / пароль
wiz::gen_pass() {
    if is::command openssl; then
        openssl rand -base64 18 | tr '+/' '_-'
    else
        tr -dc 'A-Za-z0-9_-' < /dev/urandom | head -c 18
        printf '\n'
    fi
}

# Progress indicators / Индикаторы прогресса
# ==========================================

step_go() { printf '  \033[36m▶\033[0m %s\n' "$1"; }
step_ok() { printf '  \033[32m✓\033[0m %s\n' "$1"; }

# ==========================================
# Application logic / Логика применения
# ==========================================

# @private Abort with a framed error.
# @private Прервать с ошибкой в рамке.
wiz::fail() {
    local -r inner="$(wiz::__box_width)" msg="$1"
    local -i msg_lines=0
    while IFS= read -r _; do msg_lines=$((msg_lines + 1)); done <<< "${msg}"
    wiz::__frame_begin $((inner + 2)) $((msg_lines + 4))
    wiz::__rule "${inner}" '╭' '╮'
    wiz::__title_row "${inner}" "Ошибка / Error"
    wiz::__text "${inner}" "${msg}"
    wiz::__rule "${inner}" '╰' '╯'
    exit 1
}

main() {
    # -h/--help: справка без запуска визарда / usage without starting the wizard
    case "${1:-}" in
        -h|--help)
            printf 'Usage: sudo bs run examples/ai_user_wizard.sh\n'
            printf '       sudo ./examples/ai_user_wizard.sh\n\n'
            printf 'Создаёт ограниченного системного пользователя для ИИ-агента (opencode):\n'
            printf 'заблокированный вход, точечные sudoers, лимиты ресурсов, песочница systemd.\n'
            printf 'Creates a restricted system user for an AI agent (opencode): locked\n'
            printf 'login, scoped sudoers, resource limits, optional systemd sandbox.\n\n'
            printf 'Шаги визарда / Wizard steps (все параметры — с дефолтом):\n'
            printf '  1. Имя пользователя / Username        (default: ai-agent)\n'
            printf '  2. Порт сервера / Server port          (default: 4096)\n'
            printf '  3. Пароль / Password                   сгенерировать / ввести свой / без пароля\n'
            printf '  4. systemd-сервис / Service            создать+запустить / только создать / не создавать\n'
            printf '  5. Усиление / Hardening                sudo для сервиса+firewall, песочница, SELinux\n'
            printf '  6. Сводка / Summary → подтверждение → применение\n\n'
            printf 'Что делает / What it does:\n'
            printf '  • useradd -m -s /usr/sbin/nologin + passwd -l (вход по паролю запрещён)\n'
            printf '  • /srv/<user> с правами пользователя; лимиты nproc=128 nofile=4096 core=0\n'
            printf '  • sudoers (по выбору): systemctl сервиса + firewall-cmd\n'
            printf '  • systemd-unit opencode serve (порт из шага 2), пароль в env root:600\n'
            printf '  • песочница unit (ProtectSystem/PrivateTmp) и SELinux-контекст — по выбору\n\n'
            printf 'Клавиши / Keys: ↑/↓, 1-9 — выбор · Space — отметить · Enter — OK · q — отмена\n'
            exit 0
            ;;
    esac

    signal::on EXIT wiz::__restore
    signal::on INT wiz::__restore

    # ---- root check / проверка прав
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        wiz::fail "Требуются права root / Root required.
  Запустите: sudo bs run examples/ai_user_wizard.sh
  Run:        sudo bs run examples/ai_user_wizard.sh"
    fi

    wiz::__enter_alt
    local -r inner="$(wiz::__box_width)"

    # ---- 1-2. пользователь и порт / user and port
    local ai_user service port
    wiz::ask_input ai_user "1/6 — Имя пользователя / Username" "ai-agent"
    [[ "${ai_user}" == "q" ]] && exit 0
    service="${ai_user}"   # сервис называется как пользователь / service named after the user
    wiz::ask_input port "2/6 — Порт сервера / Server port" "4096"
    [[ "${port}" == "q" ]] && exit 0
    [[ "${port}" =~ ^[0-9]+$ ]] || wiz::fail "Порт должен быть числом / Port must be a number: ${port}"
    (( port >= 1 && port <= 65535 )) || wiz::fail "Порт вне диапазона 1-65535 / Port out of range 1-65535: ${port}"

    # ---- 3. пароль / password
    local pass_mode ai_pass=""
    wiz::menu pass_mode "3/6 — Пароль сервера / Server password" \
        "Сгенерировать / Generate" \
        "Ввести свой / Enter my own" \
        "Без пароля / No password"
    [[ "${pass_mode}" == "99" ]] && exit 0
    case "${pass_mode}" in
        0) ai_pass="$(wiz::gen_pass)" ;;
        1) wiz::ask_pass ai_pass; [[ "${ai_pass}" == "q" ]] && exit 0 ;;
        2) ai_pass="" ;;
    esac

    # ---- 4. systemd-сервис / service
    local svc
    wiz::menu svc "4/6 — systemd-сервис / systemd service" \
        "Создать и запустить / Create and start" \
        "Только создать / Create only" \
        "Не создавать / Do not create"
    [[ "${svc}" == "99" ]] && exit 0

    # ---- 5. усиление / hardening (checkboxes)
    local hard_pick
    wiz::multi_menu hard_pick "5/6 — Усиление / Hardening" \
        "sudo: управление сервисом + firewall-cmd" \
        "Песочница systemd / systemd sandbox" \
        "SELinux-контекст / SELinux context"
    [[ "${hard_pick}" == "q" ]] && exit 0
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

    # ---- сводка / summary
    local summary
    printf -v summary "%s\n" \
        "Пользователь / User:  ${ai_user}" \
        "Сервис / Service:     ${service}  (порт ${port})" \
        "Пароль:               $([[ -n "${ai_pass}" ]] && echo 'сгенерирован / generated' || echo 'без пароля / none')" \
        "sudo-команд:          ${#sudo_lines[@]}" \
        "Лимиты:               nproc=${nproc}, nofile=${nofile}, core=0" \
        "Песочница:            $([[ ${want_sandbox} == 1 ]] && echo 'да / yes' || echo 'нет / no')   SELinux: $([[ ${want_selinux} == 1 ]] && echo 'да / yes' || echo 'нет / no')" \
        "systemd-сервис:       $(case ${svc} in 0) echo 'создать+запустить';; 1) echo 'только создать';; 2) echo 'не создавать';; esac)"
    local -i sum_lines=0
    while IFS= read -r _; do sum_lines=$((sum_lines + 1)); done <<< "${summary}"
    wiz::__frame_begin $((inner + 2)) $((sum_lines + 4))
    wiz::__rule "${inner}" '╭' '╮'
    wiz::__title_row "${inner}" "Сводка / SUMMARY"
    wiz::__rule "${inner}" '├' '┤'
    wiz::__text "${inner}" "${summary}"
    wiz::__rule "${inner}" '╰' '╯'
    printf '\n'
    local apply
    wiz::yn apply "Применить настройки? / Apply settings?"
    [[ "${apply}" == "q" ]] && exit 0
    if [[ "${apply}" != "y" ]]; then
        wiz::fail "Отменено пользователем / Cancelled by user"
    fi

    # ==========================================
    # ---- применение / apply
    # ==========================================
    local -r w="$(wiz::__box_width)"
    wiz::__frame_begin $((w + 2)) 3
    wiz::__rule "${w}" '╭' '╮'
    wiz::__title_row "${w}" "Применение / APPLYING"
    wiz::__rule "${w}" '╰' '╯'
    printf '\n'

    # passwd -l только для СОЗДАННОГО пользователя: блокировка пароля
    # существующего реального пользователя = потеря доступа (Thompson:
    # не трогай состояние, которое не создавал).
    # passwd -l only for a user WE created: locking an existing real
    # user's password is access loss (Thompson: never touch state you
    # didn't create).
    local user_existed=0
    if ! id "${ai_user}" >/dev/null 2>&1; then
        step_go "useradd -m -s /usr/sbin/nologin ${ai_user}"
        useradd -m -s /usr/sbin/nologin "${ai_user}"
        step_ok "пользователь создан / user created"
    else
        user_existed=1
        step_ok "пользователь существует / user exists"
    fi

    if (( user_existed == 1 )); then
        step_go "ПРЕДУПРЕЖДЕНИЕ: ${ai_user} уже существует — вход НЕ блокируем / login NOT locked"
        step_ok "существующий пользователь оставлен как есть / existing user left untouched"
    else
        step_go "passwd -l ${ai_user}  (вход по паролю запрещён / password login locked)"
        passwd -l "${ai_user}"
        step_ok "пароль заблокирован / password locked"
    fi

    step_go "usermod -aG systemd-journal ${ai_user}"
    usermod -aG systemd-journal "${ai_user}"
    step_ok "journal-группа / journal group"

    mkdir -p "/srv/${ai_user}" && chown "${ai_user}":"${ai_user}" "/srv/${ai_user}"
    step_ok "/srv/${ai_user} готов / ready"

    # ---- sudoers / sudo-права
    local sudoers_file="/etc/sudoers.d/${ai_user}"
    if (( ${#sudo_lines[@]} > 0 )); then
        step_go "запись sudoers / writing ${sudoers_file}"
        {
            printf '# Managed by ai_user_wizard / создано визардом\n'
            local line
            for line in "${sudo_lines[@]}"; do
                printf '%s ALL=(root) NOPASSWD: %s\n' "${ai_user}" "${line}"
            done
        } > "${sudoers_file}"
        chmod 440 "${sudoers_file}"
        visudo -c -f "${sudoers_file}" || { rm -f "${sudoers_file}"; wiz::fail "visudo -c не прошёл / failed — файл откачен / reverted"; }
        step_ok "sudoers записан и проверен / written and verified"
    else
        rm -f "${sudoers_file}"
        step_ok "sudoers не требуется / no sudoers needed"
    fi

    # ---- лимиты / limits (фиксированные средние / fixed medium defaults)
    local limits_file="/etc/security/limits.d/${ai_user}.conf"
    step_go "запись лимитов / writing ${limits_file}"
        cat > "${limits_file}" <<EOF
# Managed by ai_user_wizard / создано визардом
${ai_user} soft nproc ${nproc}
${ai_user} hard nproc ${nproc}
${ai_user} soft nofile ${nofile}
${ai_user} hard nofile ${nofile}
${ai_user} hard core 0
${ai_user} soft core 0
EOF
    step_ok "лимиты записаны / limits written"

    # ---- systemd-сервис / service unit
    if [[ "${svc}" != "2" ]]; then
        if is::empty "${opencode_bin}"; then
            wiz::fail "opencode не найден в PATH / opencode not found in PATH — сервис не создан / service not created"
        fi
        step_go "запись unit / writing /etc/systemd/system/${service}.service"
        local env_file="/srv/${ai_user}/opencode.env"
        if is::not_empty "${ai_pass}"; then
            # umask в subshell: не меняет umask остального скрипта
            # (Thompson: состояние не должно протекать).
            # umask inside a subshell so it never leaks into the rest
            # of the script (Thompson: no state leakage).
            (
                umask 177
                printf 'OPENCODE_SERVER_PASSWORD=%s\n' "${ai_pass}" > "${env_file}"
            )
            chown root:root "${env_file}"
            chmod 600 "${env_file}"
            step_ok "пароль в ${env_file} (root:root 600)"
        else
            rm -f "${env_file}"
        fi

        {
            printf '[Unit]\n'
            printf 'Description=opencode server for %s\n' "${ai_user}"
            printf 'After=network.target\n\n'
            printf '[Service]\n'
            printf 'User=%s\n' "${ai_user}"
            printf 'Group=%s\n' "${ai_user}"
            printf 'WorkingDirectory=/srv/%s\n' "${ai_user}"
            if is::not_empty "${ai_pass}"; then
                printf 'EnvironmentFile=%s\n' "${env_file}"
            fi
            printf 'ExecStart=%s serve --hostname 0.0.0.0 --port %s\n' "${opencode_bin}" "${port}"
            printf 'Restart=always\n'
            if (( want_sandbox == 1 )); then
                printf '\n'
                printf '# Песочница / Sandbox\n'
                printf 'ProtectSystem=strict\n'
                printf 'ProtectHome=read-only\n'
                printf 'ReadWritePaths=/srv/%s /home/%s\n' "${ai_user}" "${ai_user}"
                printf 'PrivateTmp=true\n'
                printf 'LimitNOFILE=%s\n' "${nofile}"
            fi
        } > "/etc/systemd/system/${service}.service"
        step_ok "unit записан / unit written"

        systemctl daemon-reload
        if [[ "${svc}" == "0" ]]; then
            systemctl enable --now "${service}"
            step_ok "сервис запущен / service started"
        else
            step_ok "сервис создан, не запущен / created, not started"
        fi
    else
        step_ok "сервис не создаётся / service skipped"
    fi

    # ---- SELinux / контекст
    if (( want_selinux == 1 )); then
        step_go "SELinux: fcontext + restorecon"
        if command -v semanage >/dev/null 2>&1; then
            semanage fcontext -a -t httpd_sys_rw_content_t "/srv/${ai_user}(/.*)?"
            restorecon -Rv "/srv/${ai_user}"
            step_ok "контекст применён / context applied"
        else
            step_go "semanage не найден — пропуск / not found, skipped"
        fi
    else
        step_ok "SELinux не трогаем / SELinux untouched"
    fi

    # ==========================================
    # ---- итог / final summary
    # ==========================================
    printf '\n\n'
    local final
    if is::not_empty "${ai_pass}"; then
        # Пароль показываем ОДИН раз в конце (Jobs: клиент должен мочь
        # завершить сценарий; дальше он живёт только в env-файле root:600).
        # Show the password ONCE at the end (Jobs: the customer must be
        # able to finish the scenario; after this it lives only in the
        # root:600 env file).
        printf -v final "%s\n" \
            "Готово! / Done!" \
            "" \
            "Пользователь / User:  ${ai_user} (вход запрещён / login locked)" \
            "Каталог / Dir:        /srv/${ai_user}" \
            "" \
            "ПАРОЛЬ СЕРВЕРА / SERVER PASSWORD (показывается один раз / one-time):" \
            "  ${ai_pass}" \
            "  (также в /srv/${ai_user}/opencode.env, root:600)" \
            "" \
            "sudo:                 sudo -l -U ${ai_user}" \
            "" \
            "Контроль сервиса / Service control:" \
            "  sudo systemctl status ${service}" \
            "  sudo systemctl restart ${service}" \
            "  sudo firewall-cmd --add-port=${port}/tcp --permanent && sudo firewall-cmd --reload" \
            "" \
            "Подключение / Connect: opencode attach http://<ip>:${port} -u opencode -p '${ai_pass}'"
    else
        printf -v final "%s\n" \
            "Готово! / Done!" \
            "" \
            "Пользователь / User:  ${ai_user} (вход запрещён / login locked)" \
            "Каталог / Dir:        /srv/${ai_user}" \
            "" \
            "sudo:                 sudo -l -U ${ai_user}" \
            "" \
            "Контроль сервиса / Service control:" \
            "  sudo systemctl status ${service}" \
            "  sudo systemctl restart ${service}" \
            "  sudo firewall-cmd --add-port=${port}/tcp --permanent && sudo firewall-cmd --reload" \
            "" \
            "Подключение / Connect: opencode attach http://<ip>:${port}"
    fi
    local -i fin_lines=0
    while IFS= read -r _; do fin_lines=$((fin_lines + 1)); done <<< "${final}"
    wiz::__frame_begin $((w + 2)) $((fin_lines + 4))
    wiz::__rule "${w}" '╭' '╮'
    wiz::__title_row "${w}" "ИТОГ / RESULT"
    wiz::__rule "${w}" '├' '┤'
    wiz::__text "${w}" "${final}"
    wiz::__rule "${w}" '╰' '╯'
    printf '\n'
}

main "$@"