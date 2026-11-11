#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testnetconnunit.sh — unit tests for lib/network/conn (sysfs reader, routes, nmcli parsing, actions, TUI frame)
# tests/unit/testnetconnunit.sh — юнит-тесты lib/network/conn (чтение sysfs, маршруты, разбор nmcli, действия, кадр TUI)
#
# A fake /sys/class/net tree, /proc/net/route, resolv.conf and fake "ip" and
# "nmcli" scripts stand in for the system, so the run needs no network, no
# NetworkManager and no root. The fakes log every call to check the commands.
# Систему заменяют поддельное дерево /sys/class/net, /proc/net/route,
# resolv.conf и скрипты «ip» и «nmcli»: сеть, NetworkManager и root не нужны.
# Подделки пишут каждый вызов в журнал, чтобы проверять команды.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

load "lib/network/conn/tui"

FIX="$(mktemp -d)"
readonly FIX
trap 'rm -rf "${FIX}"' EXIT

# @description Has $1 the substring $2? Prints 0/1 for assert_equal.
has() {
    if [[ "$1" == *"$2"* ]]; then printf '1'; else printf '0'; fi
}

# @description Field of a "key=value" record / Поле записи «ключ=значение».
field() {
    local line
    while IFS= read -r line; do
        [[ "${line}" == "$2="* ]] && { printf '%s' "${line#*=}"; return 0; }
    done <<< "$1"
    return 0
}

# @description Make a fake interface in the fake sysfs / Создать поддельный интерфейс.
# @param $1 name, $2 type, $3 operstate, $4 flags, $5 mac, $6 rx, $7 tx, $8 [DEVTYPE]
mkif() {
    local -r d="${FIX}/sys/$1"
    mkdir -p "${d}/statistics"
    printf '%s\n' "$2" > "${d}/type"
    printf '%s\n' "$3" > "${d}/operstate"
    printf '%s\n' "$4" > "${d}/flags"
    printf '%s\n' "$5" > "${d}/address"
    printf '1500\n' > "${d}/mtu"
    printf '1\n' > "${d}/carrier"
    printf '%s\n' "$6" > "${d}/statistics/rx_bytes"
    printf '%s\n' "$7" > "${d}/statistics/tx_bytes"
    printf 'INTERFACE=%s\n' "$1" > "${d}/uevent"
    [[ -n "${8-}" ]] && printf 'DEVTYPE=%s\n' "$8" >> "${d}/uevent"
    return 0
}

setup_fixture() {
    mkdir -p "${FIX}/sys" "${FIX}/proc" "${FIX}/bin"
    mkif lo 772 unknown 0x9 00:00:00:00:00:00 100 100
    mkif eth0 1 up 0x1003 52:54:00:12:34:56 1000 2000
    mkdir -p "${FIX}/sys/eth0/device"
    printf '1000\n' > "${FIX}/sys/eth0/speed"
    mkif wlan0 1 dormant 0x1003 aa:bb:cc:dd:ee:ff 5000 6000 wlan
    mkif docker0 1 down 0x1002 02:42:ac:11:00:01 0 0 bridge
    mkif wg0 65534 unknown 0x91 "" 10 20 wireguard
    mkif tun0 65534 unknown 0x10d1 "" 7 8
    : > "${FIX}/sys/tun0/tun_flags"
    printf '%s\n' "Iface	Destination	Gateway 	Flags	RefCnt	Use	Metric	Mask		MTU	Window	IRTT" \
        "wlan0	00000000	0101A8C0	0003	0	0	600	00000000	0	0	0" \
        "eth0	00000000	FE00000A	0003	0	0	100	00000000	0	0	0" \
        "eth0	0000000A	00000000	0001	0	0	100	00FFFFFF	0	0	0" > "${FIX}/proc/route"
    printf '%s\n' "fe8000000000000050540000fe123456 02 40 20 80     eth0" \
        "00000000000000000000000000000001 01 80 10 80       lo" > "${FIX}/proc/if_inet6"
    printf '# test\nnameserver 1.1.1.1\nnameserver  9.9.9.9 \nsearch lan\n' > "${FIX}/resolv.conf"

    cat > "${FIX}/bin/ip" <<'EOF'
#!/usr/bin/env bash
printf 'ip %s\n' "$*" >> "${NETCONN_TEST_LOG}"
case "$*" in
    "-o addr show dev eth0") printf '2: eth0    inet 10.0.0.5/24 brd 10.0.0.255 scope global eth0\\       valid_lft forever\n2: eth0    inet6 fe80::5054:ff:fe12:3456/64 scope link \\       valid_lft forever\n' ;;
    "-o -4 addr show") printf '2: eth0    inet 10.0.0.5/24 brd 10.0.0.255 scope global eth0\n3: wlan0    inet 192.168.1.20/24 scope global wlan0\n' ;;
    link\ set\ dev\ *) exit 0 ;;
esac
EOF
    cat > "${FIX}/bin/nmcli" <<'EOF'
#!/usr/bin/env bash
printf 'nmcli %s\n' "$*" >> "${NETCONN_TEST_LOG}"
[[ "${NETCONN_TEST_NM:-1}" == 1 ]] || { [[ "$*" == "-t -f RUNNING general" ]] && printf 'stopped\n'; exit 8; }
case "$*" in
    "-t -f RUNNING general") printf 'running\n' ;;
    "-t -f DEVICE,STATE device status") printf 'wlan0:connected\neth0:unmanaged\ndocker0:connected (externally)\nlo:unmanaged\n' ;;
    "-t -f NAME,UUID,TYPE,DEVICE,ACTIVE connection show")
        printf 'Home\\:5G:11111111-2222-3333-4444-555555555555:802-11-wireless:wlan0:yes\n'
        printf 'Office:aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee:802-3-ethernet::no\n'
        printf 'up:99999999-8888-7777-6666-555555555555:vpn::no\n' ;;
    "-t -f IN-USE,SSID,SIGNAL,SECURITY,CHAN device wifi list --rescan "*)
        printf ' :Cafe:40:--:6\n*:Home\\:5G:82:WPA2:36\n :Neighbour:55:WPA1 WPA2:11\n :Neighbour:30:WPA1 WPA2:1\n :--:20:WPA2:1\n' ;;
    "device wifi connect "*|"connection up "*|"connection down "*|"device connect "*|"device disconnect "*|"radio wifi "*) exit 0 ;;
    *) exit 2 ;;
esac
EOF
    chmod +x "${FIX}/bin/ip" "${FIX}/bin/nmcli"
    export BS_NET_SYS="${FIX}/sys" BS_NET_PROC="${FIX}/proc" BS_NET_RESOLV="${FIX}/resolv.conf"
    export NETCONN_TEST_LOG="${FIX}/calls.log"
    : > "${NETCONN_TEST_LOG}"
}

# @description Run with fake ip/nmcli first on PATH / Выполнить с поддельными ip/nmcli первыми в PATH.
with_fakes() { PATH="${FIX}/bin:${PATH}" "$@"; }

# @description Run with neither ip nor nmcli / Выполнить без ip и nmcli.
without_tools() { PATH="${FIX}/empty" "$@"; }

test_sysfs() {
    testframework::section "sysfs: names, kinds, states / имена, виды, состояния"
    testframework::assert_equal "lo docker0 eth0 tun0 wg0 wlan0" "$(network::conn::names | tr '\n' ' ' | sed 's/ $//')" "names: lo first, rest sorted"
    testframework::assert_equal "loopback" "$(network::conn::kind lo)" "kind lo"
    testframework::assert_equal "ethernet" "$(network::conn::kind eth0)" "kind eth0 (has device)"
    testframework::assert_equal "wifi" "$(network::conn::kind wlan0)" "kind wlan0 (DEVTYPE=wlan)"
    testframework::assert_equal "bridge" "$(network::conn::kind docker0)" "kind docker0"
    testframework::assert_equal "wireguard" "$(network::conn::kind wg0)" "kind wg0"
    testframework::assert_equal "tun" "$(network::conn::kind tun0)" "kind tun0 (tun_flags)"
    testframework::assert_equal "up" "$(network::conn::state lo)" "state unknown + IFF_UP → up"
    testframework::assert_equal "down" "$(network::conn::state docker0)" "state down"
    testframework::assert_equal "dormant" "$(network::conn::state wlan0)" "state dormant kept"
    testframework::assert_equal "1000 2000" "$(network::conn::stats eth0)" "stats rx tx"
    local rc=0
    network::conn::admin_up docker0 || rc=$?
    testframework::assert_equal "1" "${rc}" "admin_up: docker0 flags 0x1002 → down"
    testframework::assert_equal $'eth0\tethernet\tup\t52:54:00:12:34:56\t1500' "$(network::conn::list | grep '^eth0')" "list row"
}

test_routes_dns() {
    testframework::section "routes, DNS, addresses / маршруты, DNS, адреса"
    testframework::assert_equal $'eth0\t10.0.0.254\t100\nwlan0\t192.168.1.1\t600' "$(network::conn::gateways)" "default routes, lowest metric first"
    testframework::assert_equal $'wlan0\t192.168.1.1\t600' "$(network::conn::gateways wlan0)" "gateways filtered by interface"
    testframework::assert_equal $'1.1.1.1\n9.9.9.9' "$(network::conn::dns)" "dns from resolv.conf"
    testframework::assert_equal $'inet 10.0.0.5/24\ninet6 fe80::5054:ff:fe12:3456/64' "$(with_fakes network::conn::addrs eth0)" "addrs via ip -o"
    testframework::assert_equal "inet6 fe80::5054:0:fe12:3456/64" "$(without_tools network::conn::addrs eth0)" "addrs without tools: IPv6 from procfs"
    testframework::assert_equal "::1" "$(network::conn::__ip6 00000000000000000000000000000001)" "ip6 ::1"
    testframework::assert_equal "2001:db8::1:0:0:1" "$(network::conn::__ip6 20010db8000000000001000000000001)" "ip6 longest zero run"
    testframework::assert_equal "2001:db8:0:1:1:1:1:1" "$(network::conn::__ip6 20010db8000000010001000100010001)" "ip6 single zero not compressed"
    local s
    s="$(with_fakes network::conn::show eth0)"
    testframework::assert_equal "ethernet" "$(field "${s}" kind)" "show kind"
    testframework::assert_equal "1000" "$(field "${s}" speed)" "show speed"
    testframework::assert_equal "10.0.0.5/24" "$(field "${s}" inet)" "show inet"
    testframework::assert_equal "10.0.0.254" "$(field "${s}" gateway)" "show gateway"
    testframework::assert_equal "" "$(field "${s}" managed)" "show: eth0 unmanaged by NM"
    s="$(with_fakes network::conn::show wlan0)"
    testframework::assert_equal "networkmanager" "$(field "${s}" managed)" "show: wlan0 managed by NM"
    local rc=0
    network::conn::show nope 2>/dev/null || rc=$?
    testframework::assert_equal "1" "${rc}" "show: missing interface fails"
}

test_nmcli() {
    testframework::section "nmcli parsing / разбор nmcli"
    testframework::assert_equal $'a:b\tc\\d\t--\t--' "$(network::conn::nm::split 'a\:b:c\\d::')" "split: escapes, empty fields become --"
    testframework::assert_equal $'Home:5G\t11111111-2222-3333-4444-555555555555\t802-11-wireless\twlan0\tyes' \
        "$(with_fakes network::conn::nm::profiles | sed -n 1p)" "profiles: escaped colon in name"
    testframework::assert_equal "3" "$(with_fakes network::conn::nm::profiles | wc -l | tr -d ' ')" "profiles: count"
    testframework::assert_equal $'Office\taaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee\t802-3-ethernet\t--\tno' \
        "$(with_fakes network::conn::nm::profiles | sed -n 2p)" "profiles: no device → --"
    testframework::assert_equal $'wg0\twireguard\tup\t--\t1500' "$(network::conn::list | grep '^wg0')" "list: empty MAC → --"
    local w
    w="$(with_fakes network::conn::wifi::scan)"
    testframework::assert_equal $'*\tHome:5G\t82\tWPA2\t36' "$(sed -n 1p <<< "${w}")" "wifi: in-use network first"
    testframework::assert_equal $'--\tNeighbour\t55\tWPA1 WPA2\t11' "$(sed -n 2p <<< "${w}")" "wifi: strongest duplicate kept"
    testframework::assert_equal $'--\tCafe\t40\t--\t6' "$(sed -n 3p <<< "${w}")" "wifi: open network has -- security"
    testframework::assert_equal "3" "$(wc -l <<< "${w}" | tr -d ' ')" "wifi: hidden (--) and duplicates dropped"
    testframework::assert_equal "0" "$(with_fakes network::conn::wifi::known 'Home:5G' && printf 0 || printf 1)" "wifi known: saved profile"
    testframework::assert_equal "1" "$(with_fakes network::conn::wifi::known 'Cafe' && printf 0 || printf 1)" "wifi known: not saved"
    testframework::assert_equal "1" "$(NETCONN_TEST_NM=0 with_fakes network::conn::nm::available && printf 0 || printf 1)" "nm available: stopped"
    testframework::assert_equal "1" "$(without_tools network::conn::nm::available && printf 0 || printf 1)" "nm available: no nmcli"
}

test_actions() {
    testframework::section "actions / действия"
    : > "${NETCONN_TEST_LOG}"
    with_fakes network::conn::up wlan0
    testframework::assert_equal "1" "$(has "$(cat "${NETCONN_TEST_LOG}")" "nmcli device connect wlan0")" "up: NM-managed → nmcli device connect"
    : > "${NETCONN_TEST_LOG}"
    with_fakes network::conn::nm::up "Office"
    testframework::assert_equal "1" "$(has "$(cat "${NETCONN_TEST_LOG}")" "nmcli connection up id Office")" "nm up by name uses id"
    : > "${NETCONN_TEST_LOG}"
    with_fakes network::conn::nm::down "11111111-2222-3333-4444-555555555555"
    testframework::assert_equal "1" "$(has "$(cat "${NETCONN_TEST_LOG}")" "nmcli connection down uuid 11111111-2222-3333-4444-555555555555")" "nm down by uuid uses uuid"
    : > "${NETCONN_TEST_LOG}"
    with_fakes network::conn::wifi::connect "Cafe" "" wlan0
    testframework::assert_equal "nmcli device wifi connect Cafe ifname wlan0" "$(grep 'wifi connect' "${NETCONN_TEST_LOG}")" "wifi connect without password"
    local rc=0
    with_fakes network::conn::up 'eth0;reboot' 2>/dev/null || rc=$?
    testframework::assert_equal "2" "${rc}" "up: refuses a bad interface name"
    rc=0
    with_fakes network::conn::up '-x' 2>/dev/null || rc=$?
    testframework::assert_equal "2" "${rc}" "up: refuses an option-like name"
    rc=0
    with_fakes network::conn::wifi::radio maybe 2>/dev/null || rc=$?
    testframework::assert_equal "2" "${rc}" "radio: only on|off"
    if (( EUID != 0 )) && ! { command -v sudo >/dev/null && sudo -n true 2>/dev/null; }; then
        rc=0
        with_fakes network::conn::up eth0 2>/dev/null || rc=$?
        testframework::assert_equal "126" "${rc}" "up unmanaged without root → 126"
    else
        : > "${NETCONN_TEST_LOG}"
        with_fakes network::conn::up eth0
        testframework::assert_equal "1" "$(has "$(cat "${NETCONN_TEST_LOG}")" "ip link set dev eth0 up")" "up unmanaged → ip link set up"
    fi
}

# @description Dump the TUI buffer as text lines / Вывести буфер TUI строками текста.
screen() {
    local -i r c
    local line
    for (( r = 0; r < TUI_LINES; r++ )); do
        line=""
        for (( c = 0; c < TUI_COLS; c++ )); do line+="${TUI_BUF[${r},${c}]:- }"; done
        printf '%s\n' "${line%"${line##*[! ]}"}"
    done
}

test_tui() {
    testframework::section "TUI frame / кадр TUI"
    testframework::assert_equal "1.5 KB" "$(network::conn::tui::bytes 1536)" "bytes KB"
    testframework::assert_equal "ab… " "$(network::conn::tui::fit 'abcdef' 3; printf ' ')" "fit cuts with ellipsis"
    testframework::assert_equal "▁▄█" "$(network::conn::tui::spark 3 0 50 100)" "spark scales to max"
    testframework::assert_equal "▂▄▆█" "$(network::conn::tui::bars 90)" "signal bars"
    PATH="${FIX}/bin:${PATH}"
    TUI_COLS=100 TUI_LINES=24
    network::conn::tui::__styles
    network::conn::tui::probe
    network::conn::tui::reload
    network::conn::tui::sample
    NET_TUI_SEL[if]=2
    network::conn::tui::draw
    local s
    s="$(screen)"
    testframework::assert_equal "1" "$(has "${s}" "NetworkManager: да")" "title shows NetworkManager"
    testframework::assert_equal "1" "$(has "${s}" "10.0.0.254 (eth0)")" "title shows default route"
    testframework::assert_equal "1" "$(has "${s}" "Интерфейсы 6")" "interfaces tab with count"
    testframework::assert_equal "1" "$(has "${s}" "192.168.1.20/24")" "list shows IPv4 of wlan0"
    testframework::assert_equal "1" "$(has "${s}" "eth0 · ethernet")" "details of the selected interface"
    testframework::assert_equal "1" "$(has "${s}" "1000 Мбит/с")" "details show link speed"
    TUI_KEY="TAB"
    network::conn::tui::key
    network::conn::tui::draw
    s="$(screen)"
    testframework::assert_equal "1" "$(has "${s}" "Home:5G")" "profiles view lists NM profiles"
    testframework::assert_equal "1" "$(has "${s}" "профиль     Home:5G")" "profile details on the right"
    testframework::assert_equal "1" "$(has "${s}" "Трафик · wlan0")" "traffic follows the profile device"
    : > "${NETCONN_TEST_LOG}"
    TUI_KEY="ENTER"
    network::conn::tui::key
    testframework::assert_equal "confirm" "${NET_TUI_MODAL}" "Enter on an active profile asks first"
    TUI_KEY="y"
    tui::render() { :; }
    network::conn::tui::key
    testframework::assert_equal "1" "$(has "$(cat "${NETCONN_TEST_LOG}")" "nmcli connection down uuid 11111111-2222-3333-4444-555555555555")" "confirm → profile down"
    TUI_KEY="w"
    network::conn::tui::key
    testframework::assert_equal "wifi" "${NET_TUI_MODAL}" "w opens the Wi-Fi list"
    network::conn::tui::draw
    s="$(screen)"
    testframework::assert_equal "1" "$(has "${s}" "Wi-Fi · 3 сетей")" "Wi-Fi modal title"
    TUI_KEY="DOWN"; network::conn::tui::key
    TUI_KEY="ENTER"; network::conn::tui::key
    testframework::assert_equal "input" "${NET_TUI_MODAL}" "protected unknown network asks for a password"
    local ch
    for ch in s e c r e t; do TUI_KEY="${ch}"; network::conn::tui::key; done
    network::conn::tui::draw
    s="$(screen)"
    testframework::assert_equal "0" "$(has "${s}" "secret")" "password is masked on screen"
    testframework::assert_equal "1" "$(has "${s}" "••••••")" "mask dots shown"
    : > "${NETCONN_TEST_LOG}"
    TUI_KEY="ENTER"; network::conn::tui::key
    testframework::assert_equal "nmcli device wifi connect Neighbour password secret" "$(grep 'wifi connect' "${NETCONN_TEST_LOG}")" "Enter connects with the typed password"
    testframework::assert_equal "" "${NET_TUI_M[buf]:-}" "password buffer cleared after use"
    TUI_COLS=60
    network::conn::tui::draw
    testframework::assert_equal "1" "$(has "$(screen)" "Окно мало")" "small window warning"
    TUI_KEY="q"
    local rc=0
    network::conn::tui::key || rc=$?
    testframework::assert_equal "1" "${rc}" "q quits"
}

main() {
    print_header "Network connections Unit Tests / Модульные тесты сетевых подключений"
    testframework::init
    setup_fixture
    test_sysfs
    test_routes_dns
    test_nmcli
    test_actions
    test_tui
    testframework::summary
}

main "$@"
