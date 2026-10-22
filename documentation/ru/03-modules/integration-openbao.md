[↑ Оглавление](../README.md)

# Модуль `openbao` (клиент)

`lib/integration/openbao.sh` — API-клиент для [OpenBao](https://openbao.org/),
open-source форка HashiCorp Vault. Он определяет адрес, токен, CA и namespace
из хуков, выполняет запросы через `curl` и даёт типизированные помощники для
KV v2, токенов, ACL-политик, mount и namespace.

Ярус: **bash4 + curl**. `curl` обязателен: `sys/health` в OpenBao возвращает
осмысленные не-2xx статусы (sealed, standby, uninitialized), а `wget` не
позволяет надёжно их получить. `jq` нужен только типизированным помощникам,
которые собирают JSON из пользовательского ввода или читают поля JSON.

Источник: [lib/integration/openbao.sh](../../../lib/integration/openbao.sh)

## Подключение

```bash
#!/usr/bin/env bs

load "lib/integration/openbao"
```

## Настройка

| Переменная | По умолчанию | Назначение |
|---|---|---|
| `BS_OPENBAO_ADDR` | `BAO_ADDR`, затем `https://127.0.0.1:8200` | адрес API |
| `BS_OPENBAO_TOKEN` | `BAO_TOKEN`, затем файл токена | токен |
| `BS_OPENBAO_TOKEN_FILE` | `${XDG_CONFIG_HOME:-$HOME/.config}/bs/openbao-token` | сохранённый токен клиента |
| `BS_OPENBAO_CACERT` | `BAO_CACERT`, затем пусто | CA-сертификат для TLS |
| `BS_OPENBAO_NAMESPACE` | `BAO_NAMESPACE`, затем пусто | namespace OpenBao |
| `BS_OPENBAO_CURL` | `curl` | бинарник curl или тестовый мок |
| `BS_OPENBAO_JQ` | `jq` | бинарник jq или тестовый мок |
| `BS_OPENBAO_TIMEOUT` | `30` | таймаут запроса, секунды |
| `BS_OPENBAO_DRY_RUN` | `0` | `1` = только логировать, ничего не вызывать |

`openbao::init` раскладывает значения в `OPENBAO_ADDR`, `OPENBAO_TOKEN`,
`OPENBAO_CACERT` и `OPENBAO_NAMESPACE`. Явные `BS_*` важнее алиасов `BAO_*`;
пустое значение означает переход к файлу токена.

## Запросы

### `openbao::request <method> <path> [json]`

Универсальный запрос. Путь может быть относительным (`sys/health`,
`/v1/sys/health`) или полным `http://` / `https://` URL. Тело ответа идёт в
stdout, HTTP-статус сохраняется в `OPENBAO_LAST_STATUS`.

```bash
openbao::request GET sys/health
openbao::request POST auth/token/create '{"policies":["default"]}'
```

Подстановка команды выполняется в подшелле, поэтому если нужен
`OPENBAO_LAST_STATUS` в вызывающем коде, сохраняйте тело в файл:

```bash
openbao::request GET sys/health > /tmp/bao-health.json
printf 'status=%s\n' "${OPENBAO_LAST_STATUS}"
```

Токен и namespace пишутся во временный `--config`-файл curl с правами `0600`,
а не передаются как `-H "X-Vault-Token: ..."` в argv, поэтому их не видно в
списке процессов. Временный файл удаляется после запроса. Пути с `..`,
управляющими символами или пробелами отклоняются.

### `openbao::health`

Возвращает тело health. Статусы OpenBao `200`, `429`, `472`, `473`, `501` и
`503` считаются допустимым ответом и дают `0`; ошибки транспорта и прочие
статусы возвращают `OPENBAO_ERROR_HTTP`.

```bash
if health="$(openbao::health)"; then
    printf '%s\n' "${health}"
fi
```

### Жизненный цикл токена

```bash
openbao::login "hvs...."   # проверить auth/token/lookup-self и сохранить 0600
openbao::logout            # удалить сохранённый токен
openbao::token             # явный диагностический вывод; не логировать
```

`openbao::login` атомарно пишет в `BS_OPENBAO_TOKEN_FILE`; каталог создаётся с
правами `0700`, файл — `0600`. Отвергнутый токен не сохраняется.
`openbao::token` существует отдельно: обычный код не должен печатать токены.

### Seal и лидер

```bash
openbao::seal_status
openbao::unseal "$key"
openbao::seal
openbao::leader
```

### KV v2

```bash
openbao::kv::get secret app/db
openbao::kv::put secret app/db '{"password":"s3cret"}'
openbao::kv::delete secret app/db
openbao::kv::list secret app
openbao::kv::metadata secret app/db
```

Mount по умолчанию — `secret`; другой mount передаётся первым аргументом. Третий
аргумент `openbao::kv::put` — объект полей секрета; helper оборачивает его в
KV v2-конверт `data`. Пути, начинающиеся с `/`, содержащие `..` или управляющие
символы, отклоняются.

### Токены, политики, mount, namespace

```bash
openbao::auth::lookup
openbao::auth::create '{"policies":["app"],"ttl":"1h"}'
openbao::auth::revoke "$token"

openbao::policy::list
openbao::policy::read app
openbao::policy::write app ./app-policy.hcl

openbao::mount::list
openbao::mount::enable kv-custom kv
openbao::mount::enable pki-custom pki '{"max_lease_ttl":"87600h"}'
openbao::mount::disable kv-custom

openbao::namespace::list
openbao::namespace::create team-a
```

JSON-аргументы проверяются до запроса; файл политики экранируется через
`jq -Rs` и отправляется как JSON-строка, а не склеивается вручную.

`openbao::mount::enable path kv` по умолчанию включает KV v2; третий
JSON-объект переопределяет options mount.

## Коды ошибок

| Код | Значение | Смысл |
|---|---|---|
| `OPENBAO_ERROR_HTTP` | `240` | сбой транспорта или неожиданный HTTP-статус |
| `OPENBAO_ERROR_AUTH` | `241` | `401` / `403` |
| `OPENBAO_ERROR_JSON` | `242` | неверный JSON-аргумент или сбой JSON-инструмента |

Для отсутствующих зависимостей, неверного ввода и файловых операций
используются стандартные коды `LIB_ERROR_*`.

## Пример

```bash
#!/usr/bin/env bs

load "lib/integration/openbao"

export BS_OPENBAO_ADDR="https://127.0.0.1:8200"
export BS_OPENBAO_CACERT="/etc/openbao/tls/ca.crt"
openbao::login "$(cat /run/secrets/openbao-token)"

openbao::kv::put secret app/db '{"password":"s3cret"}'
openbao::kv::get secret app/db
```

Для пошаговой настройки есть визард:

```bash
bs run examples/openbao_wizard.sh --role client
```

## Зависимости

- `core/const`, `core/logger`, `core/utils` — модули ядра BS.
- `curl` — обязательный HTTP-транспорт.
- `jq` — нужен типизированным JSON-помощникам.
