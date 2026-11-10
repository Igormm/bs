[↑ Оглавление документации](../README.md)

# Модуль `vpn` — VPN/прокси-клиент на ядре sing-box

Обёртка над готовым ядром [sing-box](https://github.com/SagerNet/sing-box)
(>= 1.12, проверено на 1.14.4). Сами протоколы BS не реализует: модуль хранит
профили, импортирует ссылки и подписки, собирает JSON-конфиг ядра, запускает
и контролирует ядро и управляет им через Clash API. Сверху — полноэкранный
TUI и CLI (`examples/vpn.sh`).

Почему sing-box, а не Xray: только sing-box умеет все протоколы ниже как
клиент в одном бинарнике (в Xray нет Hysteria/TUIC), и в нём есть режим TUN,
rule-set, группы selector/urltest и Clash API. Ограничение: транспорты только
для Xray (`xhttp`/`splithttp`) отклоняются при импорте.

Ярус: **gnu-linux** для `core.sh`/`tui.sh` (управление процессом, `/proc`,
`setsid`, TUN). `link.sh`, `store.sh` и `singbox.sh` — чистый bash, переносимы.

Исходники: [lib/network/vpn/](../../../lib/network/vpn/)

| Файл | Пространство имён | Задача |
|---|---|---|
| `link.sh` | `vpn::link::*` | ссылки ⇄ записи профилей, base64, тела подписок |
| `store.sh` | `vpn::store::*`, `vpn::settings::*`, `vpn::sub::*` | профили, настройки, подписки на диске |
| `singbox.sh` | `vpn::singbox::*` | JSON sing-box (outbound, входы, DNS, маршруты, Clash API) |
| `core.sh` | `vpn::core::*` | установка, запуск/остановка, статус, смена сервера на лету, задержка, внешний IP, systemd |
| `tui.sh` | `vpn::tui::*` | полноэкранный клиент на `lib/tui/tui` |

## Протоколы

| Протокол | Схемы ссылок | Возможности |
|---|---|---|
| VLESS | `vless://` | TLS, REALITY, отпечаток uTLS, `xtls-rprx-vision`, ws/grpc/http/httpupgrade/quic |
| VMess | `vmess://` (base64 JSON) | TLS, транспорты, `alterId`, шифр |
| Trojan | `trojan://` | TLS, транспорты |
| Shadowsocks | `ss://` (SIP002, legacy, шифры 2022) | `obfs-local`/`v2ray-plugin` |
| Hysteria2 | `hysteria2://`, `hy2://` | обфускация Salamander, port hopping (`443,20000-30000`, `mport=`) |
| Hysteria | `hysteria://`, `hy://` | up/down Мбит/с, obfs, auth |
| TUIC v5 | `tuic://` | алгоритм перегрузки, режим UDP relay |
| AnyTLS | `anytls://` | TLS |
| SOCKS5 | `socks://`, `socks5://` | логин/пароль |

## Быстрый старт

```bash
./bs run examples/vpn.sh core install          # sing-box в ~/.local/share/bs/vpn/bin
./bs run examples/vpn.sh import 'vless://…'    # или: sub add mysub https://…
./bs run examples/vpn.sh connect               # режим proxy: SOCKS5/HTTP на 127.0.0.1:2080
./bs run examples/vpn.sh                       # TUI
```

## Использование из кода

```bash
#!/usr/bin/env bs

load "lib/network/vpn/core"

id="$(vpn::store::import 'trojan://secret@example.com:443?sni=example.com#DE')"
vpn::settings::set route bypass-ru
vpn::core::start "${id}"
vpn::core::status
vpn::core::stop
```

## Хранилище

| Путь | Содержимое |
|---|---|
| `${BS_VPN_HOME:-~/.config/bs/vpn}/profiles/<id>.conf` | запись профиля, `ключ=значение` (никогда не исполняется) |
| `…/profiles/.order` | порядок показа |
| `…/subs/<имя>.conf` | адрес подписки, время обновления, число серверов |
| `…/settings.conf` | настройки |
| `${BS_VPN_STATE:-~/.local/state/bs/vpn}/` | `config.json`, `sing-box.pid`, `sing-box.log`, `session`, `latency.tsv`, `cache.db` |
| `${BS_VPN_BIN_DIR:-~/.local/share/bs/vpn/bin}/sing-box` | скачанное ядро |

`BS_VPN_CORE` указывает на конкретный бинарник. Все файлы пишутся атомарно
с правами 600.

## Настройки

| Ключ | Значения | Смысл |
|---|---|---|
| `mode` | `proxy`, `tun` | локальный SOCKS5/HTTP-прокси или вся система через TUN (нужен root) |
| `route` | `global`, `bypass-ru`, `bypass-cn`, `bypass-ir`, `direct` | пресет маршрутизации; bypass-пресеты пускают сайты страны напрямую по rule-set SagerNet |
| `auto_select` | `0`/`1` | выбирать самый быстрый сервер группы (urltest) |
| `listen_port`, `allow_lan`, `system_proxy` | | локальный прокси |
| `tun_stack`, `tun_mtu`, `strict_route`, `ipv6` | | TUN; `strict_route=1` — kill switch |
| `dns_remote`, `dns_direct` | `https://…`, `tls://…`, IP, `local` | раздельный DNS |
| `block_ads`, `direct_domains`, `proxy_domains`, `block_domains` | | дополнительные правила |
| `log_level`, `api_port`, `test_url` | | журнал ядра, порт Clash API, URL замера (только https) |

## Как собирается подключение

1. Выбранный профиль и остальные профили его группы (до 200) попадают в один
   конфиг: селектор `proxy`, группа urltest `auto` и по outbound на сервер.
2. `sing-box check` проверяет конфиг; профиль, который ядро отвергло,
   отбрасывается с сообщением (`VPN_CORE_PRUNED`) — одна битая запись
   подписки не ломает подключение.
3. Ядро запускается отдельно от терминала (`setsid`/`nohup`); режим TUN идёт
   через `sudo -n` и даёт понятную ошибку, если sudo просит пароль.
4. Переключение на другой сервер той же группы — вызов Clash API: без
   перезапуска, открытые соединения переносятся.

Замер (`vpn::core::test_real`) поднимает временное ядро только с outbound и
опрашивает Clash API по всем серверам параллельно — работает и для UDP-
протоколов и не трогает работающий туннель. `vpn::core::test_tcp` — время
TCP-подключения без ядра.

## Клавиши TUI

`↑↓` выбор · `Enter` подключиться/переключиться · `d` отключиться ·
`r` переподключиться · `t`/`T` замер одного/всех · `S` сортировка по задержке ·
`a` автовыбор · `i` импорт (вставка работает) · `s` подписки · `o` настройки ·
`m` proxy↔tun · `g` пресет маршрута · `e` ссылка + QR · `x` удалить ·
`p` внешний IP · `l` журнал · `/` поиск · `?` справка ·
`q` выход (VPN продолжает работать) · `Q` выйти и отключить.

## Тесты

`tests/unit/testvpnunit.sh` — ссылки всех протоколов, обратное построение,
хранилище, проверка настроек, подписки через `file://`, отрисовка outbound и
конфига, отбраковка и запуск/остановка с поддельным ядром, кадр и клавиши
TUI. `BS_VPN_TEST_CORE=/путь/к/sing-box` дополнительно проверяет конфиги
настоящим ядром.
