[↑ Documentation index](../README.md)

# Module `vpn` — VPN/proxy client on the sing-box core

A wrapper around the ready-made [sing-box](https://github.com/SagerNet/sing-box)
core (>= 1.12, tested with 1.14.4). BS does not implement any protocol itself:
it stores profiles, imports share links and subscriptions, renders the core's
JSON config, runs and supervises the core, and talks to it through the Clash
API. On top sits a full-screen TUI and a CLI (`examples/vpn.sh`).

Why sing-box and not Xray: sing-box is the only core that speaks every
protocol below as a client in one binary (Xray has no Hysteria/TUIC), and it
ships TUN mode, rule-sets, selector/urltest groups and the Clash API.
Limitation: Xray-only transports (`xhttp`/`splithttp`) are rejected at import.

Tier: **gnu-linux** for `core.sh`/`tui.sh` (process control, `/proc`, `setsid`,
TUN). `link.sh`, `store.sh` and `singbox.sh` are pure bash and portable.

Source: [lib/network/vpn/](../../../lib/network/vpn/)

| File | Namespace | Job |
|---|---|---|
| `link.sh` | `vpn::link::*` | share links ⇄ profile records, base64, subscription bodies |
| `store.sh` | `vpn::store::*`, `vpn::settings::*`, `vpn::sub::*` | profiles, settings, subscriptions on disk |
| `singbox.sh` | `vpn::singbox::*` | sing-box JSON (outbounds, inbounds, DNS, routing, Clash API) |
| `core.sh` | `vpn::core::*` | install, start/stop, status, live switch, latency, exit IP, systemd |
| `tui.sh` | `vpn::tui::*` | full-screen client on `lib/tui/tui` |

## Protocols

| Protocol | Link schemes | Features |
|---|---|---|
| VLESS | `vless://` | TLS, REALITY, uTLS fingerprint, `xtls-rprx-vision`, ws/grpc/http/httpupgrade/quic |
| VMess | `vmess://` (base64 JSON) | TLS, transports, `alterId`, cipher |
| Trojan | `trojan://` | TLS, transports |
| Shadowsocks | `ss://` (SIP002, legacy, 2022 ciphers) | `obfs-local`/`v2ray-plugin` |
| Hysteria2 | `hysteria2://`, `hy2://` | Salamander obfs, port hopping (`443,20000-30000`, `mport=`) |
| Hysteria | `hysteria://`, `hy://` | up/down Mbps, obfs, auth |
| TUIC v5 | `tuic://` | congestion control, UDP relay mode |
| AnyTLS | `anytls://` | TLS |
| SOCKS5 | `socks://`, `socks5://` | user/password |

## Quick start

```bash
./bs run examples/vpn.sh core install          # sing-box into ~/.local/share/bs/vpn/bin
./bs run examples/vpn.sh import 'vless://…'    # or: sub add mysub https://…
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
| `${BS_VPN_STATE:-~/.local/state/bs/vpn}/` | `config.json`, `sing-box.pid`, `sing-box.log`, `session`, `latency.tsv`, `cache.db` |
| `${BS_VPN_BIN_DIR:-~/.local/share/bs/vpn/bin}/sing-box` | downloaded core |

`BS_VPN_CORE` points at a specific binary. All files are written atomically
with mode 600.

## Settings

| Key | Values | Meaning |
|---|---|---|
| `mode` | `proxy`, `tun` | local SOCKS5/HTTP proxy, or the whole system through a TUN device (root) |
| `route` | `global`, `bypass-ru`, `bypass-cn`, `bypass-ir`, `direct` | routing preset; bypass presets send the country's sites direct via SagerNet rule-sets |
| `auto_select` | `0`/`1` | pick the fastest server of the group (urltest) |
| `listen_port`, `allow_lan`, `system_proxy` | | local proxy |
| `tun_stack`, `tun_mtu`, `strict_route`, `ipv6` | | TUN; `strict_route=1` is the kill switch |
| `dns_remote`, `dns_direct` | `https://…`, `tls://…`, IP, `local` | split DNS |
| `block_ads`, `direct_domains`, `proxy_domains`, `block_domains` | | extra rules |
| `log_level`, `api_port`, `test_url` | | core log, Clash API port, delay URL (https only) |

## How a connection is built

1. The selected profile and the rest of its group (up to 200) go into one
   config: a `proxy` selector, an `auto` urltest group and one outbound each.
2. `sing-box check` validates it; a profile the core rejects is dropped and
   reported (`VPN_CORE_PRUNED`), so one broken subscription entry does not
   break the connection.
3. The core starts detached (`setsid`/`nohup`); TUN mode goes through
   `sudo -n` and fails with a clear message when sudo needs a password.
4. Switching to another server of the same group is a Clash API call: no
   restart, open connections are moved.

Latency (`vpn::core::test_real`) runs a temporary core with only the outbounds
and asks the Clash API for every server in parallel, so it works for UDP
protocols too and does not touch the running tunnel. `vpn::core::test_tcp` is
a core-free TCP connect time.

## TUI keys

`↑↓` select · `Enter` connect/switch · `d` disconnect · `r` reconnect ·
`t`/`T` test one/all · `S` sort by latency · `a` auto select · `i` import
(paste works) · `s` subscriptions · `o` settings · `m` proxy↔tun ·
`g` route preset · `e` link + QR · `x` delete · `p` exit IP · `l` log ·
`/` search · `?` help · `q` quit (VPN keeps running) · `Q` quit and disconnect.

## Tests

`tests/unit/testvpnunit.sh` — links of every protocol, round trips, store,
settings validation, subscriptions over `file://`, outbound and config
rendering, pruning and start/stop with a fake core, TUI frame and keys. Set
`BS_VPN_TEST_CORE=/path/to/sing-box` to also validate configs with the real core.
