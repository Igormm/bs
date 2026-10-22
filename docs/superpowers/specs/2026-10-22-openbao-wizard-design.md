# Дизайн: OpenBao — сервер, клиент и TUI-визард

Дата: 2026-10-22
Статус: реализовано
Автор: сессия opencode

## 1. Цель и результат

Дать BS-пользователю один визард, который поднимает OpenBao на Linux и
настраивает клиентский доступ к нему:

- **dev** — быстрый локальный сервер для разработки: бинарник, HTTP на
  loopback, root token, сервер работает в текущем терминале.
- **prod** — боевая установка: системный пользователь, single-node Raft storage, TLS,
  systemd-юнит, `operator init`, автоматический unseal, root token и ключи
  в `0600`-файле, проверка `sys/health`.
- **client** — адрес, CA, токен, проверка соединения и сохранение токена в
  `0600`-файл; без root-прав.

Успех: после визарда сервер отвечает `sys/health`, клиент выполняет
`openbao::request GET /v1/sys/health`, а секреты не попадают в argv, логи и
историю shell.

OAuth2/OAuth1 — отдельная задача и в этот дизайн не входит.

## 2. Решения по процессу (согласовано)

- Вариант 1: два слоя — `lib/system/openbao.sh` (сервер) и
  `lib/integration/openbao.sh` (клиент/API), плюс тонкий визард.
- UI — `lib/ui/wizard` (пошаговый полноэкранный визард, как
  `examples/ai_user_wizard.sh`), а не сложный `lib/tui/tui`.
- Поддержка и dev-, и prod-профиля.
- Клиент умеет generic request + типовые helpers; «весь API» не означает
  по функции на каждый endpoint.
- TLS: существующие сертификаты или самоподписанный CA + серверный серт.
- `operator init`: ключи и root token сохраняются в файл `0600`; в консоль
  выводятся только путь и предупреждение.
- Визард работает на `bash4`-тире, как остальные системные/интеграционные
  модули.

## 3. Архитектура

```
lib/system/openbao.sh           сервер: установка, конфиг, TLS, systemd, init/unseal
lib/integration/openbao.sh      клиент: адрес/токен/TLS, generic request, helpers
examples/openbao_wizard.sh      TUI-визард: сервер / клиент / оба
tests/unit/testopenbaoserverunit.sh
tests/unit/testopenbaoclientunit.sh
tests/unit/testopenbaowizardunit.sh
documentation/{en,ru}/03-modules/system-openbao.md
documentation/{en,ru}/03-modules/integration-openbao.md
```

Границы:

- серверный модуль не рисует и не читает клавиатуру;
- клиентский модуль не устанавливает бинарник и не трогает systemd;
- визард не содержит правил OpenBao, только шаги, подсказки и вызовы
  `openbao_server::*` / `openbao::*`.

## 4. Общие хуки и константы

Все пути переопределяемы для тестов; каждый хук — с парным `# @global`
(категория `hook`).

| Переменная | По умолчанию | Назначение |
|---|---|---|
| `BS_OPENBAO_VERSION` | `latest` | версия релиза |
| `BS_OPENBAO_BIN` | `/usr/local/bin/bao` | бинарник |
| `BS_OPENBAO_CONFIG` | `/etc/openbao/openbao.hcl` | конфиг сервера |
| `BS_OPENBAO_CONFIG_DIR` | `/etc/openbao` | каталог конфига |
| `BS_OPENBAO_DATA_DIR` | `/var/lib/openbao` | данные и single-node Raft storage |
| `BS_OPENBAO_TLS_DIR` | `/etc/openbao/tls` | сертификаты |
| `BS_OPENBAO_TLS_MODE` | `selfsigned` | `selfsigned` / `files` / `off` (только dev) |
| `BS_OPENBAO_TLS_CERT` | `${BS_OPENBAO_TLS_DIR}/server.crt` | серверный сертификат |
| `BS_OPENBAO_TLS_KEY` | `${BS_OPENBAO_TLS_DIR}/server.key` | серверный ключ |
| `BS_OPENBAO_LISTEN` | `127.0.0.1:8200` | listen-адрес сервера |
| `BS_OPENBAO_INIT_FILE` | `/root/openbao-init.json` | ключи + root token |
| `BS_OPENBAO_SERVICE` | `openbao` | имя systemd-юнита |
| `BS_OPENBAO_USER` | `openbao` | системный пользователь |
| `BS_OPENBAO_ADDR` | `https://127.0.0.1:8200` | адрес клиента |
| `BS_OPENBAO_TOKEN_FILE` | `${XDG_CONFIG_HOME:-$HOME/.config}/bs/openbao-token` | токен клиента |
| `BS_OPENBAO_CACERT` | пусто | CA для TLS |
| `BS_OPENBAO_DRY_RUN` | `0` | `1` — только показать действия |
| `BS_OPENBAO_RELEASE_BASE` | GitHub releases OpenBao | база для тестового «релиза» |

Клиент также читает `BAO_ADDR`, `BAO_TOKEN`, `BAO_CACERT`, `BAO_NAMESPACE`
как совместимые fallback-имена. Приоритет: `BS_*` → `BAO_*` → файл токена.

## 5. Серверный модуль `lib/system/openbao.sh`

### 5.1 Метаданные

- `#!/usr/bin/env bs`, `# shellcheck shell=bash`, `# @shell bash4`.
- `bs::guard "LIB_SYSTEM_OPENBAO"`.
- Зависимости: `core/const`, `core/logger`, `core/utils`, `lib/io/files`,
  `lib/system/systemd`, `lib/system/user`, `lib/integration/http`.
- Внешние команды: `curl`/`wget`, `sha256sum`, `tar`, `gzip`, `openssl`,
  `systemctl`, `useradd`, `chown`, `chmod`; проверяются до изменений.

### 5.2 Публичный API

| Функция | Назначение |
|---|---|
| `openbao_server::init` | выставить дефолты, определить ОС/архитектуру |
| `openbao_server::detect` | stdout: `path<TAB>version` или пусто |
| `openbao_server::install [version]` | скачать релиз, проверить `checksums.txt`, поставить `bao` атомарно |
| `openbao_server::ensure_user` | создать `openbao` (nologin, home `BS_OPENBAO_DATA_DIR`) |
| `openbao_server::tls_selfsigned <host...>` | CA + серверный серт с SAN, ключ `0600` |
| `openbao_server::render_config <profile>` | детерминированный HCL в stdout |
| `openbao_server::configure <profile>` | каталоги, права, TLS, конфиг; backup старого конфига |
| `openbao_server::unit_render` | текст systemd-юнита в stdout |
| `openbao_server::install_service` | записать юнит, `daemon-reload`, `enable --now` |
| `openbao_server::init_cluster` | `operator init` → JSON в `BS_OPENBAO_INIT_FILE` (`0600`) |
| `openbao_server::unseal` | прочитать init-файл, отправить threshold ключей |
| `openbao_server::status` | `bao status -format=json` или `sys/health` |
| `openbao_server::apply <profile>` | оркестрация prod/dev установки |
| `openbao_server::dev_command` | команда dev-сервера для `exec` |

Все функции возвращают `E_*`/`LIB_ERROR_*`; при ошибке — `log::error` с
шагом и подсказкой. В dry-run печатаются планируемые команды, файлы не
пишутся.

### 5.3 Установка бинарника

- Архитектура: `uname -m` → `amd64` (`x86_64`) / `arm64` (`aarch64`);
  остальные — `LIB_ERROR_UNSUPPORTED`.
- Релиз: `https://github.com/openbao/openbao/releases/download/v<ver>/`
  и `openbao_<ver>_linux_<arch>.tar.gz`; `latest` резолвится через GitHub API
  или редирект `releases/latest`.
- Скачивание во временный каталог (`io::files::tempdir`), проверка
  `sha256sum -c` по `checksums.txt`, распаковка, проверка, что архив содержит
  `bao`.
- Установка: `install -m 0755` во временный файл рядом с `BS_OPENBAO_BIN`,
  затем атомарный `mv`; симлинк `openbao` не создаётся, чтобы не путать с
  пакетным менеджером.
- Если бинарник уже есть и версия совпадает — no-op с сообщением, а не
  повторное скачивание.

### 5.4 Конфиг

`render_config dev|prod` печатает HCL (для `dev` — только предпросмотр;
dev-сервер запускается командой, см. 5.7):

```hcl
ui = true

storage "raft" {
  path    = "/var/lib/openbao/data"
  node_id = "openbao"
}

listener "tcp" {
  address     = "127.0.0.1:8200"
  tls_disable = 0
  tls_cert_file = "/etc/openbao/tls/server.crt"
  tls_key_file  = "/etc/openbao/tls/server.key"
}

api_addr = "https://127.0.0.1:8200"
cluster_addr = "https://127.0.0.1:8201"
```

- `dev`: `tls_disable = 1`, адрес loopback, без `cluster_addr`; dev-сервер
  запускается не из этого файла, а командой `bao server -dev`.
- `prod`: TLS обязателен; `tls_disable` не выставляется в 1.
- Адрес из визарда: `127.0.0.1:8200` (по умолчанию) или `0.0.0.0:8200`
  с предупреждением; `api_addr`/`cluster_addr` строятся из него.
- `storage "raft"` — single-node integrated storage; `node_id` = имя
  systemd-сервиса, путь всегда внутри `BS_OPENBAO_DATA_DIR`.
- Старый конфиг сохраняется как `openbao.hcl.bak.<timestamp>` через
  `io::files::copy_file`; при ошибке записи возвращается исходный.

### 5.5 Пользователь и права

- `openbao` — системный пользователь, `--system --home-dir
  "$BS_OPENBAO_DATA_DIR" --shell /usr/sbin/nologin`, группа `openbao`.
- `BS_OPENBAO_DATA_DIR` — `0700 openbao:openbao`; `data/` — `0700`.
- `BS_OPENBAO_CONFIG_DIR` — `0750 root:openbao`; конфиг `0640 root:openbao`.
- TLS: каталог `0750 root:openbao`, CA/серт `0644`, ключ `0600 openbao:openbao`;
  CA-ключ `0600 root:root`.
- `BS_OPENBAO_INIT_FILE` — `0600 root:root`; каталог `/root` не меняется.
- Секреты никогда не передаются аргументами командной строки и не пишутся
  в `log::*`; только пути и имена.

### 5.6 systemd

Юнит `openbao.service`:

- `User=openbao`, `Group=openbao`;
- `ExecStart=<bin> server -config=<config>`;
- `Restart=on-failure`, `LimitNOFILE=65536`;
- `NoNewPrivileges=true`, `PrivateTmp=true`, `ProtectSystem=strict`,
  `ProtectHome=true`, `ReadWritePaths=<data dir>`;

`systemd::unit_write` + `daemon_reload` + `enable_now`. Если systemd
недоступен — `LIB_ERROR_DEPENDENCY_MISSING` с объяснением, а не «успех».

### 5.7 init / unseal

- `openbao_server::init_cluster`:
  - если `BS_OPENBAO_INIT_FILE` уже существует — не переинициализировать,
    вернуть `E_EXISTS`/специальный код и путь;
  - `bao operator init -key-shares=5 -key-threshold=3 -format=json` с
    `BAO_ADDR`;
  - JSON пишется атомарно в `0600`; поля `unseal_keys_b64`, `root_token`;
  - stdout команды не печатается; в лог — только «init завершён».
- `openbao_server::unseal`:
  - читает `unseal_keys_b64` через `jq`, отправляет первые 3 ключа
    `POST /v1/sys/unseal` через клиентский модуль;
  - проверяет `sealed=false`; при `sealed=true` — ошибка с числом
    оставшихся ключей;
  - повторный вызов при `sealed=false` — no-op.
- `prod`-поток: `install → user → dirs/TLS/config → service → init → unseal
  → health`.
- `dev`-поток: `install → exec env BAO_DEV_ROOT_TOKEN_ID=... bao server -dev
  -dev-listen-address=127.0.0.1:8200`; без systemd, init и файлов на диске.
  Root token для dev генерируется визардом и передаётся только через env.

### 5.8 Проверка

- `openbao_server::status` использует `bao status -format=json` при наличии
  бинарника; иначе `GET /v1/sys/health`.
- Health считается успешным при HTTP 200/429/472/473 (standby/initialized/
  unsealed — допустимые состояния), но `sealed=true` для prod — ошибка.
- После apply визард показывает `systemctl status`, `bao status` и путь к
  init-файлу; root token не печатается.

## 6. Клиентский модуль `lib/integration/openbao.sh`

### 6.1 Метаданные и зависимости

- `#!/usr/bin/env bs`, `# shellcheck shell=bash`, `# @shell bash4`.
- `bs::guard "LIB_INTEGRATION_OPENBAO"`.
- Зависимости: `core/const`, `core/logger`, `core/utils`; для скачивания
  релиза серверный модуль использует `lib/integration/http`.
- API-запросы идут через приватный `curl`-помощник: OpenBao отвечает
  осмысленными не-2xx кодами (`sys/health`), а `http::request` их теряет.
  Требуется `curl`; `wget` для API не поддерживается (`LIST`/`DELETE` и
  разбор статуса).
- `jq` нужен для typed helpers; без него generic request работает, helpers
  возвращают `LIB_ERROR_DEPENDENCY_MISSING`.

### 6.2 Аутентификация и TLS

- `openbao::init`:
  - `BS_OPENBAO_ADDR` → `BAO_ADDR` → `https://127.0.0.1:8200`;
  - токен: `BS_OPENBAO_TOKEN` → `BAO_TOKEN` → файл
    `BS_OPENBAO_TOKEN_FILE` (обрезать whitespace, не логировать);
  - CA: `BS_OPENBAO_CACERT` → `BAO_CACERT`; для curl выставляется
    `CURL_CA_BUNDLE` только на время запроса;
  - namespace: `BS_OPENBAO_NAMESPACE` → `BAO_NAMESPACE`.
- `openbao::login <token>` — проверить `lookup-self`, записать токен в файл
  `0600` (каталог `0700`), не эхоить.
- `openbao::logout` — удалить файл токена.
- `openbao::token` — напечатать токен только по явному запросу (для
  диагностики), с предупреждением в stderr.

### 6.3 Generic request

`openbao::request <METHOD> <PATH> [JSON]`

- Строит URL `<addr>/v1/<path>` (path без `/v1` тоже принимается).
- Заголовки: `X-Vault-Token`, `X-Vault-Namespace` (при наличии),
  `Content-Type: application/json`.
- Приватный помощник вызывает `curl -sS -X <method> -w '\n%{http_code}'`,
  тело пишет в stdout, HTTP-статус — в `OPENBAO_LAST_STATUS` (глобальная,
  не экспортируется). Токен передаётся через заголовок, не через argv.
- `BS_OPENBAO_DRY_RUN=1` → печать метода/пути без тела и токена.
- Ошибки: `OPENBAO_ERROR_HTTP`, `OPENBAO_ERROR_AUTH` (401/403),
  `OPENBAO_ERROR_JSON`, `OPENBAO_ERROR_MISSING_DEPS`,
  `OPENBAO_ERROR_INVALID`.
- Никогда не печатает токен; при ошибке — тело ответа OpenBao без заголовков.
- `openbao::health` — исключение: 200/429/472/473/501/503 считаются
  валидными ответами, решение принимает вызывающий по `OPENBAO_LAST_STATUS`
  и `sealed`.

### 6.4 Типовые helpers

| Функция | Endpoint |
|---|---|
| `openbao::health` | `GET sys/health` |
| `openbao::seal_status` | `GET sys/seal-status` |
| `openbao::unseal <key>` | `POST sys/unseal` |
| `openbao::seal` | `POST sys/seal` |
| `openbao::leader` | `GET sys/leader` |
| `openbao::kv::get <mount> <path>` | `GET <mount>/data/<path>` |
| `openbao::kv::put <mount> <path> <json>` | `POST <mount>/data/<path>` |
| `openbao::kv::delete <mount> <path>` | `DELETE <mount>/data/<path>` |
| `openbao::kv::list <mount> <path>` | `LIST <mount>/metadata/<path>` |
| `openbao::kv::metadata <mount> <path>` | `GET <mount>/metadata/<path>` |
| `openbao::auth::lookup` | `GET auth/token/lookup-self` |
| `openbao::auth::create <json>` | `POST auth/token/create` |
| `openbao::auth::revoke <token>` | `POST auth/token/revoke` |
| `openbao::policy::list` | `LIST sys/policies/acl` |
| `openbao::policy::read <name>` | `GET sys/policies/acl/<name>` |
| `openbao::policy::write <name> <file>` | `PUT sys/policies/acl/<name>` |
| `openbao::mount::list` | `GET sys/mounts` |
| `openbao::mount::enable <path> <type>` | `POST sys/mounts/<path>` |
| `openbao::mount::disable <path>` | `DELETE sys/mounts/<path>` |
| `openbao::namespace::list` | `LIST sys/namespaces` |
| `openbao::namespace::create <name>` | `POST sys/namespaces/<name>` |

- `kv::*` работают с KV v2 (`<mount>/data/<path>`), mount по умолчанию
  `secret`; путь проверяется на пустоту и `..`.
- `policy::write` читает файл, JSON-экранирует через `jq -Rs`, не кладёт
  политику в argv.
- Все helpers возвращают JSON как есть; преобразование — через `jq` у
  вызывающего.

## 7. Визард `examples/openbao_wizard.sh`

### 7.1 Каркас

- `#!/usr/bin/env bs`, `# shellcheck shell=bash`.
- `load "lib/ui/wizard"`, `lib/ui/steplog`, `lib/ui/presentation`,
  `lib/system/apply`, `lib/system/openbao`, `lib/integration/openbao`.
- `--help` — без запуска, без создания журнала и без проверки root.
- `--dry-run` → `BS_OPENBAO_DRY_RUN=1`, `FRAMEWORK_DRY_RUN=true`.
- `--verbose` — дублировать журнал в stderr.
- `steplog::init "${TMPDIR:-/tmp}/openbao_wizard.log"`.
- `steplog::on_exit wizard::__restore`; SIGINT — восстановить терминал.
- Запуск только при `BASH_EXECUTION_STRING` или `BASH_SOURCE[0]==$0`,
  чтобы unit-тесты могли source без запуска.

### 7.2 Шаги

1. **Роль** — `Сервер` / `Клиент` / `Сервер + клиент`.
2. **Профиль сервера** — `dev` / `prod`; для client шаг пропускается.
3. **Проверка окружения**:
   - сервер: root, Linux, systemd (prod), архитектура, `curl`/`wget`,
     `sha256sum`, `tar`, `openssl` (self-signed);
   - клиент: `curl`/`wget`, `jq` (для helpers).
4. **Установка** — найден `bao` → показать версию и спросить «использовать
   его?»; иначе скачать.
5. **Адрес** — `127.0.0.1:8200` или `0.0.0.0:8200` (prod, с предупреждением);
   для клиента — полный `https://...`.
6. **TLS** — `самоподписанный` / `существующие файлы` / `без TLS` (только
   dev); для client — CA-файл.
7. **Токен** — для client: вставить токен (скрытый ввод), прочитать из
   файла или пропустить; проверить `lookup-self`.
8. **Сводка** — рамка с путями, профилем, адресом, тем, что будет создано;
   предупреждения о перезаписи и о том, что init-файл содержит секреты.
9. **Применение** — шаги с `step_go/step_ok`, при ошибке — `wizard::fail`
   с командой и путём к журналу.
10. **Итог** — `presentation`/`wizard::box`: статус, `systemctl status`,
    `bao status`, путь к init-файлу, следующий шаг. Для client — команда
    проверки и путь к токену.

### 7.3 Безопасность и UX

- Root token и unseal-ключи не печатаются; только путь.
- Пароль/токен — `wizard::ask_pass`; не попадает в `steplog`.
- Перед перезаписью существующего конфига/юнита — backup и подтверждение.
- Если сервер уже инициализирован — не делать повторный `operator init`;
  предложить unseal.
- Если сервер sealed — предложить unseal из init-файла.
- `--dry-run` показывает команды и файлы, но не создаёт пользователя,
  каталоги, сертификаты и не запускает сервис.
- Отмена на любом шаге: `Ничего не изменено` (если изменения ещё не
  начались) или список уже выполненных шагов; exit 0.

## 8. Документация

- `documentation/en/03-modules/system-openbao.md` и RU-зеркало: профили,
  хуки, API, безопасность, примеры.
- `documentation/en/03-modules/integration-openbao.md` и RU-зеркало:
  аутентификация, TLS, generic request, helpers, коды ошибок.
- `documentation/en|ru/03-modules/lib-modules-overview.md` — добавить оба
  модуля.
- `README.md` — пример `sudo bs run examples/openbao_wizard.sh`.
- `AGENTS.md` — не менять, если не появляется новый тир/группа.

## 9. Тесты

`tests/unit/testopenbaoserverunit.sh`:

- `render_config dev|prod`: TLS, storage, адреса, отсутствие секретов;
- архитектура → имя ассета; неизвестная архитектура → ошибка;
- установка на фейковом релизе (tar.gz + checksums) во временный
  `BS_OPENBAO_BIN`; неверная контрольная сумма → ошибка и нет файла;
- повторная установка той же версии → no-op;
- `ensure_user` на фейковом `useradd` (проверить аргументы, nologin);
- `tls_selfsigned` на реальном `openssl` в temp: ключ `0600`, SAN содержит
  host/127.0.0.1;
- `unit_render` содержит `User=`, `ExecStart=`, `ReadWritePaths=`;
- `init_cluster` на фейковом `bao`: JSON `0600`, повторный вызов не
  переинициализирует;
- `unseal` на фейковом `bao`/HTTP: 3 ключа, `sealed=false`; при 2 ключах —
  ошибка;
- dry-run не создаёт файлов.

`tests/unit/testopenbaoclientunit.sh`:

- приоритет addr/token: `BS_*` → `BAO_*` → файл;
- файл токена с whitespace читается без лишних символов;
- `request` на фейковом `curl`: URL `/v1/...`, заголовки, тело, отсутствие
  токена в argv/логе;
- ошибки HTTP/auth/JSON;
- `login` пишет `0600`, каталог `0700`; `logout` удаляет;
- `kv::get/put/list` формируют правильные пути; `..` отклоняется;
- `policy::write` не кладёт политику в argv.

`tests/unit/testopenbaowizardunit.sh`:

- source без запуска main;
- `--help` не создаёт журнал и не требует root;
- шаги/дефолты, dry-run;
- при уже существующем init-файле выбирается unseal, а не init;
- отмена на каждом шаге не меняет систему (фейковые модули).

Все тесты — без сети и без реального OpenBao; внешние команды — фейки в
`PATH`, системные пути — в `BS_OPENBAO_*` temp-каталогах.

## 10. Валидация

После реализации:

```bash
bash tests/validatesyntax.sh
bash tests/unit/testopenbaoserverunit.sh
bash tests/unit/testopenbaoclientunit.sh
bash tests/unit/testopenbaowizardunit.sh
bash tests/runalltests.sh
shellcheck -s bash --severity=error lib/system/openbao.sh \
  lib/integration/openbao.sh examples/openbao_wizard.sh
```

## 11. Этапы

1. Клиентский модуль + тесты (не требует root и сети).
2. Серверный модуль + тесты на фейках.
3. Визард + тесты source/dry-run.
4. Документация en/ru.
5. Полная валидация и ручной smoke в контейнере/VM (dev и prod) — пройдены на OpenBao 2.7.1.

## 12. Вне scope

- OAuth2/OAuth1 и их визарды — отдельный дизайн.
- HA/raft-кластер, auto-unseal через KMS/Transit, миграция с Vault.
- Пакетные менеджеры (deb/rpm) и обновление OpenBao.
- Хранение секретов в keyring.
