#!/usr/bin/env bs
# shellcheck shell=bash
# @shell bash4,zsh — нужны конструкции bash (массивы, [[ ]], declare -A,
#   namerefs нет); тот же код исполняется в zsh после setopt KSH_ARRAYS
#   SH_WORD_SPLIT no_nomatch (см. шорткат ниже) / needs bash constructs
#   (arrays, [[ ]], declare -A; no namerefs); the same code runs under zsh
#   after setopt KSH_ARRAYS SH_WORD_SPLIT no_nomatch (shim below)
# examples/dripfetch.sh — настраиваемый терминальный дашборд с «матричным»
#   дождём и боксами: logo, sysinfo, clock, calendar, weather, net, text
# examples/dripfetch.sh — a custom terminal dashboard with a "matrix" rain and
#   boxes: logo, sysinfo, clock, calendar, weather, net, text
#
# Работает в bash 4.2+ и zsh (ярус @shell bash4,zsh) / Runs on bash 4.2+ and
#   zsh (the @shell bash4,zsh tier). Матричный дождь + рамки, позиции боксов
#   сохраняются в <config-dir>/positions.conf / matrix rain + borders; box
#   positions persist to <config-dir>/positions.conf.
#
# Запуск / Run:
#   ./bs run examples/dripfetch.sh          # через bs (bash) / via bs (bash)
#   ./examples/dripfetch.sh                 # шебанг bs / bs shebang
#   zsh examples/dripfetch.sh               # напрямую в zsh / directly in zsh
#
# Клавиши / Keys:
#   q             выход / quit
#   Space         пауза дождя / pause the rain
#   Tab           выбрать бокс / select box
#   Стрелки/WASD  двигать бокс (позиция сохраняется) / move box (saved)
#   Esc           снять выделение / deselect
#
# CLI: -c N|NAME|PATH · --set-config · --list-configs|logos|boxes · --print-logo
#   · --config-path · --init-config · -v · -h
#
# Честные упрощения против оригинального dripfetch (Python) / Honest
#   simplifications vs the original dripfetch (Python): небольшой набор
#   логотипов вместо 487; под-парсер YAML только под документированную плоскую
#   схему (без yq); позиции боксов — в positions.conf, а не в YAML;
#   rain.speeds/effects распознаются, но визуально упрощены.
#
# Примечание: строгий режим (set -euo pipefail) не включён намеренно — это
#   интерактивное TUI, здесь только set -u / Note: strict mode is off on
#   purpose — this is an interactive TUI, only set -u here.

# Ярус bash4,zsh / bash4,zsh tier: в zsh делаем массивы 0-индексными и
# включаем word-splitting как в bash/bash4 (иначе ${#a[@]} и x=( $v ) разъедутся)
# In zsh make arrays 0-based and enable bash-like word splitting (else
# ${#a[@]} and x=( $v ) misbehave). No-op under bash (ZSH_VERSION is unset).
if [[ -n "${ZSH_VERSION:-}" ]]; then
    setopt KSH_ARRAYS SH_WORD_SPLIT no_nomatch
fi

# Ядровые идиомы тишины / kernel "quiet" idioms. Под bs ядро даёт utils::*;
# при прямом запуске (`zsh examples/dripfetch.sh`) их нет — лёгкий фолбэк, чтобы
# файл работал обоими способами и в нём не было разбросанных `>/dev/null`.
# Under bs the kernel provides utils::*; a raw `zsh examples/dripfetch.sh` has
# none — a lightweight fallback so this file works both ways with no scattered
# raw `>/dev/null` of its own.
if ! type utils::has >/dev/null 2>&1; then
    utils::has()       { command -v "${1:-}" >/dev/null 2>&1; }
    utils::quiet()     { "$@" >/dev/null 2>&1; }
    utils::quiet_err() { "$@" 2>/dev/null; }
    utils::ignore()    { "$@" >/dev/null 2>&1 || :; }
    utils::attempt()   { "$@" 2>/dev/null || :; }
fi

set -u

readonly VERSION="0.5.0-bash"
readonly CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/dripfetch"
readonly CONFIG_FILE="$CONFIG_DIR/config.yaml"
readonly POS_FILE="$CONFIG_DIR/positions.conf"

# --- ANSI / colour primitives ---------------------------------------------------
ESC=$'\033'
RESET="${ESC}[0m"
REVERSE="${ESC}[7m"
BOLD="${ESC}[1m"
declare -i EMIT_TRUECOLOR=0

dripfetch::detect_colour() {
    case "${COLORTERM:-}" in
        *24bit*|*truecolor*|*truecolour*) EMIT_TRUECOLOR=1; return ;;
    esac
    case "${TERM:-}" in
        xterm-kitty|alacritty*|wezterm*|foot*|ghostty*|*kitty*) EMIT_TRUECOLOR=1; return ;;
    esac
    if [[ "${TERM:-}" == *256color* ]]; then EMIT_TRUECOLOR=1
    else EMIT_TRUECOLOR=0; fi
}

dripfetch::hex2rgb() { # "#RRGGBB" -> "r g b" (fallback grey)
    local h="${1#\#}"
    case ${#h} in
        3) h="${h:0:1}${h:0:1}${h:1:1}${h:1:1}${h:2:1}${h:2:1}" ;;
        8) h="${h:0:6}" ;;
        6) : ;;
        *) printf '128 128 128'; return ;;
    esac
    printf '%d %d %d' $((16#${h:0:2})) $((16#${h:2:2})) $((16#${h:4:2}))
}

dripfetch::rgb256() { printf '%d' $(( 16 + 36*(($1*5)/255) + 6*(($2*5)/255) + (($3*5)/255) )); }

# fg / bg emit helpers append raw ANSI to the global OUT buffer.
dripfetch::fgb() { local r=$1 g=$2 b=$3
    if (( EMIT_TRUECOLOR )); then OUT+="$(printf '%s[38;2;%d;%d;%dm' "$ESC" "$r" "$g" "$b")"
    else OUT+="$(printf '%s[38;5;%dm' "$ESC" "$(dripfetch::rgb256 "$r" "$g" "$b")")"; fi; }
dripfetch::bgb() { local r=$1 g=$2 b=$3
    if (( EMIT_TRUECOLOR )); then OUT+="$(printf '%s[48;2;%d;%d;%dm' "$ESC" "$r" "$g" "$b")"
    else OUT+="$(printf '%s[48;5;%dm' "$ESC" "$(dripfetch::rgb256 "$r" "$g" "$b")")"; fi; }

# palette arrays (r g b)
declare -a C_BORDER C_TEXT C_ACCENT C_BG
declare -i BG_SET=0
dripfetch::set_colour() { case "$1" in
        border) C_BORDER=( "$2" "$3" "$4" ) ;;
        text)   C_TEXT=( "$2" "$3" "$4" ) ;;
        accent) C_ACCENT=( "$2" "$3" "$4" ) ;;
        bg)     C_BG=( "$2" "$3" "$4" ); BG_SET=1 ;;
    esac; }

# --- terminal control -----------------------------------------------------------
TERM_W=0; TERM_H=0
ORIG_STTY=""

dripfetch::get_size() {
    local s
    if s=$(utils::quiet_err stty size) && [[ -n "$s" ]]; then
        TERM_H=${s%% *}; TERM_W=${s##* }
    else
        TERM_H=${LINES:-24}; TERM_W=${COLUMNS:-80}
    fi
    (( TERM_W < 20 )) && TERM_W=80
    (( TERM_H < 8 ))  && TERM_H=24
}

dripfetch::term_init() {
    ORIG_STTY=$(utils::attempt stty -g)
    utils::attempt stty -echo -icanon
    printf '%b' "${ESC}[?25l" "${ESC}[?1049h" "${ESC}[2J"
}
TERM_ACTIVE=0
dripfetch::term_restore() {
    [[ "$TERM_ACTIVE" -eq 1 ]] || return 0
    printf '%b' "${ESC}[?1049l" "${ESC}[?25h" "$RESET"
    if [[ -n "$ORIG_STTY" ]]; then utils::quiet_err stty "$ORIG_STTY"; else utils::quiet_err stty sane; fi || true
}

# --- config: YAML-subset flattener -------------------------------------------------
# Flattens nested scalar keys into `a.b.c=value` and `boxes.items.N.*` entries.
declare -A CFG

dripfetch::yaml_flatten() { # file -> fills CFG
    local file="$1"; CFG=()
    [ -r "$file" ] || return 1
    while IFS='=' read -r k v; do
        [[ -n "$k" ]] && CFG[$k]="$v"
    done < <(awk '
        function t(s){ gsub(/^[ \t]+|[ \t]+$/,"",s); return s }
        function join(a,n,sep,  i,o){ o=""; for(i=1;i<=n;i++){ o=o (i>1?sep:"") a[i] } return o }
        {
          line=t($0)
          if(line=="" || index(line,"#")==1) next
          ind=0
          while(substr($0,ind+1,1)==" ") ind++
          depth=int(ind/2)+1
          islist=(line=="-" || index(line,"- ")==1)
          if(islist) sub(/^-[ \t]*/,"",line)
          if(line=="") next
          if(line ~ /:$/){
            path[depth]=t(substr(line,1,length(line)-1))
            next
          }
          eq=index(line,":")
          name=(eq==0)? t(line) : t(substr(line,1,eq-1))
          val =(eq==0)? ""      : t(substr(line,eq+1))
          gsub(/^"|"$/,"",val)
          prefix=join(path,depth-1,".")
          if(islist){
            if(name=="type"){
              itemc[depth-1]++
              nn=itemc[depth-1]-1
              path[depth]=nn
              printf "%s.%d.type=%s\n", prefix, nn, val
            } else {
              nn=itemc[depth-1]-1
              if(nn<0) nn=0
              printf "%s.%d.%s=%s\n", prefix, nn, name, val
            }
            next
          }
          if(name=="") next
          if(prefix=="") printf "%s=%s\n", name, val
          else printf "%s.%s=%s\n", prefix, name, val
        }
    ' "$file")
}

dripfetch::cfg_get() { local v; v="${CFG[$1]:-}"; if [ -n "$v" ]; then echo "$v"; else echo "${2:-}"; fi; }

# --- defaults (dripfetch-like) -----------------------------------------------------
BG_HEX="#080B12"
BORDER_HEX="#50FFC1"
TEXT_HEX="#D9E5F4"
ACCENT_HEX="#50FFC1"
BORDER_STYLE="titled_single"
PAD_H=2; PAD_V=0

RAIN_INTENSITY=40
RAIN_CHARS=("│" "┃" "╎")
RAIN_COLORS=("0.7" "#21F7A8" "0.3" "#45B8FF")     # p color p color …
RAIN_SPEEDS=("0.5" "30" "0.5" "50")               # p delay-ms p delay-ms …
RAIN_LENGTHS=("0.8" "6" "0.2" "14")               # p len p len …

CLOCK_SIZE="big"; CLOCK_24H=1; CLOCK_SECONDS=1; CLOCK_AMPM=0; CLOCK_BLINK=1; CLOCK_DATE=1
CAL_START="monday"
LOGO_NAME=""
TEXT_CONTENT=""; TEXT_ALIGN="left"
WEATHER_LOC=""; WEATHER_LAT=""; WEATHER_LON=""; WEATHER_UNITS="celsius"; WEATHER_DAYS=3
NET_WIDTH=40; NET_INTERVAL=5

declare -a BOX_TYPES=( logo sysinfo clock calendar text )

# --- presets ----------------------------------------------------------------------
dripfetch::preset_apply() { # N | name
    local p="$1"
    case "$p" in
        0|default) : ;;
        1|neon_matrix|neon)      BG_HEX="#080B12"; BORDER_HEX="#50FFC1"; TEXT_HEX="#D9E5F4"; ACCENT_HEX="#50FFC1" ;;
        2|moonlight_observatory|moonlight) BG_HEX="#0B1026"; BORDER_HEX="#8E9DFF"; TEXT_HEX="#E6ECFF"; ACCENT_HEX="#FFD28F" ;;
        3|ops_console|ops)       BG_HEX="#0A0F0A"; BORDER_HEX="#4CAF50"; TEXT_HEX="#C8E6C9"; ACCENT_HEX="#FF9800" ;;
        4|citrus_pop|citrus)     BG_HEX="#141006"; BORDER_HEX="#FFD166"; TEXT_HEX="#FFF3D6"; ACCENT_HEX="#FF6B6B" ;;
        5|arcade_white|arcade)   BG_HEX="#0D0D0D"; BORDER_HEX="#ffffff"; TEXT_HEX="#eeeeee"; ACCENT_HEX="#00d8ff" ;;
        6|ink_and_amber|ink)     BG_HEX="#0A0806"; BORDER_HEX="#FFB300"; TEXT_HEX="#E8DFC8"; ACCENT_HEX="#FFB300" ;;
        7|arcade_cabinet|cabinet) BG_HEX="#0B0B14"; BORDER_HEX="#FF2E88"; TEXT_HEX="#E0E0FF"; ACCENT_HEX="#2EFFD0" ;;
        *) : ;;
    esac
}

# --- logos ------------------------------------------------------------------------
dripfetch::logo_text() { case "${1:-__auto__}" in
        arch)    printf '%s\n' '      /\' '     /  \' '    /\   \' '   /      \' '  /   ,.   \' ' /   |   |  \' '/_-''    ''-_\' ;;
        debian)  printf '%s\n' '  _____' ' /  __ \' '|  /    |' '|  \___-' '-_  /' ' /\  |' ' \ \_/' '  \__/' ;;
        ubuntu)  printf '%s\n' '         _' '     ---(_)' ' _/  ---  \\' '(_) |   |' '  \  --- _/' '     ---(_)' '        (___)' ;;
        fedora)  printf '%s\n' '     _____' '    /   __)' '    |  /  )' '    | |  |' '    | |  |' '    | |__/' '   _/  )' '  / __/' ' (__/' ;;
        nixos)   printf '%s\n' '  \\   \\ //' ' ==\\__\\/ //' '   //   \\//' '==//     //==' ' //\\___//' '// /\\  \\==' '  // \\  \\' ;;
        alpine)  printf '%s\n' '    /\\ /\\' '   /  V  \\' '  /  -o-|  \\' ' |_-_|_|  |' '  \\___/  /' '   \\___\\/' ;;
        gentoo)  printf '%s\n' '          -/oyddmdhs+:.' '      -odNMMMMMMMMNNmhy+-' '    -yNMMMMMMMMMMMNNNmmdhy+' '  /omMMMMMMMMMMMMNmdhyyyyhh:' '  /mMMMMMMMMMMMMMNdhhyyyyhh:' '  sNMMMMMMMMMMMNhmhhhhhhhhs' '  +NMMMMMMMMMMNmhyyyyyyyyys' '   +mMMMMMMMMMMmhyyyyyymy+' ;;
        opensuse) printf '%s\n' '  _______' ' /       \\' '/    __   |' '|   (__)  |' '|    __   |' ' \\  (__)  /' '  \\______/' ;;
        pop)     printf '%s\n' '______' '\\   _ \\       __' " \\  \\ \\ \\____  \\ \\" '  \\  \\_/ _  \\  \\ \\' "   \\____/\\_\\  \\  \\" '             \\__\\' ;;
        bs)      printf '%s\n' '  ____  ____' '  |  _ \/ ___|' '  | |_) \___ \' '  |  _ < ___) |' '  |_| \_\____/' ;;
        linux|__auto__|*) printf '%s\n' '        #####' '       #######' '       ##O##O##' '       # #### #' '      ## #### ##' '     #### # # ##' '    #############' '   ###############' '   ## ########## ##' '  # ##############  ##' ;;
    esac; }

dripfetch::detect_logo() {
    local id=""
    id=$(utils::quiet_err sed -n 's/^ID=//p' /etc/os-release | head -1 | tr -d '"')
    case "$id" in
        arch) LOGO_NAME=arch ;; debian) LOGO_NAME=debian ;; ubuntu) LOGO_NAME=ubuntu ;;
        fedora) LOGO_NAME=fedora ;; nixos) LOGO_NAME=nixos ;; alpine) LOGO_NAME=alpine ;;
        gentoo) LOGO_NAME=gentoo ;; opensuse*|suse) LOGO_NAME=opensuse ;; pop) LOGO_NAME=pop ;;
        manjaro) LOGO_NAME=arch ;; *) LOGO_NAME=linux ;;
    esac
}

# --- runtime data ----------------------------------------------------------------
HOSTNAME_S=$(utils::quiet_err hostname || utils::quiet_err cat /etc/hostname || echo unknown)
USER_S=$(utils::quiet_err id -un || echo "${USER:-unknown}")
DISTRO_S=$(utils::quiet_err sed -n 's/^PRETTY_NAME=//p' /etc/os-release | head -1 | tr -d '"'); DISTRO_S=${DISTRO_S:-unknown}
KERNEL_S=$(utils::quiet_err uname -r || echo unknown)
SHELL_S="${SHELL:-unknown}"
UPTIME_S=""; CPU_S=""; MEM_S=""; DISK_S=""; IP_S=""

dripfetch::sysinfo_collect() {
    if [ -r /proc/uptime ]; then
        local up _ s d h m
        read -r up _ </proc/uptime
        s=${up%.*}
        d=$(( s/86400 )); h=$(( (s%86400)/3600 )); m=$(( (s%3600)/60 ))
        UPTIME_S="${d}d ${h}h ${m}m"
    fi
    CPU_S=$(utils::quiet_err awk -F': ' '/model name/{print $2; exit}' /proc/cpuinfo); CPU_S=${CPU_S:-unknown}
    if [ -r /proc/meminfo ]; then
        local tot avail
        tot=$(awk '/MemTotal/{print $2}' /proc/meminfo)
        avail=$(awk '/MemAvailable/{print $2}' /proc/meminfo)
        MEM_S="$(( (tot-avail)/1024 ))M / $(( tot/1024 ))M"
    fi
    DISK_S=$(utils::quiet_err df -h / | awk 'NR==2{print $3" / "$2" ("$5")"}'); DISK_S=${DISK_S:-unknown}
    IP_S=$(utils::quiet_err hostname -I | awk '{print $1}'); IP_S=${IP_S:-"-"}
}

# --- box content builders --------------------------------------------------------
dripfetch::sysinfo_lines() {
    printf '%s\n' "host   $HOSTNAME_S" "user   $USER_S" "os     $DISTRO_S" \
        "kernel $KERNEL_S" "uptime $UPTIME_S" "shell  $SHELL_S" \
        "cpu    $CPU_S" "mem    $MEM_S" "disk   $DISK_S" "ip     $IP_S"
}

# 3x5 block font (rows joined by '|')
declare -A FONT
FONT[0]="███|█ █|█ █|█ █|███"; FONT[1]=" █ |██ | █ | █ |███"
FONT[2]="███|  █|███|█  |███"; FONT[3]="███|  █|███|  █|███"
FONT[4]="█ █|█ █|███|  █|  █"; FONT[5]="███|█  |███|  █|███"
FONT[6]="███|█  |███|█ █|███"; FONT[7]="███|  █|  █|  █|  █"
FONT[8]="███|█ █|███|█ █|███"; FONT[9]="███|█ █|███|  █|███"
FONT[:]="   | █ |   | █ |   "; FONT[a]="███|█ █|███|█ █|█ █"
FONT[m]="█ █|███|█ █|█ █|█ █"; FONT[p]="███|█ █|███|█  |█  "

dripfetch::big_clock_lines() { # hh mm [ss] -> 5 lines
    local hh=$1 mm=$2 ss=$3
    local -a glyphs; glyphs=("${hh:0:1}" "${hh:1:1}" ":" "${mm:0:1}" "${mm:1:1}")
    [ -n "$ss" ] && glyphs+=(":" "${ss:0:1}" "${ss:1:1}")
    local row g
    for row in 0 1 2 3 4; do
        local out=""
        for g in "${glyphs[@]}"; do
            local seg="${FONT[$g]}" r=$row
            while (( r > 0 )); do seg="${seg#*|}"; (( r-- )); done
            out+="${seg%%|*} "
        done
        printf '%s\n' "$out"
    done
}

dripfetch::clock_lines() {
    local ts; ts=$(utils::quiet_err date +%H:%M:%S)
    local hh=${ts:0:2} mm=${ts:3:2} ss=${ts:6:2}
    local h12=$(( 10#$hh % 12 )); [ "$h12" -eq 0 ] && h12=12
    local ampm=""; (( CLOCK_24H )) || ampm=$(( 10#$hh >= 12 ? "PM" : "AM" ))
    local hdisp=$(( CLOCK_24H ? 10#$hh : h12 ))

    if [[ "$CLOCK_SIZE" == "small" ]]; then
        local body
        if (( CLOCK_24H )); then body="$hh:$mm"; (( CLOCK_SECONDS )) && body+=":$ss"
        else body="$h12:$mm"; (( CLOCK_SECONDS )) && body+=":$ss"; body+=" $ampm"; fi
        printf '%s\n' "$body"
    else
        (( CLOCK_BLINK )) && { if (( (FRAME/12)%2==0 )); then FONT[:]="   | █ |   | █ |   "; else FONT[:]="   |   |   |   |   "; fi; }
        local hhs mmss extra=""
        hhs=$(printf '%02d' "$hdisp")
        mmss="$mm"; (( CLOCK_SECONDS )) && extra="$ss"
        dripfetch::big_clock_lines "$hhs" "$mmss" "$extra"
        (( ! CLOCK_24H && CLOCK_AMPM )) && printf '%s\n' "$ampm"
    fi
    (( CLOCK_DATE )) && printf '%s\n' "$(date '+%a %d %b %Y')"
}

dripfetch::calendar_lines() {
    local Y M D dim firstdow
    Y=$(date +%Y); M=$(date +%m); D=$(date +%d)
    dim=$(utils::quiet_err date -d "$Y-$M-01 +1 month -1 day" +%d); dim=${dim:-30}
    firstdow=$(utils::quiet_err date -d "$Y-$M-01" +%u); firstdow=${firstdow:-1}
    local off hdr
    case "$CAL_START" in
        sunday)   off=$(( firstdow % 7 )); hdr="Su Mo Tu We Th Fr Sa" ;;
        saturday) off=$(( (firstdow % 7 + 1) % 7 )); hdr="Sa Su Mo Tu We Th Fr" ;;
        monday|*) off=$(( firstdow - 1 )); hdr="Mo Tu We Th Fr Sa Su" ;;
    esac
    printf '%s\n' "$(date +'%B %Y')" "$hdr"
    local day cell row="" idx
    for day in $(seq 1 "$dim"); do
        idx=$(( off + day - 1 ))
        if (( idx % 7 == 0 && day > 1 )); then printf '%s\n' "$row"; row=""; fi
        cell=$(printf '%2d' "$day")
        if (( day == D )); then row+="$REVERSE$BOLD$cell$RESET "
        else row+="$cell "; fi
    done
    [ -n "$row" ] && printf '%s\n' "$row"
}

dripfetch::weather_lines() {
    local lat=$WEATHER_LAT lon=$WEATHER_LON loc=$WEATHER_LOC
    if ! utils::has curl; then printf '%s\n' "offline (curl missing)"; return; fi
    if [ -z "$loc" ] && { [ -z "$lat" ] || [ -z "$lon" ]; }; then
        local geo; geo=$(utils::quiet_err curl -s --max-time 4 https://ipapi.co/json/)
        if [[ "$geo" == *'"latitude"'* ]]; then
            lat=$(sed -n 's/.*"latitude"[[:space:]]*:[[:space:]]*\(-\?[0-9.]*\).*/\1/p' <<<"$geo")
            lon=$(sed -n 's/.*"longitude"[[:space:]]*:[[:space:]]*\(-\?[0-9.]*\).*/\1/p' <<<"$geo")
            loc=$(sed -n 's/.*"city"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' <<<"$geo")
        fi
    fi
    if [ -n "$loc" ] && [ -z "$lat" ]; then
        local g; g=$(utils::quiet_err curl -s --max-time 4 "https://geocoding-api.open-meteo.com/v1/search?name=${loc// /%20}&count=1")
        lat=$(head -1 <<<"$(sed -n 's/.*"latitude":[[:space:]]*\(-\?[0-9.]*\).*/\1/p' <<<"$g")")
        lon=$(head -1 <<<"$(sed -n 's/.*"longitude":[[:space:]]*\(-\?[0-9.]*\).*/\1/p' <<<"$g")")
    fi
    if [ -z "$lat" ] || [ -z "$lon" ]; then printf '%s\n' "offline (no location)"; return; fi

    local unit="celsius"
    case "$WEATHER_UNITS" in fahrenheit|imperial) unit="fahrenheit" ;; esac
    local url="https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current_weather=true&daily=weathercode,temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=$WEATHER_DAYS&temperature_unit=$unit"
    local data; data=$(utils::quiet_err curl -s --max-time 6 "$url") || { printf '%s\n' "offline"; return; }
    [[ "$data" == *'"current_weather"'* ]] || { printf '%s\n' "no data"; return; }

    local t curcode cond du
    t=$(sed -n 's/.*"temperature":[[:space:]]*\(-\?[0-9.]*\).*/\1/p' <<<"$data")
    curcode=$(sed -n 's/.*"weathercode":[[:space:]]*\([0-9]*\).*/\1/p' <<<"$data")
    case "${curcode:-0}" in
        0|1) cond="clear" ;; 2) cond="partly" ;; 3) cond="overcast" ;;
        45|48) cond="fog" ;; 51|53|55|56|57) cond="drizzle" ;;
        61|63|65|66|67) cond="rain" ;; 71|73|75|77) cond="snow" ;;
        80|81|82) cond="showers" ;; 85|86) cond="snow" ;; 95|96|99) cond="thunder" ;;
        *) cond="-" ;;
    esac
    [[ "$unit" == "fahrenheit" ]] && du="F" || du="C"
    printf '%s\n' "${loc:-—}   ${t}°${du}  ${cond}"

    local dates maxs mins i line
    dates=(); while IFS= read -r line; do dates+=("$line"); done < <(sed -n 's/.*"time":\[\([^]]*\)\].*/\1/p' <<<"$data" | tr -d '"' | tr ',' '\n')
    maxs=();  while IFS= read -r line; do maxs+=("$line");  done < <(sed -n 's/.*"temperature_2m_max":\[\([^]]*\)\].*/\1/p' <<<"$data" | tr ',' '\n')
    mins=();  while IFS= read -r line; do mins+=("$line");  done < <(sed -n 's/.*"temperature_2m_min":\[\([^]]*\)\].*/\1/p' <<<"$data" | tr ',' '\n')
    local n=${#dates[@]}
    for (( i=0; i<n; i++ )); do
        printf '%s\n' "$(utils::quiet_err date -d "${dates[$i]}" '+%a' ) ${mins[$i]:-—}°  ${maxs[$i]:-—}°"
    done
}

dripfetch::text_lines() {
    if [ -z "$TEXT_CONTENT" ]; then
        printf '%s\n' "q quit · space pause · tab select · arrows move"
    else
        printf '%s\n' "$TEXT_CONTENT"
    fi
}

# --- net graph --------------------------------------------------------------------
declare NET_LAST_RX=0 NET_LAST_TX=0 NET_SAMPLES="" NET_T=0

dripfetch::net_sample_bytes() { [ -r /proc/net/dev ] || { echo "0 0"; return; }
    awk 'NR>2 { gsub(/:/," ",$1); rx+=$2; tx+=$10 } END { printf "%d %d", rx, tx }' /proc/net/dev; }

dripfetch::net_lines() {
    NET_T=$(( NET_T + 1 ))
    if (( NET_T >= NET_INTERVAL )); then
        NET_T=0
        local rx tx
        read -r rx tx <<<"$(dripfetch::net_sample_bytes)"
        if (( NET_LAST_RX > 0 )); then
            NET_SAMPLES+="$(( (rx-NET_LAST_RX)/NET_INTERVAL )):$(( (tx-NET_LAST_TX)/NET_INTERVAL )) "
        fi
        NET_LAST_RX=$rx; NET_LAST_TX=$tx
        local -a arr; arr=($NET_SAMPLES)
        while (( ${#arr[@]} > NET_WIDTH )); do arr=("${arr[@]:1}"); done
        NET_SAMPLES="${arr[*]}"
    fi
    local -a arr; arr=($NET_SAMPLES)
    if (( ${#arr[@]} == 0 )); then printf '%s\n' "down -" "up -"; return; fi
    local v d u max=1
    for v in "${arr[@]}"; do d=${v%%:*}; u=${v##*:}; (( d>max )) && max=$d; (( u>max )) && max=$u; done
    (( max < 1 )) && max=1
    local chars=( '▁' '▂' '▃' '▄' '▅' '▆' '▇' '█' ) dline="" uline="" di ui
    for v in "${arr[@]}"; do
        d=${v%%:*}; u=${v##*:}
        di=$(( d*8/max )); (( di>7 )) && di=7
        ui=$(( u*8/max )); (( ui>7 )) && ui=7
        dline+="${chars[$di]}"; uline+="${chars[$ui]}"
    done
    printf '%s\n' "down $dline" "up   $uline"
}

# --- box rendering ------------------------------------------------------------------
dripfetch::box_content() { case "$1" in
        sysinfo) dripfetch::sysinfo_lines ;; clock) dripfetch::clock_lines ;; calendar) dripfetch::calendar_lines ;;
        weather) dripfetch::weather_lines ;; text) dripfetch::text_lines ;; net) dripfetch::net_lines ;;
        logo) dripfetch::logo_text "$LOGO_NAME" ;; *) printf '%s\n' "?" ;;
    esac; }

dripfetch::strip_ansi() { sed -e 's/\x1b\[[0-9;]*m//g'; }

# return width/height of a box's content via globals BX_W/BX_H
dripfetch::box_measure() {
    local -a lines; lines=()
    local l w
    while IFS= read -r l; do lines+=("$l"); done < <(dripfetch::box_content "$1")
    BX_H=${#lines[@]}; BX_W=0
    while IFS= read -r l; do w=${#l}; (( w > BX_W )) && BX_W=$w; done < <(printf '%s\n' "${lines[@]}" | dripfetch::strip_ansi)
    [[ "$BX_W" -eq 0 ]] && BX_W=1
}

OUT=""
dripfetch::at() { OUT+="${ESC}[$1;$2H"; }

dripfetch::draw_box() {
    local type="$1" row="$2" col="$3"
    local -a lines; lines=()
    local l
    while IFS= read -r l; do lines+=("$l"); done < <(dripfetch::box_content "$type")
    local BX_H=${#lines[@]} BX_W=0 plain w
    while IFS= read -r l; do w=${#l}; (( w > BX_W )) && BX_W=$w; done < <(printf '%s\n' "${lines[@]}" | dripfetch::strip_ansi)
    [[ "$BX_W" -eq 0 ]] && BX_W=1

    local inner_w=$(( BX_W + 2*PAD_H )) inner_h=$(( BX_H + 2*PAD_V ))
    local total_w=$(( inner_w + 2 )) total_h=$(( inner_h + 2 ))
    (( total_w > TERM_W - 1 )) && total_w=$(( TERM_W - 1 ))
    (( total_h > TERM_H - 1 )) && total_h=$(( TERM_H - 1 ))
    (( row < 1 )) && row=1; (( col < 1 )) && col=1
    (( row + total_h - 1 > TERM_H )) && row=$(( TERM_H - total_h + 1 ))
    (( col + total_w - 1 > TERM_W )) && col=$(( TERM_W - total_w + 1 ))

    local tl tr bl br hz vt
    case "$BORDER_STYLE" in
        double) tl="╔" tr="╗" bl="╚" br="╝" hz="═" vt="║" ;;
        none)   tl=" " tr=" " bl=" " br=" " hz=" " vt=" " ;;
        *)      tl="┌" tr="┐" bl="└" br="┘" hz="─" vt="│" ;;
    esac

    local title="${BOX_TITLE[$type]:-}" x
    if (( ${#title} > inner_w )); then title="${title:0:$inner_w}"; fi

    # top border (+title)
    dripfetch::at "$row" "$col"
    dripfetch::fgb "${C_BORDER[0]}" "${C_BORDER[1]}" "${C_BORDER[2]}"
    OUT+="$tl"
    if [ -n "$title" ]; then
        dripfetch::fgb "${C_ACCENT[0]}" "${C_ACCENT[1]}" "${C_ACCENT[2]}"
        OUT+="$title"
        dripfetch::fgb "${C_BORDER[0]}" "${C_BORDER[1]}" "${C_BORDER[2]}"
    fi
    for (( x=col+1+${#title}; x < col+total_w-1; x++ )); do OUT+="$hz"; done
    OUT+="$tr"

    local i
    for (( i=1; i<=inner_h; i++ )); do
        dripfetch::at "$((row+i))" "$col"
        dripfetch::fgb "${C_BORDER[0]}" "${C_BORDER[1]}" "${C_BORDER[2]}"
        OUT+="$vt"
        dripfetch::fgb "${C_TEXT[0]}" "${C_TEXT[1]}" "${C_TEXT[2]}"
        local linetxt=""
        if (( i > PAD_V && i <= PAD_V+BX_H )); then linetxt="${lines[$((i-PAD_V-1))]}"; fi
        OUT+="$linetxt"
        plain=$(printf '%s' "$linetxt" | dripfetch::strip_ansi)
        local w padn p
        w=${#plain}; padn=$(( inner_w - w ))
        p=$(printf '%*s' "$padn" '')
        OUT+="$p"
        dripfetch::fgb "${C_BORDER[0]}" "${C_BORDER[1]}" "${C_BORDER[2]}"
        OUT+="$vt"
    done

    dripfetch::at "$((row+inner_h+1))" "$col"
    dripfetch::fgb "${C_BORDER[0]}" "${C_BORDER[1]}" "${C_BORDER[2]}"
    OUT+="$bl"
    local rep=$(( total_w - 2 )); (( rep < 0 )) && rep=0
    local x2
    for (( x2=0; x2<rep; x2++ )); do OUT+="$hz"; done
    OUT+="$br$RESET"
}

# --- matrix rain ----------------------------------------------------------------------
declare -a RAIN_HEAD RAIN_LEN RAIN_COLOR_STR RAIN_CHAR_X
RAIN_NCOL=0

dripfetch::weighted_pick() { # p1 v1 p2 v2 … -> echoes a value
    local r=$(( RANDOM % 1000 )) acc=0 p v pi last=""
    while [[ $# -ge 2 ]]; do
        p="$1"; v="$2"; shift 2
        pi=$(awk -v p="$p" 'BEGIN{printf "%d", p*1000}')
        acc=$(( acc + pi ))
        if (( r < acc )); then printf '%s' "$v"; return 0; fi
        last="$v"
    done
    printf '%s' "$last"
}

dripfetch::rain_respawn() { local x=$1 len speed ch color
    len=$(dripfetch::weighted_pick "${RAIN_LENGTHS[@]}");   len=${len:-6}
    speed=$(dripfetch::weighted_pick "${RAIN_SPEEDS[@]}");  speed=${speed:-40}
    ch="${RAIN_CHARS[$((RANDOM % ${#RAIN_CHARS[@]}))]}"
    color=$(dripfetch::weighted_pick "${RAIN_COLORS[@]}");  color=${color:-#21F7A8}
    RAIN_HEAD[$x]=-1
    RAIN_LEN[$x]=$len
    RAIN_COLOR_STR[$x]=$color
    RAIN_CHAR_X[$x]="$ch"
}

dripfetch::rain_init() {
    local x
    for (( x=0; x<TERM_W; x++ )); do
        RAIN_HEAD[$x]=-1; RAIN_LEN[$x]=6
        RAIN_COLOR_STR[$x]="#21F7A8"; RAIN_CHAR_X[$x]="│"
        if (( RANDOM % 100 < RAIN_INTENSITY * 100 / TERM_W )); then
            dripfetch::rain_respawn "$x"; RAIN_HEAD[$x]=$(( RANDOM % (TERM_H+1) ))
        fi
    done
    RAIN_NCOL=$TERM_W
}

dripfetch::rain_step() {
    local x
    for (( x=0; x<RAIN_NCOL; x++ )); do
        if (( RAIN_HEAD[$x] < 0 )); then
            if (( RANDOM % (TERM_W*2) < RAIN_INTENSITY )); then dripfetch::rain_respawn "$x"; fi
            continue
        fi
        (( RAIN_HEAD[$x] + 1 > TERM_H )) && { RAIN_HEAD[$x]=-1; continue; }
        RAIN_HEAD[$x]=$(( RAIN_HEAD[$x] + 1 ))
    done
}

dripfetch::rain_draw() {
    local x head len rgbstr ch rgb y i fgstr headstr s
    for (( x=0; x<RAIN_NCOL; x++ )); do
        head=${RAIN_HEAD[$x]}; (( head < 0 )) && continue
        len=${RAIN_LEN[$x]}; rgbstr=${RAIN_COLOR_STR[$x]}; ch=${RAIN_CHAR_X[$x]}
        rgb=($(dripfetch::hex2rgb "$rgbstr"))
        if (( EMIT_TRUECOLOR )); then
            fgstr=$(printf '%s[38;2;%d;%d;%dm' "$ESC" "${rgb[0]}" "${rgb[1]}" "${rgb[2]}")
        else
            fgstr=$(printf '%s[38;5;%dm' "$ESC" "$(dripfetch::rgb256 "${rgb[0]}" "${rgb[1]}" "${rgb[2]}")")
        fi
        headstr="${BOLD}$(printf '%s[38;2;255;255;255m' "$ESC")"
        s=""
        for (( i=0; i<len && i<TERM_H; i++ )); do
            y=$(( head - i )); (( y < 0 )) && continue
            s+="${ESC}[$((y+1));$((x+1))H"
            if (( i == 0 )); then s+="$headstr$ch"; else s+="$fgstr$ch"; fi
        done
        OUT+="$s$RESET"
    done
}

# --- selection / persistence ----------------------------------------------------------
SEL_INDEX=-1
declare -A BOX_META BOX_TITLE

dripfetch::sel_box() { local n=${#BOX_TYPES[@]}; (( n )) && SEL_INDEX=$(( (SEL_INDEX + 1) % n )); }

dripfetch::move_sel() { local dx=$1 dy=$2
    [[ $SEL_INDEX -lt 0 ]] && return
    local t m col row
    t=${BOX_TYPES[$SEL_INDEX]}; m=${BOX_META[$t]}
    col=${m%% *}; row=${m#* }
    BOX_META[$t]="$(( col + dx )) $(( row + dy ))"
    dripfetch::persist_positions; }

dripfetch::persist_positions() {
    utils::quiet mkdir -p "$CONFIG_DIR" || return
    : > "$POS_FILE"
    local t m col row
    for t in "${BOX_TYPES[@]}"; do
        m=${BOX_META[$t]}; col=${m%% *}; row=${m#* }
        printf '%s=%s=%s\n' "$t" "$col" "$row" >> "$POS_FILE"
    done
}

dripfetch::load_positions() { local t col row
    [ -r "$POS_FILE" ] || return
    while IFS='=' read -r t col row; do
        [ -n "$t" ] && BOX_META[$t]="$col $row"
    done < "$POS_FILE"; }

# --- frame composer --------------------------------------------------------------------
declare -i QUIT=0 PAUSED=0 FRAME=0

dripfetch::render_frame() {
    OUT=""
    OUT+="${ESC}[2J"

    if (( BG_SET )); then
        local y pad
        pad=$(printf '%*s' "$TERM_W" '')
        for (( y=1; y<=TERM_H; y++ )); do
            dripfetch::at "$y" 1
            dripfetch::bgb "${C_BG[0]}" "${C_BG[1]}" "${C_BG[2]}"
            OUT+="$pad"
        done
        OUT+="$RESET"
    fi

    local t m col row
    for t in "${BOX_TYPES[@]}"; do
        m=${BOX_META[$t]}; col=${m%% *}; row=${m#* }
        dripfetch::draw_box "$t" "${row:-1}" "${col:-1}"
    done

    (( PAUSED )) || dripfetch::rain_draw

    if (( SEL_INDEX >= 0 )); then
        local t=${BOX_TYPES[$SEL_INDEX]}
        dripfetch::at "$TERM_H" 1
        OUT+="${ESC}[2K${ESC}[7m [$t] arrows/WASD move · Esc deselect ${ESC}[0m"
    fi

    OUT+="${ESC}[1;1H"
    printf '%s' "$OUT"
}

# --- keyboard ----------------------------------------------------------------------------
dripfetch::read_char() { # varname timeout -> 0 on success, 1 on timeout/EOF (portable bash/zsh)
    if [[ -n "${ZSH_VERSION:-}" ]]; then
        IFS= read -rs -k 1 -t "$2" "$1"
    else
        IFS= read -rs -t "$2" -n 1 "$1"
    fi
}

dripfetch::read_key() {
    local k
    if ! dripfetch::read_char k 0.03; then return 1; fi
    if [[ "$k" == "$ESC" ]]; then
        local k2="" k3=""
        dripfetch::read_char k2 0.02 || true
        dripfetch::read_char k3 0.02 || true
        case "$k2$k3" in
            '[A') echo UP ;; '[B') echo DOWN ;; '[C') echo RIGHT ;; '[D') echo LEFT ;;
            '') echo ESC ;; *) echo NONE ;;
        esac
    else
        printf '%s' "$k"
    fi
}

dripfetch::handle_key() { case "$1" in
        q|Q) QUIT=1 ;;
        ' ') PAUSED=$(( 1 - PAUSED )) ;;
        $'\t') dripfetch::sel_box ;;
        UP) dripfetch::move_sel 0 -1 ;; DOWN) dripfetch::move_sel 0 1 ;; LEFT) dripfetch::move_sel -1 0 ;; RIGHT) dripfetch::move_sel 1 0 ;;
        w) dripfetch::move_sel 0 -1 ;; s) dripfetch::move_sel 0 1 ;; a) dripfetch::move_sel -1 0 ;; d) dripfetch::move_sel 1 0 ;;
        ESC) SEL_INDEX=-1 ;;
        *) : ;;
    esac; }

# --- layout -------------------------------------------------------------------------------
dripfetch::layout_boxes() {
    local t; for t in "${BOX_TYPES[@]}"; do dripfetch::box_measure "$t"; BOX_W[$t]=$BX_W; BOX_H[$t]=$BX_H; done
    local lw=${BOX_W[logo]:-10} lh=${BOX_H[logo]:-6} cw=${BOX_W[calendar]:-20} ch=${BOX_H[calendar]:-8}
    local top_row=2
    BOX_META[logo]="$top_row 2"
    BOX_META[sysinfo]="$top_row $(( 2 + lw + 2 ))"
    BOX_META[clock]="$top_row $(( TERM_W - BOX_W[clock] - 2 ))"
    local bottom=$(( top_row + lh + 2 ))
    BOX_META[calendar]="$bottom 2"
    BOX_META[text]="$bottom $(( 2 + cw + 2 ))"
    BOX_META[weather]="$bottom $(( TERM_W - BOX_W[weather] - 2 ))"
    BOX_META[net]="$(( bottom + ch + 2 )) 2"

    BOX_TITLE[logo]=""; BOX_TITLE[sysinfo]="sysinfo"; BOX_TITLE[clock]="clock"
    BOX_TITLE[calendar]=""; BOX_TITLE[weather]="weather"; BOX_TITLE[text]=""; BOX_TITLE[net]="net"
}
declare -A BOX_W BOX_H

# --- config apply --------------------------------------------------------------------------
dripfetch::apply_config() {
    local raw
    raw=$(dripfetch::cfg_get "background" ""); [ -n "$raw" ] && BG_HEX="$raw"
    raw=$(dripfetch::cfg_get "boxes.border_color" ""); [ -n "$raw" ] && BORDER_HEX="$raw"
    raw=$(dripfetch::cfg_get "boxes.text_color" ""); [ -n "$raw" ] && TEXT_HEX="$raw"
    raw=$(dripfetch::cfg_get "boxes.accent_color" ""); [ -n "$raw" ] && ACCENT_HEX="$raw"
    raw=$(dripfetch::cfg_get "boxes.border" ""); [ -n "$raw" ] && BORDER_STYLE="$raw"
    raw=$(dripfetch::cfg_get "boxes.padding.horizontal" ""); [ -n "$raw" ] && PAD_H="$raw"
    raw=$(dripfetch::cfg_get "boxes.padding.vertical" ""); [ -n "$raw" ] && PAD_V="$raw"

    raw=$(dripfetch::cfg_get "rain.intensity" ""); [ -n "$raw" ] && RAIN_INTENSITY="$raw"
    raw=$(dripfetch::cfg_get "rain.character" "")
    if [ -n "$raw" ]; then RAIN_CHARS=(); local __c; while IFS= read -r __c; do [ -n "$__c" ] && RAIN_CHARS+=("$__c"); done < <(printf '%s\n' "$raw" | tr -d '[]" ' | tr ',' '\n'); fi
    raw=$(dripfetch::cfg_get "rain.colors" "")
    if [ -n "$raw" ]; then RAIN_COLORS=( $(printf '%s\n' "$raw" | tr -d '[]"' | tr ',' ' ') ); fi
    raw=$(dripfetch::cfg_get "rain.speeds" "")
    if [ -n "$raw" ]; then RAIN_SPEEDS=( $(printf '%s\n' "$raw" | tr -d '[]"' | tr ',' ' ') ); fi
    raw=$(dripfetch::cfg_get "rain.lengths" "")
    if [ -n "$raw" ]; then RAIN_LENGTHS=( $(printf '%s\n' "$raw" | tr -d '[]"' | tr ',' ' ') ); fi

    raw=$(dripfetch::cfg_get "calendar.starting_day" ""); [ -n "$raw" ] && CAL_START="$raw"
    raw=$(dripfetch::cfg_get "weather.location" "");  [ -n "$raw" ] && WEATHER_LOC="$raw"
    raw=$(dripfetch::cfg_get "weather.latitude" "");  [ -n "$raw" ] && WEATHER_LAT="$raw"
    raw=$(dripfetch::cfg_get "weather.longitude" ""); [ -n "$raw" ] && WEATHER_LON="$raw"
    raw=$(dripfetch::cfg_get "weather.units" "");     [ -n "$raw" ] && WEATHER_UNITS="$raw"
    raw=$(dripfetch::cfg_get "weather.days" "");      [ -n "$raw" ] && WEATHER_DAYS="$raw"
    raw=$(dripfetch::cfg_get "net.width" "");         [ -n "$raw" ] && NET_WIDTH="$raw"
    raw=$(dripfetch::cfg_get "net.interval" "");      [ -n "$raw" ] && NET_INTERVAL="$raw"
    raw=$(dripfetch::cfg_get "text.alignment" "");    [ -n "$raw" ] && TEXT_ALIGN="$raw"

    # items
    local i=0 ty types=""
    while :; do
        ty=$(dripfetch::cfg_get "boxes.items.$i.type" "")
        [ -z "$ty" ] && break
        types+="$ty "
        case "$ty" in
            clock)    raw=$(dripfetch::cfg_get "boxes.items.$i.clock_size" ""); [ -n "$raw" ] && CLOCK_SIZE="$raw"
                      raw=$(dripfetch::cfg_get "boxes.items.$i.clock_24h" "true");   [[ "$raw" == false ]] && CLOCK_24H=0 || CLOCK_24H=1
                      raw=$(dripfetch::cfg_get "boxes.items.$i.show_seconds" "true"); [[ "$raw" == false ]] && CLOCK_SECONDS=0 || CLOCK_SECONDS=1
                      raw=$(dripfetch::cfg_get "boxes.items.$i.show_date" "true");    [[ "$raw" == false ]] && CLOCK_DATE=0 || CLOCK_DATE=1
                      raw=$(dripfetch::cfg_get "boxes.items.$i.show_am_pm" "false");  [[ "$raw" == true ]] && CLOCK_AMPM=1 || CLOCK_AMPM=0
                      raw=$(dripfetch::cfg_get "boxes.items.$i.blink_colon" "true");  [[ "$raw" == false ]] && CLOCK_BLINK=0 || CLOCK_BLINK=1 ;;
            calendar) raw=$(dripfetch::cfg_get "boxes.items.$i.starting_day" ""); [ -n "$raw" ] && CAL_START="$raw" ;;
            weather)  raw=$(dripfetch::cfg_get "boxes.items.$i.location" ""); [ -n "$raw" ] && WEATHER_LOC="$raw"
                      raw=$(dripfetch::cfg_get "boxes.items.$i.latitude" ""); [ -n "$raw" ] && WEATHER_LAT="$raw"
                      raw=$(dripfetch::cfg_get "boxes.items.$i.longitude" ""); [ -n "$raw" ] && WEATHER_LON="$raw"
                      raw=$(dripfetch::cfg_get "boxes.items.$i.units" ""); [ -n "$raw" ] && WEATHER_UNITS="$raw"
                      raw=$(dripfetch::cfg_get "boxes.items.$i.days" ""); [ -n "$raw" ] && WEATHER_DAYS="$raw" ;;
            text)     raw=$(dripfetch::cfg_get "boxes.items.$i.text" ""); [ -n "$raw" ] && TEXT_CONTENT="$raw"
                      raw=$(dripfetch::cfg_get "boxes.items.$i.alignment" ""); [ -n "$raw" ] && TEXT_ALIGN="$raw" ;;
            logo)     raw=$(dripfetch::cfg_get "boxes.items.$i.logo" ""); [ -n "$raw" ] && [[ "$raw" != "__auto__" ]] && LOGO_NAME="$raw" ;;
            net)      raw=$(dripfetch::cfg_get "boxes.items.$i.width" ""); [ -n "$raw" ] && NET_WIDTH="$raw" ;;
        esac
        i=$(( i + 1 ))
    done
    if [ -n "$types" ]; then
        BOX_TYPES=(); local t; for t in $types; do BOX_TYPES+=("$t"); done
    fi
}

# --- CLI / meta ---------------------------------------------------------------------------
dripfetch::usage() { cat <<'EOF'
dripfetch.sh — bash terminal dashboard (matrix rain + boxes)

Usage:
  dripfetch.sh                        interactive dashboard
  dripfetch.sh -c N|NAME|PATH         run with preset/config (session only)
  dripfetch.sh --set-config N|PATH    save preset/config as active config
  dripfetch.sh --init-config          (re)create default config
  dripfetch.sh --list-configs         presets
  dripfetch.sh --list-logos           logos
  dripfetch.sh --list-boxes           box types
  dripfetch.sh --print-logo NAME      print a logo
  dripfetch.sh --config-path          print config path
  dripfetch.sh -v|--version           show version
  dripfetch.sh -h|--help              this help

Interactive: q quit · Space pause · Tab select · arrows/WASD move · Esc deselect
EOF
}

dripfetch::list_logos()  { printf '%s\n' arch debian ubuntu fedora nixos alpine gentoo opensuse pop linux bs; }
dripfetch::list_boxes()  { printf '%s\n' logo sysinfo clock calendar weather net text; }
dripfetch::list_configs(){ printf '0 default\n1 neon_matrix\n2 moonlight_observatory\n3 ops_console\n4 citrus_pop\n5 arcade_white\n6 ink_and_amber\n7 arcade_cabinet\n'; }

dripfetch::create_default_config() { # serializes current globals (theme) into CONFIG_FILE
    utils::quiet mkdir -p "$CONFIG_DIR" || return 1
    cat > "$CONFIG_FILE" <<EOF
background: "$BG_HEX"
keyboard:
  layout: qwerty
rain:
  collision: false
  intensity: $RAIN_INTENSITY
  character: ["│", "┃", "╎"]
  colors: [[0.7, "$ACCENT_HEX"], [0.3, "$BORDER_HEX"]]
  speeds: [[0.5, 30], [0.5, 50]]
  lengths: [[0.8, 6], [0.2, 14]]
  effects:
    acceleration: false
    splash: false
boxes:
  border: titled_single
  border_color: "$BORDER_HEX"
  text_color: "$TEXT_HEX"
  accent_color: "$ACCENT_HEX"
  padding:
    horizontal: 2
    vertical: 0
  items:
    - type: logo
    - type: sysinfo
    - type: clock
      clock_size: big
      clock_24h: true
      show_seconds: true
      blink_colon: true
      show_date: true
    - type: calendar
      starting_day: monday
    - type: text
      text: "q quit · space pause · arrows move"
EOF
    printf 'created %s\n' "$CONFIG_FILE"
}

# --- main -----------------------------------------------------------------------------------
main() {
    local cfgarg="" setcfg="" printlogo=""
    while [ $# -gt 0 ]; do
        case "$1" in
            -c|--use-config) cfgarg="$2"; shift 2 ;;
            --set-config)    setcfg="$2"; shift 2 ;;
            --list-configs)  dripfetch::list_configs; exit 0 ;;
            --list-logos)    dripfetch::list_logos;   exit 0 ;;
            --list-boxes)    dripfetch::list_boxes;   exit 0 ;;
            --config-path)   printf '%s\n' "$CONFIG_FILE"; exit 0 ;;
            --print-logo)    printlogo="$2"; shift 2 ;;
            --init-config)   dripfetch::create_default_config; exit 0 ;;
            -v|--version)    printf '%s\n' "$VERSION"; exit 0 ;;
            -h|--help)       dripfetch::usage; exit 0 ;;
            *) dripfetch::usage; exit 2 ;;
        esac
    done

    if [ -n "$printlogo" ]; then dripfetch::logo_text "$printlogo"; exit 0; fi

    local loadfile=0 cfgfile="$CONFIG_FILE"
    if [ -n "$cfgarg" ]; then
        case "$cfgarg" in
            *.yaml|*.yml) [ -r "$cfgarg" ] && { cfgfile="$cfgarg"; loadfile=1; } ;;   # session config from file
            *) dripfetch::preset_apply "$cfgarg" ;;                                              # preset = theme only
        esac
    elif [ -r "$CONFIG_FILE" ]; then
        loadfile=1
    else
        utils::ignore dripfetch::create_default_config
    fi

    if [ -n "$setcfg" ]; then
        case "$setcfg" in
            *.yaml|*.yml) [ -r "$setcfg" ] && { mkdir -p "$CONFIG_DIR"; cp "$setcfg" "$CONFIG_FILE"; } ;;
            *) dripfetch::preset_apply "$setcfg"; dripfetch::create_default_config; printf 'active config set to preset "%s"\n' "$setcfg"; exit 0 ;;
        esac
    fi

    if (( loadfile )); then dripfetch::yaml_flatten "$cfgfile"; dripfetch::apply_config; fi

    dripfetch::set_colour border $(dripfetch::hex2rgb "$BORDER_HEX")
    dripfetch::set_colour text   $(dripfetch::hex2rgb "$TEXT_HEX")
    dripfetch::set_colour accent $(dripfetch::hex2rgb "$ACCENT_HEX")
    if [ -n "$BG_HEX" ] && [ "$BG_HEX" != "nil" ]; then dripfetch::set_colour bg $(dripfetch::hex2rgb "$BG_HEX"); fi

    dripfetch::detect_logo
    dripfetch::detect_colour
    dripfetch::get_size
    TERM_ACTIVE=1
    trap dripfetch::term_restore EXIT
    trap 'exit 0' INT TERM
    dripfetch::term_init
    dripfetch::sysinfo_collect
    dripfetch::layout_boxes
    dripfetch::load_positions
    dripfetch::rain_init

    local key
    while true; do
        FRAME=$(( FRAME + 1 ))
        (( PAUSED )) || dripfetch::rain_step
        dripfetch::render_frame
        if key=$(dripfetch::read_key); then dripfetch::handle_key "$key"; fi
        (( QUIT )) && break
    done
}

main "$@"
