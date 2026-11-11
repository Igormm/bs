[↑ Оглавление документации](../README.md)

# Модуль `network/conn`

Сетевые подключения в Linux: интерфейсы и их состояние, адреса, маршруты по
умолчанию и DNS, профили подключений NetworkManager и Wi-Fi, а также
полноэкранный TUI в духе `nmtui`.

Уровень: **только Linux** (`/sys/class/net`, `/proc/net/route`). Список
интерфейсов работает вообще без утилит; `ip` (iproute2) добавляет адреса
IPv4 и up/down; запущенный NetworkManager (`nmcli`) — профили и Wi-Fi.

Исходники: [lib/network/conn/core.sh](../../../lib/network/conn/core.sh) (данные и действия),
[lib/network/conn/tui.sh](../../../lib/network/conn/tui.sh) (TUI на `lib/tui`),
[examples/netconn.sh](../../../examples/netconn.sh) (CLI).

## Загрузка

```bash
#!/usr/bin/env bs

load "lib/network/conn/core"   # только данные и действия
load "lib/network/conn/tui"    # + TUI (network::conn::tui::run)
```

## Интерфейсы

```bash
network::conn::list          # имя<TAB>вид<TAB>состояние<TAB>mac<TAB>mtu («--», если пусто)
network::conn::show eth0     # key=value: name kind state admin carrier mac mtu speed driver rx tx inet inet6 gateway managed
network::conn::kind wlan0    # loopback | wifi | ethernet | bridge | bond | vlan | wireguard | tun | veth | virtual | …
network::conn::state lo      # up | down | dormant | … (loopback/tun «unknown» с IFF_UP → up)
network::conn::stats eth0    # «rx_bytes tx_bytes»
network::conn::addrs eth0    # «inet 10.0.0.5/24», «inet6 fe80::…/64» (ip → ifconfig → IPv6 из /proc/net/if_inet6)
network::conn::gateways      # интерфейс<TAB>шлюз<TAB>метрика, меньшая метрика первой
network::conn::dns           # nameserver из resolv.conf
```

`up`/`down` вызывают `nmcli device connect|disconnect`, если устройством
управляет NetworkManager, иначе `ip link set dev X up|down` (root: запуск от
root или `sudo` без пароля; без них — код 126). Имя интерфейса проверяется
заранее (никаких имён вида опции или со спецсимволами оболочки).

```bash
network::conn::up wlan0
network::conn::down eth1
```

## NetworkManager и Wi-Fi

В строках нет пустых полей: пустое значение — `--`, поэтому
`IFS=$'\t' read` (таб — пробельный IFS и схлопывается) не сдвигает колонки.

```bash
network::conn::nm::available          # есть nmcli и NetworkManager запущен
network::conn::nm::profiles           # имя<TAB>uuid<TAB>тип<TAB>устройство<TAB>активен(yes|no)
network::conn::nm::up "Office"        # по имени (nmcli … id) или UUID (nmcli … uuid)
network::conn::nm::down 1111…5555
network::conn::wifi::scan [yes]       # inuse(*|--)<TAB>ssid<TAB>сигнал<TAB>защита(-- открытая)<TAB>канал
network::conn::wifi::connect "Home" "secret" [wlan0]
network::conn::wifi::known "Home"     # есть сохранённый профиль
network::conn::wifi::radio on|off
```

Пароль Wi-Fi передаётся `nmcli device wifi connect` аргументом (так эта
команда nmcli его принимает), поэтому на время вызова он виден в списке
процессов. CLI никогда не берёт его из своих аргументов: спрашивает
(`--ask`) или читает stdin (`--password-stdin`).

## TUI

```bash
bs run examples/netconn.sh            # в терминале — TUI, иначе — list
bs run examples/netconn.sh tui wifi   # сразу со списком Wi-Fi
```

Слева вкладки **Интерфейсы** и **Профили** (`Tab`). Справа — сведения о
выбранном интерфейсе (или о профиле и его устройстве) и живой трафик со
спарклайном. Клавиши: `Enter` включает или выключает интерфейс или профиль
(выключение спрашивает подтверждение и предупреждает о маршруте по
умолчанию), `u`/`d` — поднять/опустить, `w` — Wi-Fi (Enter подключает; для
защищённой несохранённой сети открывается поле пароля со звёздочками,
`Ctrl+R` — показать), `r` — обновить, `?` — справка, `q` — выход. Поднять
или опустить интерфейс без NetworkManager — TUI один раз выйдет с
alt-экрана для `sudo -v`.

## CLI

```text
netconn.sh list | show <if> | up <if> | down <if> | routes
netconn.sh profiles | connect <профиль|uuid> | disconnect <профиль|uuid>
netconn.sh wifi [list|rescan|on|off]
netconn.sh wifi connect <ssid> [--ask|--password-stdin] [--ifname <if>]
```

## Хуки для тестов

| Переменная | По умолчанию | Назначение |
|---|---|---|
| `BS_NET_SYS` | `/sys/class/net` | корень sysfs |
| `BS_NET_PROC` | `/proc/net` | `route` и `if_inet6` |
| `BS_NET_RESOLV` | `/etc/resolv.conf` | DNS-серверы |

Тесты: [tests/unit/testnetconnunit.sh](../../../tests/unit/testnetconnunit.sh)
(поддельные sysfs, `ip` и `nmcli`, кадры TUI рисуются в буфер).
