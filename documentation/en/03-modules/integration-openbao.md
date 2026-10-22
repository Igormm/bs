[↑ Documentation index](../README.md)

# Module `openbao` (client)

`lib/integration/openbao.sh` is the API client for [OpenBao](https://openbao.org/),
the open-source fork of HashiCorp Vault. It resolves the address, token, CA and
namespace from hooks, sends requests through `curl`, and provides typed helpers
for KV v2, tokens, ACL policies, mounts and namespaces.

Tier: **bash4 + curl**. `curl` is required because OpenBao's `sys/health`
endpoint returns meaningful non-2xx statuses (sealed, standby, uninitialized);
`wget` cannot expose them reliably. `jq` is required only for the typed helpers
that build JSON from user input or read JSON fields.

Source: [lib/integration/openbao.sh](../../../lib/integration/openbao.sh)

## Loading

```bash
#!/usr/bin/env bs

load "lib/integration/openbao"
```

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `BS_OPENBAO_ADDR` | `BAO_ADDR`, then `https://127.0.0.1:8200` | API address |
| `BS_OPENBAO_TOKEN` | `BAO_TOKEN`, then the token file | token |
| `BS_OPENBAO_TOKEN_FILE` | `${XDG_CONFIG_HOME:-$HOME/.config}/bs/openbao-token` | saved client token |
| `BS_OPENBAO_CACERT` | `BAO_CACERT`, then empty | CA bundle for TLS |
| `BS_OPENBAO_NAMESPACE` | `BAO_NAMESPACE`, then empty | OpenBao namespace |
| `BS_OPENBAO_CURL` | `curl` | curl binary or test fake |
| `BS_OPENBAO_JQ` | `jq` | jq binary or test fake |
| `BS_OPENBAO_TIMEOUT` | `30` | per-request timeout, seconds |
| `BS_OPENBAO_DRY_RUN` | `0` | `1` = log requests, call nothing |

`openbao::init` resolves these values into `OPENBAO_ADDR`, `OPENBAO_TOKEN`,
`OPENBAO_CACERT` and `OPENBAO_NAMESPACE`. Explicit `BS_*` values win over the
`BAO_*` aliases; an empty value falls back to the token file.

## Requests

### `openbao::request <method> <path> [json]`

Generic request. The path may be relative (`sys/health`, `/v1/sys/health`) or a
full `http://` / `https://` URL. The response body goes to stdout. The HTTP
status is stored in `OPENBAO_LAST_STATUS`.

```bash
openbao::request GET sys/health
openbao::request POST auth/token/create '{"policies":["default"]}'
```

Because command substitution runs in a subshell, capture the body through a
file when you need `OPENBAO_LAST_STATUS` in the caller:

```bash
openbao::request GET sys/health > /tmp/bao-health.json
printf 'status=%s\n' "${OPENBAO_LAST_STATUS}"
```

The token and namespace are written to a temporary curl `--config` file with
mode `0600`, not passed as `-H "X-Vault-Token: ..."` in argv, so they do not
appear in the process list. The temporary file is removed after the request.
Paths containing `..`, control characters or whitespace are rejected.

### `openbao::health`

Returns the health body. OpenBao's `200`, `429`, `472`, `473`, `501` and `503`
are valid health answers and return `0`; transport errors and other statuses
return `OPENBAO_ERROR_HTTP`.

```bash
if health="$(openbao::health)"; then
    printf '%s\n' "${health}"
fi
```

### Token lifecycle

```bash
openbao::login "hvs...."   # verify auth/token/lookup-self, then save 0600
openbao::logout            # remove the saved token
openbao::token             # explicit diagnostic print; never log it
```

`openbao::login` writes atomically to `BS_OPENBAO_TOKEN_FILE`; the directory is
created with mode `0700` and the file with `0600`. A rejected token is never
saved. `openbao::token` is intentionally separate: normal code should not print
tokens.

### Seal and leadership

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

The default mount is `secret`; pass another mount as the first argument. Paths
starting with `/`, containing `..` or control characters are rejected.

### Tokens, policies, mounts, namespaces

```bash
openbao::auth::lookup
openbao::auth::create '{"policies":["app"],"ttl":"1h"}'
openbao::auth::revoke "$token"

openbao::policy::list
openbao::policy::read app
openbao::policy::write app ./app-policy.hcl

openbao::mount::list
openbao::mount::enable kv-custom kv
openbao::mount::disable kv-custom

openbao::namespace::list
openbao::namespace::create team-a
```

JSON arguments are validated before a request; a policy file is JSON-escaped
through `jq -Rs`, so it is sent as a JSON string, not concatenated.

## Error codes

| Code | Value | Meaning |
|---|---|---|
| `OPENBAO_ERROR_HTTP` | `240` | transport failure or unexpected HTTP status |
| `OPENBAO_ERROR_AUTH` | `241` | `401` / `403` |
| `OPENBAO_ERROR_JSON` | `242` | invalid JSON argument or JSON tooling failure |

Standard `LIB_ERROR_*` codes are used for missing dependencies, invalid input
and file operations.

## Example

```bash
#!/usr/bin/env bs

load "lib/integration/openbao"

export BS_OPENBAO_ADDR="https://127.0.0.1:8200"
export BS_OPENBAO_CACERT="/etc/openbao/tls/ca.crt"
openbao::login "$(cat /run/secrets/openbao-token)"

openbao::kv::put secret app/db '{"password":"s3cret"}'
openbao::kv::get secret app/db
```

For a guided setup use the wizard:

```bash
bs run examples/openbao_wizard.sh --role client
```

## Dependencies

- `core/const`, `core/logger`, `core/utils` — BS core modules.
- `curl` — required HTTP transport.
- `jq` — required by typed JSON helpers.
