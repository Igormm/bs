#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testvpnunit.sh — unit tests for lib/network/vpn (links, store, sing-box config, core, TUI)
# tests/unit/testvpnunit.sh — юнит-тесты lib/network/vpn (ссылки, хранилище, конфиг sing-box, ядро, TUI)
#
# A fake "sing-box" script stands in for the core, so the run needs no network
# and no real binary. When a real sing-box is on PATH (or BS_VPN_TEST_CORE
# points at one), the generated configs are also checked with "sing-box check".
# Ядро заменяет поддельный скрипт «sing-box»: сеть и настоящий бинарник не
# нужны. Если настоящий sing-box есть в PATH (или в BS_VPN_TEST_CORE),
# сгенерированные конфиги дополнительно проверяются «sing-box check».

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

load "lib/network/vpn/tui"

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

readonly REALITY='vless://b831381d-6324-4d53-ad4f-8cda48b30811@1.2.3.4:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=SbVKOEMjK0sIlbwg4akyBg5mL5KZwwB-ed4eEE7YnRc&sid=6ba85179e30d4fc2&type=tcp#%F0%9F%87%A9%F0%9F%87%AA%20DE%20Reality'
readonly VLESS_WS='vless://b831381d-6324-4d53-ad4f-8cda48b30811@ex.com:443?security=tls&type=ws&path=%2Fws%3Fed%3D2048&host=cdn.ex.com#WS'
readonly TROJAN='trojan://p%40ss:word@[2001:db8::1]:8443?type=grpc&serviceName=gun#T'
readonly SS='ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ@5.6.7.8:8388#SS'
readonly SS_LEGACY='ss://YWVzLTEyOC1nY206dGVzdEAxOTIuMTY4LjEwMC4xOjg4ODg#legacy'
readonly SS22='ss://2022-blake3-aes-128-gcm:YctPZ6U7xPPcU%2Bgp3u%2B0tw%3D%3D@1.1.1.1:443#SS22'
readonly HY2='hysteria2://letmein@hy.example.com:443,20000-30000/?sni=hy.example.com&obfs=salamander&obfs-password=gawrgura&insecure=1#HY2'
readonly HY1='hysteria://h.com:443?protocol=udp&auth=123&peer=h.com&insecure=1&upmbps=100&downmbps=100&alpn=hysteria#H1'
readonly TUIC='tuic://c1e6dbe2-f417-4890-994c-9ee15b926597:pass@t.com:443?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=t.com#TUIC'
readonly ANYTLS='anytls://pass@a.com:443?sni=a.com&insecure=1#ANY'
readonly SOCKS='socks://dXNlcjpwYXNz@9.9.9.9:1080#S'
readonly VMESS='vmess://eyJ2IjoiMiIsInBzIjoiVk0gXCJxXCIiLCJhZGQiOiJ2LmNvbSIsInBvcnQiOiI0NDMiLCJpZCI6ImEzNDgyZTg4LTY4NmEtNGE1OC04MTI2LTk5YzlkZjY0YjdiZiIsImFpZCI6IjAiLCJzY3kiOiJhdXRvIiwibmV0Ijoid3MiLCJ0eXBlIjoibm9uZSIsImhvc3QiOiJ2LmNvbSIsInBhdGgiOiIvdm0iLCJ0bHMiOiJ0bHMiLCJzbmkiOiJ2LmNvbSJ9'

test_links() {
    testframework::section "links / ссылки"
    local r
    r="$(vpn::link::parse "${REALITY}")"
    testframework::assert_equal "vless" "$(field "${r}" proto)" "vless proto"
    testframework::assert_equal "reality" "$(field "${r}" security)" "vless reality"
    testframework::assert_equal "xtls-rprx-vision" "$(field "${r}" flow)" "vless flow"
    testframework::assert_equal "6ba85179e30d4fc2" "$(field "${r}" sid)" "reality short id"
    testframework::assert_equal "🇩🇪 DE Reality" "$(field "${r}" name)" "utf-8 name decoded"

    r="$(vpn::link::parse "${VLESS_WS}")"
    testframework::assert_equal "/ws?ed=2048" "$(field "${r}" path)" "ws path decoded"
    testframework::assert_equal "cdn.ex.com" "$(field "${r}" host)" "ws host"

    r="$(vpn::link::parse "${TROJAN}")"
    testframework::assert_equal "2001:db8::1" "$(field "${r}" server)" "trojan ipv6 server"
    testframework::assert_equal "p@ss:word" "$(field "${r}" password)" "trojan password with @ and :"
    testframework::assert_equal "tls" "$(field "${r}" security)" "trojan implies tls"
    testframework::assert_equal "gun" "$(field "${r}" service_name)" "grpc service"

    r="$(vpn::link::parse "${SS}")"
    testframework::assert_equal "aes-256-gcm" "$(field "${r}" method)" "ss SIP002 method"
    testframework::assert_equal "password" "$(field "${r}" password)" "ss SIP002 password"
    r="$(vpn::link::parse "${SS_LEGACY}")"
    testframework::assert_equal "192.168.100.1" "$(field "${r}" server)" "ss legacy server"
    testframework::assert_equal "8888" "$(field "${r}" port)" "ss legacy port"
    r="$(vpn::link::parse "${SS22}")"
    testframework::assert_equal "YctPZ6U7xPPcU+gp3u+0tw==" "$(field "${r}" password)" "ss 2022 plain userinfo"

    r="$(vpn::link::parse "${HY2}")"
    testframework::assert_equal "443" "$(field "${r}" port)" "hy2 first port"
    testframework::assert_equal "443,20000-30000" "$(field "${r}" ports)" "hy2 port hopping"
    testframework::assert_equal "gawrgura" "$(field "${r}" obfs_password)" "hy2 obfs password"
    testframework::assert_equal "1" "$(field "${r}" insecure)" "hy2 insecure"
    r="$(vpn::link::parse 'hy2://pw@h.com:8443?mport=1000-2000#x')"
    testframework::assert_equal "hysteria2" "$(field "${r}" proto)" "hy2 short scheme"
    testframework::assert_equal "1000-2000" "$(field "${r}" ports)" "hy2 mport"

    r="$(vpn::link::parse "${HY1}")"
    testframework::assert_equal "123" "$(field "${r}" auth)" "hysteria auth"
    testframework::assert_equal "100" "$(field "${r}" up_mbps)" "hysteria up"

    r="$(vpn::link::parse "${TUIC}")"
    testframework::assert_equal "pass" "$(field "${r}" password)" "tuic password"
    testframework::assert_equal "bbr" "$(field "${r}" congestion)" "tuic congestion"

    r="$(vpn::link::parse "${ANYTLS}")"
    testframework::assert_equal "anytls" "$(field "${r}" proto)" "anytls"
    r="$(vpn::link::parse "${SOCKS}")"
    testframework::assert_equal "user" "$(field "${r}" username)" "socks base64 userinfo"

    r="$(vpn::link::parse "${VMESS}")"
    testframework::assert_equal 'VM "q"' "$(field "${r}" name)" "vmess escaped name"
    testframework::assert_equal "ws" "$(field "${r}" transport)" "vmess transport"
    testframework::assert_equal "/vm" "$(field "${r}" path)" "vmess path"

    local rc=0
    vpn::link::parse 'vless://u@h:99999#bad' >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_INPUT}" "${rc}" "port out of range rejected"
    rc=0; vpn::link::parse 'foo://x' >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_INPUT}" "${rc}" "unknown scheme rejected"
    rc=0; vpn::link::parse 'vless://not;a;uuid@h.com:443#x' >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_INPUT}" "${rc}" "bad uuid rejected"
    rc=0; vpn::link::parse 'vless://u@h.com:443?type=xhttp#x' >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_INPUT}" "${rc}" "xhttp (Xray only) rejected"
    r="$(vpn::link::parse 'trojan://pw@h.com:443#evil%0Aproto%3Dsocks%0D')"
    testframework::assert_equal "1" "$(printf '%s\n' "${r}" | grep -c '^proto=')" "newline in name cannot inject a field"

    testframework::section "round trip / ссылка → профиль → ссылка"
    local link a b key
    for link in "${REALITY}" "${VLESS_WS}" "${TROJAN}" "${SS}" "${SS22}" "${HY2}" "${HY1}" "${TUIC}" "${ANYTLS}" "${SOCKS}" "${VMESS}"; do
        a="$(vpn::link::parse "${link}")"
        b="$(printf '%s\n' "${a}" | vpn::link::build)"
        b="$(vpn::link::parse "${b}")"
        for key in proto server port uuid password method security sni pbk sid transport path service_name obfs_password; do
            if [[ "$(field "${a}" "${key}")" != "$(field "${b}" "${key}")" ]]; then
                testframework::assert_equal "$(field "${a}" "${key}")" "$(field "${b}" "${key}")" "round trip ${link%%:*} ${key}"
            fi
        done
        testframework::assert_equal "$(field "${a}" name)" "$(field "${b}" name)" "round trip ${link%%:*} keeps fields"
    done

    testframework::section "base64 / подписки"
    testframework::assert_equal "aes-256-gcm:password" "$(vpn::link::b64decode 'YWVzLTI1Ni1nY206cGFzc3dvcmQ')" "url-safe without padding"
    local body
    body="$(printf '%s\n%s\nnot a link\n' "${SS}" "${TROJAN}" | base64 | tr -d '\n')"
    testframework::assert_equal "2" "$(vpn::link::subscription_links "${body}" | wc -l | tr -d ' ')" "base64 subscription body"
    testframework::assert_equal "1" "$(vpn::link::subscription_links "${SS}" | wc -l | tr -d ' ')" "plain subscription body"
}

test_store() {
    testframework::section "store / хранилище"
    local id id2 rc
    id="$(vpn::store::import "${REALITY}" sub1)"
    testframework::assert_equal "de-reality" "${id}" "slug from the name (emoji dropped)"
    id2="$(vpn::store::import "${REALITY}" sub1)"
    testframework::assert_equal "${id}" "${id2}" "same server in the same group updates in place"
    id2="$(vpn::store::import "${REALITY}" other)"
    testframework::assert_equal "de-reality-2" "${id2}" "same server in another group gets a new id"
    vpn::store::import_text "$(printf '%s\n' "${TROJAN}" "${HY2}" "${TUIC}" "${SS}")" sub1 >/dev/null
    testframework::assert_equal "5" "$(vpn::store::ids sub1 | wc -l | tr -d ' ')" "group listing"
    testframework::assert_equal "de-reality" "$(vpn::store::ids | head -n 1)" "import order kept"
    testframework::assert_equal "sub1" "$(vpn::store::field hy2 group)" "group stored"

    vpn::store::set_field hy2 sni new.example.com
    testframework::assert_equal "new.example.com" "$(vpn::store::field hy2 sni)" "set_field"
    rc=0; vpn::store::set_field hy2 port 0 2>/dev/null || rc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_INPUT}" "${rc}" "set_field validates"
    rc=0; vpn::store::set_field hy2 bogus 1 2>/dev/null || rc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_ARGS}" "${rc}" "set_field unknown key"
    rc=0; vpn::store::get '../etc/passwd' >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "${LIB_ERROR_FILE_NOT_FOUND}" "${rc}" "path traversal id rejected"

    vpn::store::remove de-reality-2
    testframework::assert_equal "0" "$(grep -c '^de-reality-2$' "${BS_VPN_HOME}/profiles/.order" || true)" "remove drops the id from the order"

    testframework::section "settings / настройки"
    testframework::assert_equal "proxy" "$(vpn::settings::get mode)" "default mode"
    vpn::settings::set mode tun
    testframework::assert_equal "tun" "$(vpn::settings::get mode)" "set mode"
    rc=0; vpn::settings::set mode vpn 2>/dev/null || rc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_INPUT}" "${rc}" "enum validated"
    rc=0; vpn::settings::set listen_port 70000 2>/dev/null || rc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_INPUT}" "${rc}" "port validated"
    rc=0; vpn::settings::set dns_remote 'https://dns.google/dns-query' || rc=$?
    testframework::assert_equal "0" "${rc}" "doh url accepted"
    rc=0; vpn::settings::set dns_remote 'https://x/"; rm -rf /' 2>/dev/null || rc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_INPUT}" "${rc}" "dns injection rejected"
    rc=0; vpn::settings::set test_url 'http://example.com/' 2>/dev/null || rc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_INPUT}" "${rc}" "http test url rejected (core ignores it)"
    rc=0; vpn::settings::set direct_domains 'example.org,local.lan' || rc=$?
    testframework::assert_equal "0" "${rc}" "domain list accepted"
    local s1 s2
    s1="$(vpn::settings::secret)"; s2="$(vpn::settings::secret)"
    testframework::assert_equal "32" "${#s1}" "secret generated"
    testframework::assert_equal "${s1}" "${s2}" "secret stable"
    vpn::settings::set mode proxy

    testframework::section "subscriptions / подписки"
    local subfile="${BS_VPN_HOME}/../sub.txt"
    printf '%s\n%s\n' "${ANYTLS}" "${SOCKS}" | base64 > "${subfile}"
    vpn::sub::add mysub "file://${subfile}"
    testframework::assert_equal "2" "$(vpn::sub::update mysub)" "subscription imported"
    printf '%s\n' "${ANYTLS}" | base64 > "${subfile}"
    testframework::assert_equal "1" "$(vpn::sub::update mysub)" "subscription updated"
    testframework::assert_equal "1" "$(vpn::store::ids mysub | wc -l | tr -d ' ')" "vanished server removed"
    testframework::assert_equal "1" "$(vpn::sub::list | grep -c '^mysub')" "subscription listed"
    rc=0; vpn::sub::add 'Bad Name' "https://x" 2>/dev/null || rc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_INPUT}" "${rc}" "subscription name validated"
    vpn::sub::remove mysub
    testframework::assert_equal "0" "$(vpn::store::ids mysub | wc -l | tr -d ' ')" "subscription removal drops servers"
}

test_singbox() {
    testframework::section "sing-box outbounds / outbound"
    local -A p=()
    local ob
    vpn::link::read_record p < <(vpn::link::parse "${REALITY}")
    ob="$(vpn::singbox::outbound p r1)"
    testframework::assert_equal "1" "$(has "${ob}" '"reality":{"enabled":true,"public_key":"SbVKOEMjK0sIlbwg4akyBg5mL5KZwwB-ed4eEE7YnRc","short_id":"6ba85179e30d4fc2"}')" "reality block"
    testframework::assert_equal "1" "$(has "${ob}" '"utls":{"enabled":true,"fingerprint":"chrome"}')" "utls fingerprint"
    unset p; local -A p=()
    vpn::link::read_record p < <(vpn::link::parse "${VLESS_WS}")
    ob="$(vpn::singbox::outbound p w1)"
    testframework::assert_equal "1" "$(has "${ob}" '"max_early_data":2048,"early_data_header_name":"Sec-WebSocket-Protocol"')" "ws early data"
    testframework::assert_equal "1" "$(has "${ob}" '"path":"/ws"')" "ws path without ?ed"
    unset p; local -A p=()
    vpn::link::read_record p < <(vpn::link::parse "${HY2}")
    ob="$(vpn::singbox::outbound p h2)"
    testframework::assert_equal "1" "$(has "${ob}" '"server_ports":["443:443","20000:30000"]')" "hy2 server_ports"
    testframework::assert_equal "0" "$(has "${ob}" '"server_port"')" "hy2 server_port omitted with hopping"
    testframework::assert_equal "1" "$(has "${ob}" '"obfs":{"type":"salamander","password":"gawrgura"}')" "hy2 obfs"
    testframework::assert_equal "1" "$(has "${ob}" '"alpn":["h3"]')" "hy2 default alpn"
    unset p; local -A p=()
    vpn::link::read_record p < <(vpn::link::parse "${VMESS}")
    ob="$(vpn::singbox::outbound p v1)"
    testframework::assert_equal "1" "$(has "${ob}" '"security":"auto"')" "vmess cipher"

    testframework::section "sing-box config / конфиг"
    vpn::settings::set route bypass-ru
    vpn::settings::set block_ads 1
    vpn::settings::set mode tun
    local -a ids=()
    mapfile -t ids < <(vpn::store::ids sub1)
    local cfg
    cfg="$(VPN_SINGBOX_VERSION=1.14.4 vpn::singbox::config "${ids[@]}")"
    testframework::assert_equal "1" "$(has "${cfg}" '"type":"tun"')" "tun inbound"
    testframework::assert_equal "1" "$(has "${cfg}" '"geosite-category-ru"')" "bypass-ru rule-set"
    testframework::assert_equal "1" "$(has "${cfg}" '"rule_set":["geosite-category-ads-all"],"action":"reject"')" "ads blocked"
    testframework::assert_equal "1" "$(has "${cfg}" '"http_clients":[{"tag":"bs-fetch","detour":"proxy"}]')" "1.14 http client for rule-sets"
    testframework::assert_equal "1" "$(has "${cfg}" '"tag":"auto"')" "urltest group"
    testframework::assert_equal "1" "$(has "${cfg}" "\"default\":\"${ids[0]}\"")" "selector default = selected"
    testframework::assert_equal "1" "$(has "${cfg}" '"domain_suffix":["example.org","local.lan"],"outbound":"direct"')" "custom direct domains"
    cfg="$(VPN_SINGBOX_VERSION=1.12.3 vpn::singbox::config "${ids[@]}")"
    testframework::assert_equal "1" "$(has "${cfg}" '"download_detour":"proxy"')" "pre-1.14 download_detour"
    testframework::assert_equal "0" "$(has "${cfg}" 'http_clients')" "pre-1.14 has no http_clients"
    testframework::assert_true "\"\$(VPN_SINGBOX_VERSION=1.11.0; vpn::singbox::version_ge 1.12 && echo y || echo n)\" == n" "version_ge older"
    if is::command jq; then
        local jrc=0
        printf '%s' "${cfg}" | jq -e . >/dev/null 2>&1 || jrc=$?
        testframework::assert_equal "0" "${jrc}" "config is valid JSON (jq)"
    else
        testframework::skip "config is valid JSON (jq)" "jq not installed"
    fi
    local real="${BS_VPN_TEST_CORE:-}"
    is::empty "${real}" && real="$(command -v sing-box 2>/dev/null || true)"
    if is::not_empty "${real}" && "${real}" version >/dev/null 2>&1; then
        local f="${BS_VPN_HOME}/../real.json" crc=0
        vpn::singbox::config "${ids[@]}" > "${f}"
        "${real}" check -c "${f}" >/dev/null 2>&1 || crc=$?
        testframework::assert_equal "0" "${crc}" "real sing-box accepts the config"
    else
        testframework::skip "real sing-box check" "sing-box not installed (set BS_VPN_TEST_CORE)"
    fi
    vpn::settings::set route global
    vpn::settings::set block_ads 0
    vpn::settings::set mode proxy
}

# @description Fake core: "check" fails on a marked profile, "run" logs "started" and idles.
make_fake_core() {
    local -r path="$1"
    cat > "${path}" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  version) echo "sing-box version 1.14.4"; exit 0 ;;
  check)
    if grep -q 'bad.example' "$3"; then echo "FATAL[0000] initialize outbound[${FAKE_BAD_INDEX:-3}]: bad key length"; exit 1; fi
    exit 0 ;;
  run)
    echo "INFO[0000] sing-box started (0.00s)"
    trap 'exit 0' TERM INT
    while :; do sleep 1; done ;;
esac
EOF
    chmod +x "${path}"
}

test_core() {
    testframework::section "core / ядро"
    local -r core="${BS_VPN_HOME}/../sing-box"
    make_fake_core "${core}"
    export BS_VPN_CORE="${core}"
    testframework::assert_equal "1.14.4" "$(vpn::core::version)" "version parsed"
    testframework::assert_true "-n \"\$(vpn::core::platform)\"" "platform detected"
    testframework::assert_equal "5" "$(vpn::core::__bad_index 'FATAL initialize outbound[5]: x')" "bad index parsed"

    local bad
    bad="$(vpn::store::import 'trojan://pw@bad.example:443#Bad' sub1)"
    local -a ids=()
    mapfile -t ids < <(vpn::core::config_ids de-reality)
    testframework::assert_equal "de-reality" "${ids[0]}" "selected profile goes first"
    # outbounds: proxy, auto, затем профили — bad последний в группе / bad is last in the group
    export FAKE_BAD_INDEX=$(( ${#ids[@]} + 1 ))
    local f="${BS_VPN_STATE}/t.json" rc=0
    vpn::core::build_config full "${f}" "${ids[@]}" || rc=$?
    testframework::assert_equal "0" "${rc}" "config built after pruning"
    testframework::assert_equal "${bad}" "${VPN_CORE_PRUNED[*]:-}" "rejected profile pruned"
    testframework::assert_equal "0" "$(grep -c 'bad.example' "${f}" || true)" "pruned profile not in config"
    export FAKE_BAD_INDEX=2
    rc=0; vpn::core::build_config full "${f}" "${bad}" de-reality 2>/dev/null || rc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_INPUT}" "${rc}" "rejected selected profile is an error"
    vpn::store::remove "${bad}"
    unset FAKE_BAD_INDEX

    testframework::section "start / stop / запуск и остановка"
    vpn::settings::set api_port 1
    rc=0; vpn::core::start de-reality 2>/dev/null || rc=$?
    testframework::assert_equal "0" "${rc}" "start"
    testframework::assert_true "\"\$(vpn::core::status | grep '^running=')\" == running=1" "running after start"
    testframework::assert_equal "de-reality" "$(vpn::core::session_get id)" "session id"
    testframework::assert_equal "de-reality" "$(vpn::settings::get active)" "active remembered"
    testframework::assert_file_exists "$(vpn::core::config_file)" "config written"
    vpn::core::stop
    testframework::assert_false "vpn::core::running" "stopped"
    vpn::settings::set mode tun
    if (( EUID != 0 )) && ! vpn::core::root_ready; then
        rc=0; vpn::core::start de-reality 2>/dev/null || rc=$?
        testframework::assert_equal "${LIB_ERROR_PERMISSION_DENIED}" "${rc}" "tun without root refused"
    else
        testframework::skip "tun without root refused" "running as root or with passwordless sudo"
    fi
    vpn::settings::set mode proxy

    testframework::section "latency store / замеры"
    vpn::core::latency_save hy2 120
    vpn::core::latency_save hy2 80
    testframework::assert_equal "80" "$(vpn::core::latency_list | awk -F'\t' '$1=="hy2"{print $2}')" "latency replaced"
    BS_VPN_DRY_RUN=1 vpn::core::service_install 2>/dev/null >/dev/null || true
    testframework::assert_equal "1" "$(has "$(vpn::core::service_unit)" "ExecStart=${core} run -c")" "systemd unit"
    unset BS_VPN_CORE
}

test_tui() {
    testframework::section "tui helpers / хелперы TUI"
    testframework::assert_equal "1.5 KB" "$(vpn::tui::bytes 1536)" "bytes KB"
    testframework::assert_equal "2.0 MB" "$(vpn::tui::bytes 2097152)" "bytes MB"
    testframework::assert_equal "1d 01:01:01" "$(vpn::tui::duration 90061)" "duration"
    testframework::assert_equal "Привет    " "$(vpn::tui::fit 'Привет' 10)" "fit pads by characters"
    testframework::assert_equal "Приве…" "$(vpn::tui::fit 'Привет мир' 6)" "fit cuts with ellipsis"
    testframework::assert_equal "DE Reality" "$(vpn::tui::narrow '🇩🇪 DE Reality')" "narrow drops flags"
    testframework::assert_equal "VLESS·R" "$(vpn::tui::proto_label vless reality tcp)" "proto label"
    testframework::assert_equal "a b" "$(vpn::tui::__strip_sgr $'\e[31ma\e[0m b')" "strip sgr"

    testframework::section "tui frame / кадр TUI"
    TUI_COLS=100; TUI_LINES=30
    vpn::tui::__styles
    vpn::tui::reload
    vpn::tui::refresh
    vpn::tui::draw
    local row="" c
    for (( c = 0; c < TUI_COLS; c++ )); do row+="${TUI_BUF[0,${c}]:- }"; done
    testframework::assert_equal "1" "$(has "${row}" 'BS VPN')" "title drawn"
    row=""
    for (( c = 0; c < TUI_COLS; c++ )); do row+="${TUI_BUF[1,${c}]:- }"; done
    testframework::assert_equal "1" "$(has "${row}" 'Серверы')" "server list drawn"
    testframework::assert_true "${#VPN_TUI_IDS[@]} -ge 4" "profiles loaded"
    VPN_TUI_SEL=0
    TUI_KEY="DOWN"; vpn::tui::key
    testframework::assert_equal "1" "${VPN_TUI_SEL}" "down moves selection"
    TUI_KEY="?"; vpn::tui::key
    testframework::assert_equal "text" "${VPN_TUI_MODAL}" "help opens"
    TUI_KEY="ESC"; vpn::tui::key
    testframework::assert_equal "" "${VPN_TUI_MODAL}" "esc closes"
    vpn::tui::__filter_cb "tuic"
    testframework::assert_equal "1" "${#VPN_TUI_IDS[@]}" "filter"
    vpn::tui::__filter_cb ""
    TUI_KEY="q"
    local qrc=0; vpn::tui::key || qrc=$?
    testframework::assert_equal "1" "${qrc}" "q quits"
}

main() {
    print_header "VPN client Unit Tests / Юнит-тесты VPN-клиента"
    testframework::init
    local tmp
    tmp="$(mktemp -d)"
    export BS_VPN_HOME="${tmp}/home" BS_VPN_STATE="${tmp}/state" BS_VPN_BIN_DIR="${tmp}/bin"
    test_links
    test_store
    test_singbox
    test_core
    test_tui
    vpn::core::stop >/dev/null 2>&1 || true
    rm -rf "${tmp}"
    testframework::summary
}

main "$@"
