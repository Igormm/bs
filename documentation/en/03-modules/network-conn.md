[↑ Documentation index](../README.md)

# Module `network/conn`

Network connections on Linux: interfaces and their state, addresses, default
routes and DNS, NetworkManager connection profiles and Wi-Fi, plus a
full-screen TUI in the spirit of `nmtui`.

Tier: **Linux-only** (`/sys/class/net`, `/proc/net/route`). The interface
list works with no tools at all; `ip` (iproute2) adds IPv4 addresses and
link up/down; a running NetworkManager (`nmcli`) adds profiles and Wi-Fi.

Sources: [lib/network/conn/core.sh](../../../lib/network/conn/core.sh) (data and actions),
[lib/network/conn/tui.sh](../../../lib/network/conn/tui.sh) (TUI on `lib/tui`),
[examples/netconn.sh](../../../examples/netconn.sh) (CLI).

## Loading

```bash
#!/usr/bin/env bs

load "lib/network/conn/core"   # data and actions only
load "lib/network/conn/tui"    # + the TUI (network::conn::tui::run)
```

## Interfaces

```bash
network::conn::list          # name<TAB>kind<TAB>state<TAB>mac<TAB>mtu ("--" when empty)
network::conn::show eth0     # key=value: name kind state admin carrier mac mtu speed driver rx tx inet inet6 gateway managed
network::conn::kind wlan0    # loopback | wifi | ethernet | bridge | bond | vlan | wireguard | tun | veth | virtual | …
network::conn::state lo      # up | down | dormant | … (loopback/tun "unknown" with IFF_UP → up)
network::conn::stats eth0    # "rx_bytes tx_bytes"
network::conn::addrs eth0    # "inet 10.0.0.5/24", "inet6 fe80::…/64" (ip → ifconfig → IPv6 from /proc/net/if_inet6)
network::conn::gateways      # iface<TAB>gateway<TAB>metric, lowest metric first
network::conn::dns           # nameservers from resolv.conf
```

`up`/`down` use `nmcli device connect|disconnect` when NetworkManager
manages the device, and `ip link set dev X up|down` otherwise (root: run
as root or with passwordless `sudo`; returns 126 when neither is there).
Interface names are checked first (no option-like or shell-special names).

```bash
network::conn::up wlan0
network::conn::down eth1
```

## NetworkManager and Wi-Fi

Rows never contain an empty field: an empty value is `--`, so
`IFS=$'\t' read` (tab is IFS whitespace and collapses) keeps the columns.

```bash
network::conn::nm::available          # nmcli present and NetworkManager running
network::conn::nm::profiles           # name<TAB>uuid<TAB>type<TAB>device<TAB>active(yes|no)
network::conn::nm::up "Office"        # by name (nmcli … id) or UUID (nmcli … uuid)
network::conn::nm::down 1111…5555
network::conn::wifi::scan [yes]       # inuse(*|--)<TAB>ssid<TAB>signal<TAB>security(-- open)<TAB>chan
network::conn::wifi::connect "Home" "secret" [wlan0]
network::conn::wifi::known "Home"     # a saved profile exists
network::conn::wifi::radio on|off
```

The Wi-Fi password reaches `nmcli device wifi connect` as an argument
(that is how this nmcli command takes it), so it is visible in the process
list for the time of the call. The CLI never takes it from its own
arguments: it asks (`--ask`) or reads stdin (`--password-stdin`).

## TUI

```bash
bs run examples/netconn.sh            # TUI on a terminal, `list` otherwise
bs run examples/netconn.sh tui wifi   # open on the Wi-Fi list
```

Left pane: **Interfaces** and **Profiles** tabs (`Tab`). Right pane: details
of the selected interface (or of the profile and its device) and live
traffic with a sparkline. Keys: `Enter` toggles the interface or profile
(turning something off asks first; the default route is called out), `u`/`d`
up/down, `w` Wi-Fi (Enter connects, a masked password field opens for a
protected network that is not saved; `Ctrl+R` shows it), `r` refresh, `?`
help, `q` quit. Bringing a link up/down without NetworkManager leaves the
alt screen once for `sudo -v`.

## CLI

```text
netconn.sh list | show <if> | up <if> | down <if> | routes
netconn.sh profiles | connect <profile|uuid> | disconnect <profile|uuid>
netconn.sh wifi [list|rescan|on|off]
netconn.sh wifi connect <ssid> [--ask|--password-stdin] [--ifname <if>]
```

## Test hooks

| Variable | Default | Purpose |
|---|---|---|
| `BS_NET_SYS` | `/sys/class/net` | sysfs root |
| `BS_NET_PROC` | `/proc/net` | `route` and `if_inet6` |
| `BS_NET_RESOLV` | `/etc/resolv.conf` | DNS servers |

Tests: [tests/unit/testnetconnunit.sh](../../../tests/unit/testnetconnunit.sh)
(fake sysfs, fake `ip` and `nmcli`, TUI frames drawn into the buffer).
