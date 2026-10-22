[↑ Оглавление](../README.md)

# Модуль `openbao` (сервер)

`lib/system/openbao.sh` ставит релиз OpenBao, создаёт системного
пользователя, пишет HCL-конфиг и systemd-юнит, инициализирует кластер,
разблокирует его и проверяет готовность. Это серверная пара к
[lib/integration/openbao.sh](integration-openbao.md).

Ярус: **только Linux** (пишет под `/etc`, `/var/lib`, `/usr/local/bin` и
использует systemd). При отсутствии инструмента или прав — чистая деградация
с кодами `LIB_ERROR_*`, без молчаливого успеха.

Источник: [lib/system/openbao.sh](../../../lib/system/openbao.sh)

## Подключение

```bash
#!/usr/bin/env bs

load "lib/system/openbao"
```

## Профили

| Профиль | Поведение |
|---|---|
| `dev` | установить бинарник, HTTP на loopback, сгенерированный root-токен, `bao server -dev` на переднем плане |
| `prod` | системный пользователь, file storage, TLS, systemd-юнит, `operator init`, автоматический unseal, health-check |

`prod` — профиль по умолчанию для `openbao_server::apply`.

## Хуки

| Переменная | По умолчанию | Назначение |
|---|---|---|
| `BS_OPENBAO_VERSION` | `latest` | версия релиза или `latest` |
| `BS_OPENBAO_BIN` | `/usr/local/bin/bao` | путь к бинарнику |
| `BS_OPENBAO_CONFIG` | `/etc/openbao/openbao.hcl` | HCL-конфиг |
| `BS_OPENBAO_CONFIG_DIR` | `/etc/openbao` | каталог конфига |
| `BS_OPENBAO_DATA_DIR` | `/var/lib/openbao` | каталог данных/storage |
| `BS_OPENBAO_TLS_DIR` | `/etc/openbao/tls` | каталог TLS |
| `BS_OPENBAO_TLS_MODE` | `selfsigned` | `selfsigned`, `files` или `off` |
| `BS_OPENBAO_TLS_CERT` | `${TLS_DIR}/server.crt` | серверный сертификат |
| `BS_OPENBAO_TLS_KEY` | `${TLS_DIR}/server.key` | ключ сервера |
| `BS_OPENBAO_TLS_CA` | `${TLS_DIR}/ca.crt` | CA для клиентов |
| `BS_OPENBAO_LISTEN` | `127.0.0.1:8200` | listener `host:port` |
| `BS_OPENBAO_INIT_FILE` | `/root/openbao-init.json` | JSON `operator init` |
| `BS_OPENBAO_SERVICE` | `openbao` | имя systemd-юнита |
| `BS_OPENBAO_USER` / `BS_OPENBAO_GROUP` | `openbao` | сервисная учётка |
| `BS_OPENBAO_RELEASE_BASE` | GitHub releases | база скачивания релизов |
| `BS_OPENBAO_API_BASE` | GitHub latest-release API | поиск последней версии |
| `BS_OPENBAO_LATEST_VERSION` | пусто | заранее известная latest-версия для тестов |
| `BS_OPENBAO_INIT_SHARES` / `BS_OPENBAO_INIT_THRESHOLD` | `5` / `3` | доли unseal |
| `BS_OPENBAO_DEV_TOKEN` | пусто | фиксированный dev root-токен |
| `BS_OPENBAO_DEV_LISTEN` | `127.0.0.1:8200` | dev-listener |
| `BS_OPENBAO_DRY_RUN` | `0` | `1` = печатать действия, ничего не менять |
| `BS_OPENBAO_TIMEOUT` | `30` | таймаут готовности, секунды |

Все пути, попадающие в HCL или юнит, проверяются на переводы строк и кавычки.

## Жизненный цикл

```bash
openbao_server::init          # проверить хуки и платформу
openbao_server::install       # скачать, проверить sha256, атомарно установить
openbao_server::ensure_user   # useradd --system + блокировка пароля
openbao_server::tls_selfsigned localhost 127.0.0.1
openbao_server::configure prod
openbao_server::install_service
openbao_server::wait_ready
openbao_server::init_cluster
openbao_server::unseal
openbao_server::status
```

`openbao_server::install` разрешает `latest` через GitHub API, скачивает
`openbao_<version>_linux_<arch>.tar.gz` и `checksums.txt`, проверяет SHA-256,
извлекает исполняемый `bao` и атомарно заменяет цель. Уже установленная
подходящая версия — no-op.

`openbao_server::tls_selfsigned` создаёт 4096-битные CA и ключ сервера,
подписывает серверный сертификат с SAN для переданных хостов плюс
`localhost`, `127.0.0.1` и `::1`, и ставит ключу права `0600`.

`openbao_server::configure` создаёт каталоги данных и конфига, делает backup
существующего конфига и пишет новый HCL с правами `0640`. Режимы TLS:

- `selfsigned` — сгенерировать CA и сертификат сервера, если их нет.
- `files` — требовать читаемые `BS_OPENBAO_TLS_CERT` и `BS_OPENBAO_TLS_KEY`.
- `off` — HTTP; для dev, визард явно предупреждает.

`openbao_server::init_cluster` запускает `bao operator init -format=json`,
проверяет JSON и пишет ключи и root-токен в `BS_OPENBAO_INIT_FILE` с правами
`0600`. Если файл уже есть — отказ с `LIB_ERROR_CONFLICT`.
`openbao_server::unseal` читает `.unseal_keys_b64[]`, отправляет ключи до
порога и проверяет, что `sys/seal-status` сообщает `sealed: false`.

## Применение

```bash
openbao_server::apply dev    # только установка; dev_start вызывает вызывающий
openbao_server::apply prod   # install → user → config → systemd → init → unseal
openbao_server::dev_command  # напечатать команду dev-сервера
openbao_server::dev_start    # exec dev-сервера в этом терминале
```

`apply prod` запускает сервис до `init_cluster`, поэтому первый health-check
может законно увидеть `503` (uninitialized/sealed); затем идут init, unseal и
повторное ожидание здорового ответа.

## Безопасность

- Init-файл содержит unseal-ключи и root-токен; держите его `0600` и вне
  незашифрованных backup. `apply prod` его не печатает.
- systemd-юнит работает от непривилегированного пользователя с
  `NoNewPrivileges`, `PrivateTmp`, `ProtectSystem=strict` и `ProtectHome`;
  запись разрешена только в `BS_OPENBAO_DATA_DIR`.
- Токен клиента пишется через `openbao::login` с правами `0600`.
- Токены уходят через временный config-файл curl, а не в argv.

## Коды ошибок

Для неверного ввода, отсутствующих файлов и зависимостей, конфликтов,
таймаутов и файловых операций используются стандартные `LIB_ERROR_*`. Ошибка
проверки релиза — `LIB_ERROR_INVALID_INPUT`; HTTP-сбой —
`INTEGRATION_ERROR_HTTP`; неверный JSON `operator init` —
`OPENBAO_ERROR_JSON`.

## Визард

`examples/openbao_wizard.sh` — полноэкранный TUI поверх этого и клиентского
модуля: роль (`server`, `client`, `both`), профиль (`dev`, `prod`), адрес
listen, TLS-режим/файлы, адрес/CA/токен клиента, подтверждение, установка,
systemd, init/unseal и журнал шагов.

```bash
sudo bs run examples/openbao_wizard.sh --profile prod
bs run examples/openbao_wizard.sh --role client
bs run examples/openbao_wizard.sh --dry-run
```

## Зависимости

- `core/const`, `core/logger`, `core/utils`, `lib/io/files`,
  `lib/system/systemd`, `lib/system/user`, `lib/integration/http`,
  `lib/integration/openbao`.
- `curl` или `wget` (скачивание релиза), `sha256sum`, `tar`, `gzip`,
  `openssl` для self-signed TLS, `systemctl`, `useradd`.
