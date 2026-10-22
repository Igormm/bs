[↑ Documentation index](../README.md)

# Module `openbao` (server)

`lib/system/openbao.sh` installs an OpenBao release, creates the service user,
writes the HCL config and systemd unit, initializes the cluster, unseals it and
checks readiness. It is the server-side counterpart of
[lib/integration/openbao.sh](integration-openbao.md).

Tier: **Linux only** (writes under `/etc`, `/var/lib`, `/usr/local/bin` and
uses systemd). It degrades with defined `LIB_ERROR_*` codes when a tool or
permission is missing; it never reports a silent success.

Source: [lib/system/openbao.sh](../../../lib/system/openbao.sh)

## Loading

```bash
#!/usr/bin/env bs

load "lib/system/openbao"
```

## Profiles

| Profile | Behaviour |
|---|---|
| `dev` | install the binary, HTTP on loopback, generated root token, foreground `bao server -dev` |
| `prod` | system user, file storage, TLS, systemd unit, `operator init`, automatic unseal, health check |

`prod` is the default for `openbao_server::apply`.

## Hooks

| Variable | Default | Purpose |
|---|---|---|
| `BS_OPENBAO_VERSION` | `latest` | release version or `latest` |
| `BS_OPENBAO_BIN` | `/usr/local/bin/bao` | binary path |
| `BS_OPENBAO_CONFIG` | `/etc/openbao/openbao.hcl` | HCL config |
| `BS_OPENBAO_CONFIG_DIR` | `/etc/openbao` | config directory |
| `BS_OPENBAO_DATA_DIR` | `/var/lib/openbao` | data/storage directory |
| `BS_OPENBAO_TLS_DIR` | `/etc/openbao/tls` | TLS directory |
| `BS_OPENBAO_TLS_MODE` | `selfsigned` | `selfsigned`, `files` or `off` |
| `BS_OPENBAO_TLS_CERT` | `${TLS_DIR}/server.crt` | server certificate |
| `BS_OPENBAO_TLS_KEY` | `${TLS_DIR}/server.key` | server key |
| `BS_OPENBAO_TLS_CA` | `${TLS_DIR}/ca.crt` | CA for clients |
| `BS_OPENBAO_LISTEN` | `127.0.0.1:8200` | listener `host:port` |
| `BS_OPENBAO_INIT_FILE` | `/root/openbao-init.json` | `operator init` JSON |
| `BS_OPENBAO_SERVICE` | `openbao` | systemd unit name |
| `BS_OPENBAO_USER` / `BS_OPENBAO_GROUP` | `openbao` | service account |
| `BS_OPENBAO_RELEASE_BASE` | GitHub releases | release download base |
| `BS_OPENBAO_API_BASE` | GitHub latest-release API | latest version lookup |
| `BS_OPENBAO_LATEST_VERSION` | empty | pre-resolved latest version for tests |
| `BS_OPENBAO_INIT_SHARES` / `BS_OPENBAO_INIT_THRESHOLD` | `5` / `3` | unseal shares |
| `BS_OPENBAO_DEV_TOKEN` | empty | fixed dev root token |
| `BS_OPENBAO_DEV_LISTEN` | `127.0.0.1:8200` | dev listener |
| `BS_OPENBAO_DRY_RUN` | `0` | `1` = print actions, change nothing |
| `BS_OPENBAO_TIMEOUT` | `30` | readiness timeout, seconds |

All paths used inside HCL or the unit are checked for newlines and quotes.

## Lifecycle

```bash
openbao_server::init          # validate hooks and platform
openbao_server::install       # download, sha256-verify, atomic install
openbao_server::ensure_user   # useradd --system + lock password
openbao_server::tls_selfsigned localhost 127.0.0.1
openbao_server::configure prod
openbao_server::install_service
openbao_server::wait_ready
openbao_server::init_cluster
openbao_server::unseal
openbao_server::status
```

`openbao_server::install` resolves `latest` through the GitHub API, downloads
`openbao_<version>_linux_<arch>.tar.gz` and `checksums.txt`, verifies SHA-256,
extracts the executable `bao` and replaces the target atomically. An installed
matching version is a no-op.

`openbao_server::tls_selfsigned` creates a 4096-bit CA and server key,
signs the server certificate with SANs for the supplied hosts plus
`localhost`, `127.0.0.1` and `::1`, and sets the key mode to `0600`.

`openbao_server::configure` creates the data and config directories, backs up
an existing config and writes the new HCL with mode `0640`. TLS modes:

- `selfsigned` — generate a CA and server certificate if missing.
- `files` — require readable `BS_OPENBAO_TLS_CERT` and `BS_OPENBAO_TLS_KEY`.
- `off` — HTTP; intended for dev and explicitly warned about in the wizard.

`openbao_server::init_cluster` runs `bao operator init -format=json`, validates
the JSON and writes the keys plus root token to `BS_OPENBAO_INIT_FILE` with
mode `0600`. If the file already exists it refuses with
`LIB_ERROR_CONFLICT`. `openbao_server::unseal` reads
`.unseal_keys_b64[]`, submits up to the threshold and verifies that
`sys/seal-status` reports `sealed: false`.

## Apply

```bash
openbao_server::apply dev    # install only; the caller runs dev_start
openbao_server::apply prod   # install → user → config → systemd → init → unseal
openbao_server::dev_command  # print the foreground dev command
openbao_server::dev_start    # exec the dev server in this terminal
```

`apply prod` starts the service before `init_cluster`, so the first health
check may legitimately see `503` (uninitialized/sealed); it then initializes,
unseals and waits for a healthy answer again.

## Security notes

- The init file contains unseal keys and the root token; keep it `0600` and
  off backups that are not encrypted. `apply prod` never prints it.
- The systemd unit runs as the unprivileged service user with
  `NoNewPrivileges`, `PrivateTmp`, `ProtectSystem=strict` and
  `ProtectHome`; only `BS_OPENBAO_DATA_DIR` is writable.
- The client token is written through `openbao::login` with mode `0600`.
- Tokens are sent through a temporary curl config file, not curl argv.

## Error codes

Standard `LIB_ERROR_*` codes are used for invalid input, missing files,
missing dependencies, conflicts, timeouts and file operations. Release
verification failures return `LIB_ERROR_INVALID_INPUT`; HTTP failures return
`INTEGRATION_ERROR_HTTP`; invalid `operator init` JSON returns
`OPENBAO_ERROR_JSON`.

## Wizard

`examples/openbao_wizard.sh` is a full-screen TUI over this module and the
client module: role (`server`, `client`, `both`), profile (`dev`, `prod`),
listen address, TLS mode/files, client address/CA/token, confirmation,
install, systemd, init/unseal and a step log.

```bash
sudo bs run examples/openbao_wizard.sh --profile prod
bs run examples/openbao_wizard.sh --role client
bs run examples/openbao_wizard.sh --dry-run
```

## Dependencies

- `core/const`, `core/logger`, `core/utils`, `lib/io/files`,
  `lib/system/systemd`, `lib/system/user`, `lib/integration/http`,
  `lib/integration/openbao`.
- `curl` or `wget` (release download), `sha256sum`, `tar`, `gzip`,
  `openssl` for self-signed TLS, `systemctl`, `useradd`.
