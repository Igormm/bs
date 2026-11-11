[↑ Documentation index](../README.md)

# Module `vpn` — VPN/proxy client on the sing-box and Xray cores

A wrapper around ready-made cores: [sing-box](https://github.com/SagerNet/sing-box)
(>= 1.12, tested with 1.14.4) is the main one, [Xray-core](https://github.com/XTLS/Xray-core)
(>= 24.11, tested with 26.3.27) is the second. BS does not implement any
protocol itself: it stores profiles, imports share links, WireGuard configs and
subscriptions, renders the core's JSON config, runs and supervises the core,
and talks to it through its API. On top sits a full-screen TUI and a CLI
(`examples/vpn.sh`).

Why two cores: sing-box speaks every protocol below in one binary (Xray has no
Hysteria/TUIC/AnyTLS/NaiveProxy) and ships TUN mode, rule-sets and the Clash
API. Xray alone has the XHTTP (`splithttp`) transport and VLESS encryption
(`mlkem768x25519plus`). The `core` setting chooses: `auto` (default) runs a
profile on Xray only when only Xray can dial it.

Tier: **gnu-linux** for `core.sh`/`tui.sh` (process control, `/proc`, `setsid`,
TUN). `link.sh`, `store.sh`, `singbox.sh` and `xray.sh` are pure bash and portable.

Source: [lib/network/vpn/](../../../lib/network/vpn/)

| File | Namespace | Job |
|---|---|---|
| `link.sh` | `vpn::link::*` | share links and WireGuard `.conf` ⇄ profile records, base64, subscription bodies, which core a profile needs |
| `store.sh` | `vpn::store::*`, `vpn::settings::*`, `vpn::sub::*` | profiles, settings, subscriptions on disk |
| `singbox.sh` | `vpn::singbox::*` | sing-box JSON (outbounds, WireGuard endpoints, inbounds, DNS, routing, Clash API) |
| `xray.sh` | `vpn::xray::*` | Xray JSON (outbounds, balancer, observatory, routing, stats API) |
| `core.sh` | `vpn::core::*` | install, core choice, start/stop, status, live switch, latency, exit IP, systemd |
| `tui.sh` | `vpn::tui::*` | full-screen client on `lib/tui/tui` |

## Protocols

| Protocol | Link schemes | Features | Core |
|---|---|---|---|
| VLESS | `vless://` | TLS, REALITY, uTLS fingerprint, `xtls-rprx-vision`, ws/grpc/http/httpupgrade/quic | both (http/quic: sing-box) |
| VLESS + XHTTP | `vless://…?type=xhttp` (or `splithttp`) | `mode`, `extra` (JSON), REALITY/TLS | Xray |
| VLESS encryption | `vless://…?encryption=mlkem768x25519plus…` | post-quantum VLESS encryption | Xray |
| VMess | `vmess://` (base64 JSON) | TLS, transports, `alterId`, cipher | both |
| Trojan | `trojan://` | TLS, transports | both |
| Shadowsocks | `ss://` (SIP002, legacy, 2022 ciphers) | `obfs-local`/`v2ray-plugin` (sing-box) | both |
| Hysteria2 | `hysteria2://`, `hy2://` | Salamander obfs, port hopping (`443,20000-30000`, `mport=`) | sing-box |
| Hysteria | `hysteria://`, `hy://` | up/down Mbps, obfs, auth | sing-box |
| TUIC v5 | `tuic://` | congestion control, UDP relay mode | sing-box |
| AnyTLS | `anytls://` | TLS | sing-box |
| WireGuard | `wireguard://`, `wg://`, a `.conf` file | pre-shared key, `reserved` (WARP), MTU, keepalive | both |
| NaiveProxy | `naive+https://`, `naive+quic://` | HTTP/2 or QUIC, `insecure-concurrency` | sing-box (needs `libcronet.so`, shipped with the official build) |
| SOCKS5 | `socks://`, `socks5://` | user/password | both |

Xray no longer accepts `allowInsecure` (removed in 2026): a self-signed server
needs the certificate hash in the link (`pcs=<sha256>`), which is passed to Xray
as `pinnedPeerCertSha256`.

## Quick start

```bash
./bs run examples/vpn.sh core install          # sing-box into ~/.local/share/bs/vpn/bin
./bs run examples/vpn.sh core install xray     # Xray with geoip.dat/geosite.dat (for XHTTP)
./bs run examples/vpn.sh import 'vless://…'    # or a WireGuard .conf, or: sub add mysub https://…
./bs run examples/vpn.sh connect               # proxy mode: SOCKS5/HTTP on 127.0.0.1:2080
./bs run examples/vpn.sh                       # TUI
```

## Library use

```bash
#!/usr/bin/env bs

load "lib/network/vpn/core"

id="$(vpn::store::import 'trojan://secret@example.com:443?sni=example.com#DE')"
vpn::settings::set route bypass-ru
vpn::core::start "${id}"
vpn::core::status
vpn::core::stop
```

## Storage

| Path | Content |
|---|---|
| `${BS_VPN_HOME:-~/.config/bs/vpn}/profiles/<id>.conf` | profile record, `key=value` (never sourced) |
| `…/profiles/.order` | display order |
| `…/subs/<name>.conf` | subscription URL, last update, count |
| `…/settings.conf` | settings |
| `${BS_VPN_STATE:-~/.local/state/bs/vpn}/` | `config.json`, `core.pid`, `core.log`, `session`, `latency.tsv`, `cache.db` |
| `${BS_VPN_BIN_DIR:-~/.local/share/bs/vpn/bin}/` | downloaded cores: `sing-box` (+ `libcronet.so`), `xray` (+ `geoip.dat`, `geosite.dat`) |

`BS_VPN_CORE` and `BS_VPN_XRAY` point at specific binaries. All files are
written atomically with mode 600.

## Settings

| Key | Values | Meaning |
|---|---|---|
| `core` | `auto`, `sing-box`, `xray` | which core runs the connection; `auto` picks Xray only for profiles only Xray can dial |
| `mode` | `proxy`, `tun` | local SOCKS5/HTTP proxy, or the whole system through a TUN device (root, sing-box only) |
| `route` | `global`, `bypass-ru`, `bypass-cn`, `bypass-ir`, `direct` | routing preset; sing-box uses SagerNet rule-sets, Xray uses `geosite`/`geoip` files (domain zones only without them) |
| `auto_select` | `0`/`1` | pick the fastest server of the group (sing-box urltest, Xray leastPing) |
| `listen_port`, `allow_lan`, `system_proxy` | | local proxy |
| `tun_stack`, `tun_mtu`, `strict_route`, `ipv6` | | TUN; `strict_route=1` is the kill switch |
| `dns_remote`, `dns_direct` | `https://…`, `tls://…`, IP, `local` | split DNS (Xray has no DoT client: `tls://host` becomes DoH on the same host) |
| `block_ads`, `direct_domains`, `proxy_domains`, `block_domains` | | extra rules |
| `log_level`, `api_port`, `test_url` | | core log, API port, delay URL (https only) |

## How a connection is built

1. `vpn::core::engine_for` picks the core from the `core` setting and the
   selected profile. The profile and the rest of its group that this core can
   dial (up to 200) go into one config.
2. sing-box: a `proxy` selector, an `auto` urltest group and one outbound each
   (WireGuard as an endpoint). Xray: one outbound per profile tagged `p:<id>`
   and a `proxy` balancer over them (leastPing with the observatory when there
   are several).
3. The core validates the config (`sing-box check`, `xray run -test`); a
   profile the core rejects is dropped and reported (`VPN_CORE_PRUNED`), so
   one broken subscription entry does not break the connection.
4. The core starts detached (`setsid`/`nohup`); TUN mode goes through
   `sudo -n` and fails with a clear message when sudo needs a password.
5. Switching to another server of the same group happens live: a Clash API
   call on sing-box, a balancer override (`xray api bo`) on Xray. A server the
   running core cannot dial restarts the connection on the other core.

Latency (`vpn::core::test_real`) runs temporary cores and never touches the
running tunnel: sing-box measures through its Clash API delay test, profiles
only Xray can dial go through a temporary Xray with one local SOCKS port per
profile. Both work for UDP protocols. `vpn::core::test_tcp` is a core-free TCP
connect time.

Traffic counters come from the Clash API (sing-box) or the stats API (Xray,
which does not count connections).

## TUI keys

`↑↓` select · `Enter` connect/switch · `d` disconnect · `r` reconnect ·
`t`/`T` test one/all · `S` sort by latency · `a` auto select · `i` import
(paste works, a WireGuard `.conf` too) · `s` subscriptions · `o` settings
(the core too) · `m` proxy↔tun · `g` route preset · `e` link + QR · `x` delete ·
`p` exit IP · `l` log · `/` search · `?` help · `q` quit (VPN keeps running) ·
`Q` quit and disconnect. The title shows the running core, the profile panel
shows which core a profile runs on.

## Tests

`tests/unit/testvpnunit.sh` — links of every protocol, WireGuard `.conf`,
round trips, store, settings validation, subscriptions over `file://`,
sing-box and Xray rendering, core choice, pruning, start/stop and live switch
with fake cores, TUI frame and keys. Set `BS_VPN_TEST_CORE=/path/to/sing-box`
and `BS_VPN_TEST_XRAY=/path/to/xray` to also validate configs with the real cores.
