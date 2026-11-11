[↑ Оглавление документации](../README.md)

# Модуль `vpn` — VPN/прокси-клиент на ядрах sing-box и Xray

Обёртка над готовыми ядрами: [sing-box](https://github.com/SagerNet/sing-box)
(>= 1.12, проверено на 1.14.4) — основное, [Xray-core](https://github.com/XTLS/Xray-core)
(>= 24.11, проверено на 26.3.27) — второе. Сами протоколы BS не реализует:
модуль хранит профили, импортирует ссылки, конфиги WireGuard и подписки,
собирает JSON-конфиг ядра, запускает и контролирует ядро и управляет им через
его API. Сверху — полноэкранный TUI и CLI (`examples/vpn.sh`).

Почему два ядра: sing-box умеет все протоколы ниже в одном бинарнике (в Xray
нет Hysteria/TUIC/AnyTLS/NaiveProxy), и в нём есть режим TUN, rule-set и Clash
API. Только в Xray есть транспорт XHTTP (`splithttp`) и шифрование VLESS
(`mlkem768x25519plus`). Выбирает настройка `core`: `auto` (по умолчанию)
запускает профиль на Xray, только если подключиться к нему умеет лишь Xray.

Ярус: **gnu-linux** для `core.sh`/`tui.sh` (управление процессом, `/proc`,
`setsid`, TUN). `link.sh`, `store.sh`, `singbox.sh` и `xray.sh` — чистый bash, переносимы.

Исходники: [lib/network/vpn/](../../../lib/network/vpn/)

| Файл | Пространство имён | Задача |
|---|---|---|
| `link.sh` | `vpn::link::*` | ссылки и `.conf` WireGuard ⇄ записи профилей, base64, тела подписок, какое ядро нужно профилю |
| `store.sh` | `vpn::store::*`, `vpn::settings::*`, `vpn::sub::*` | профили, настройки, подписки на диске |
| `singbox.sh` | `vpn::singbox::*` | JSON sing-box (outbound, endpoint WireGuard, входы, DNS, маршруты, Clash API) |
| `xray.sh` | `vpn::xray::*` | JSON Xray (outbound, балансировщик, observatory, маршруты, API статистики) |
| `core.sh` | `vpn::core::*` | установка, выбор ядра, запуск/остановка, статус, смена сервера на лету, задержка, внешний IP, systemd |
| `tui.sh` | `vpn::tui::*` | полноэкранный клиент на `lib/tui/tui` |

## Протоколы

| Протокол | Схемы ссылок | Возможности | Ядро |
|---|---|---|---|
| VLESS | `vless://` | TLS, REALITY, отпечаток uTLS, `xtls-rprx-vision`, ws/grpc/http/httpupgrade/quic | оба (http/quic — sing-box) |
| VLESS + XHTTP | `vless://…?type=xhttp` (или `splithttp`) | `mode`, `extra` (JSON), REALITY/TLS | Xray |
| Шифрование VLESS | `vless://…?encryption=mlkem768x25519plus…` | постквантовое шифрование VLESS | Xray |
| VMess | `vmess://` (base64 JSON) | TLS, транспорты, `alterId`, шифр | оба |
| Trojan | `trojan://` | TLS, транспорты | оба |
| Shadowsocks | `ss://` (SIP002, legacy, шифры 2022) | `obfs-local`/`v2ray-plugin` (sing-box) | оба |
| Hysteria2 | `hysteria2://`, `hy2://` | обфускация Salamander, port hopping (`443,20000-30000`, `mport=`) | sing-box |
| Hysteria | `hysteria://`, `hy://` | up/down Мбит/с, obfs, auth | sing-box |
| TUIC v5 | `tuic://` | алгоритм перегрузки, режим UDP relay | sing-box |
| AnyTLS | `anytls://` | TLS | sing-box |
| WireGuard | `wireguard://`, `wg://`, файл `.conf` | pre-shared key, `reserved` (WARP), MTU, keepalive | оба |
| NaiveProxy | `naive+https://`, `naive+quic://` | HTTP/2 или QUIC, `insecure-concurrency` | sing-box (нужен `libcronet.so`, он есть в официальной сборке) |
| SOCKS5 | `socks://`, `socks5://` | логин/пароль | оба |

Xray больше не принимает `allowInsecure` (убран в 2026 году): серверу с
самоподписанным сертификатом нужен хеш сертификата в ссылке (`pcs=<sha256>`),
он передаётся в Xray как `pinnedPeerCertSha256`.

## Быстрый старт

```bash
./bs run examples/vpn.sh core install          # sing-box в ~/.local/share/bs/vpn/bin
./bs run examples/vpn.sh core install xray     # Xray с geoip.dat/geosite.dat (для XHTTP)
./bs run examples/vpn.sh import 'vless://…'    # или .conf WireGuard, или: sub add mysub https://…
./bs run examples/vpn.sh connect               # режим proxy: SOCKS5/HTTP на 127.0.0.1:2080
./bs run examples/vpn.sh                       # TUI
```

## Использование из библиотеки

```bash
#!/usr/bin/env bs

load "lib/network/vpn/core"

id="$(vpn::store::import 'trojan://secret@example.com:443?sni=example.com#DE')"
vpn::settings::set route bypass-ru
vpn::core::start "${id}"
vpn::core::status
vpn::core::stop
```

## Хранение

| Путь | Содержимое |
|---|---|
| `${BS_VPN_HOME:-~/.config/bs/vpn}/profiles/<id>.conf` | запись профиля `ключ=значение` (никогда не source-ится) |
| `…/profiles/.order` | порядок показа |
| `…/subs/<имя>.conf` | URL подписки, время обновления, число серверов |
| `…/settings.conf` | настройки |
| `${BS_VPN_STATE:-~/.local/state/bs/vpn}/` | `config.json`, `core.pid`, `core.log`, `session`, `latency.tsv`, `cache.db` |
| `${BS_VPN_BIN_DIR:-~/.local/share/bs/vpn/bin}/` | скачанные ядра: `sing-box` (+ `libcronet.so`), `xray` (+ `geoip.dat`, `geosite.dat`) |

`BS_VPN_CORE` и `BS_VPN_XRAY` указывают конкретные бинарники. Все файлы
пишутся атомарно с правами 600.

## Настройки

| Ключ | Значения | Смысл |
|---|---|---|
| `core` | `auto`, `sing-box`, `xray` | каким ядром работает подключение; `auto` берёт Xray только для профилей, которые умеет лишь Xray |
| `mode` | `proxy`, `tun` | локальный SOCKS5/HTTP-прокси или весь трафик системы через TUN (root, только sing-box) |
| `route` | `global`, `bypass-ru`, `bypass-cn`, `bypass-ir`, `direct` | пресет маршрутизации; sing-box берёт rule-set SagerNet, Xray — файлы `geosite`/`geoip` (без них — только доменные зоны) |
| `auto_select` | `0`/`1` | выбирать самый быстрый сервер группы (urltest в sing-box, leastPing в Xray) |
| `listen_port`, `allow_lan`, `system_proxy` | | локальный прокси |
| `tun_stack`, `tun_mtu`, `strict_route`, `ipv6` | | TUN; `strict_route=1` — kill switch |
| `dns_remote`, `dns_direct` | `https://…`, `tls://…`, IP, `local` | раздельный DNS (у Xray нет клиента DoT: `tls://host` становится DoH на том же хосте) |
| `block_ads`, `direct_domains`, `proxy_domains`, `block_domains` | | дополнительные правила |
| `log_level`, `api_port`, `test_url` | | журнал ядра, порт API, URL замера (только https) |

## Как собирается подключение

1. `vpn::core::engine_for` выбирает ядро по настройке `core` и выбранному
   профилю. Профиль и остальные профили его группы, к которым умеет
   подключаться это ядро (до 200), идут в один конфиг.
2. sing-box: селектор `proxy`, группа urltest `auto` и по outbound на профиль
   (WireGuard — как endpoint). Xray: по outbound на профиль с тегом `p:<id>`
   и балансировщик `proxy` над ними (leastPing с observatory, если профилей
   несколько).
3. Ядро проверяет конфиг (`sing-box check`, `xray run -test`); профиль,
   который ядро отвергло, выбрасывается с сообщением (`VPN_CORE_PRUNED`), и
   одна битая запись подписки не ломает подключение.
4. Ядро стартует отдельно от терминала (`setsid`/`nohup`); режим TUN идёт
   через `sudo -n` и падает с понятным сообщением, если sudo просит пароль.
5. Переход на другой сервер той же группы — на лету: вызов Clash API в
   sing-box, override балансировщика (`xray api bo`) в Xray. Сервер, к
   которому работающее ядро подключаться не умеет, перезапускает подключение
   на другом ядре.

Замер задержки (`vpn::core::test_real`) запускает временные ядра и не трогает
работающий туннель: sing-box меряет через delay-тест Clash API, профили
только для Xray идут через временный Xray с отдельным локальным SOCKS-портом
на профиль. Оба способа работают и для UDP-протоколов. `vpn::core::test_tcp`
— время TCP-подключения без ядра.

Счётчики трафика берутся из Clash API (sing-box) или API статистики (Xray —
соединения он не считает).

## Клавиши TUI

`↑↓` выбор · `Enter` подключить/переключить · `d` отключить · `r`
переподключить · `t`/`T` замер одного/всех · `S` сортировка по задержке ·
`a` автовыбор · `i` импорт (работает вставка, и `.conf` WireGuard тоже) ·
`s` подписки · `o` настройки (и ядро) · `m` proxy↔tun · `g` пресет
маршрутов · `e` ссылка + QR · `x` удалить · `p` внешний IP · `l` журнал ·
`/` поиск · `?` справка · `q` выйти (VPN продолжит работать) · `Q` выйти и
отключить. В заголовке — работающее ядро, в панели профиля — на каком ядре
пойдёт профиль.

## Тесты

`tests/unit/testvpnunit.sh` — ссылки всех протоколов, `.conf` WireGuard,
круговые преобразования, хранилище, проверка настроек, подписки через
`file://`, сборка конфигов sing-box и Xray, выбор ядра, отбраковка, запуск,
остановка и смена сервера на лету с поддельными ядрами, кадр и клавиши TUI.
`BS_VPN_TEST_CORE=/путь/к/sing-box` и `BS_VPN_TEST_XRAY=/путь/к/xray`
включают проверку конфигов настоящими ядрами.
