[↑ Documentation index](../README.md)

# Testing

How the BS test suite is organized, how to run it, and how to write new tests.

## Layout

All tests live in `tests/`, grouped by type:

```
tests/
├── runalltests.sh                 # Main test runner
├── testframework.sh               # Assertion helpers for writing tests
├── validatesyntax.sh              # bash -n syntax validation
├── validateshellcheck.sh          # ShellCheck validation
├── unit/                          # Unit tests for core and lib modules
│   ├── testargsunit.sh            # core/args
│   ├── testconstunit.sh           # core/const: error codes, const::error_description
│   ├── testerrorhandlerunit.sh    # core/errorhandler: errorhandler::throw, cleanup stack
│   ├── testloaderunit.sh          # bootstrap/loader: load, re-loads, errors
│   ├── testloggerunit.sh          # core/logger: levels, formatting
│   ├── testplatformcheckunit.sh   # lib/system/platformcheck
│   ├── testps1configunit.sh       # lib/ui/ps1config
│   ├── teststreamsunit.sh         # lib/io/streams (io::streams)
│   └── testversionunit.sh         # core/version: bs::version::compare
├── integration/                   # Integration tests (mocked)
│   ├── testvkapi.sh               # lib/integration/vkapi (curl mock)
│   ├── testvkmusic.sh             # lib/integration/vkmusic (curl/vkapi mocks, isolated HOME)
│   └── testwireguard.sh           # lib/integration/wireguard — requires root, see below
├── data/
│   └── testdataprocessor.sh       # lib/data/dataprocessor (jq/xmllint/pyyaml)
├── frameworks/
│   └── testframeworksintegration.sh # lib/frameworks/frameworksintegration
├── network/
│   └── testsshnetwork.sh          # lib/network/sshnetwork (ssh/scp/rsync/nmap mocks)
├── status/
│   └── testps1status.sh           # lib/status/ps1status
├── audit/
│   └── testsystemaudit.sh         # lib/audit/systemaudit — requires root, see below
└── demos/
    └── testps1configdemo.sh       # ps1config module demo
```

## Running the full suite

```bash
bash tests/runalltests.sh        # from the project root
cd tests && bash runalltests.sh  # or from tests/
```

Paths are resolved from the script location, so the run works from any directory. The runner walks the directories in this order: `unit`, `integration`, `data`, `frameworks`, `network`, `status`, `audit`, `demos`, then prints a summary (total / passed / failed / skipped) and exits `0` if nothing failed, `1` otherwise. An unknown option exits with code `2`.

The default run needs no root and writes nothing to `/etc` or the real `~/.config`: modules that touch the home directory are tested in an isolated temporary `HOME`.

### Destructive / root-requiring tests

Two tests are skipped by default with an explicit message:

- `integration/testwireguard.sh` — writes to `/etc/wireguard` and `/var/backups/wireguard`, brings up network interfaces; requires root.
- `audit/testsystemaudit.sh` — replaces `/etc/ssh/sshd_config` and `/etc/security/pwquality.conf`; requires root.

Run them only explicitly and only as root:

```bash
sudo bash tests/runalltests.sh --with-root
```

With `--with-root` but without root privileges they are still skipped (with the reason `EUID != 0`).

## Running a single test

Every test file is a standalone script:

```bash
bash tests/unit/testloggerunit.sh        # from the root
cd tests/unit && bash testloggerunit.sh  # or from the test's directory
```

## Writing a test

Test files source `tests/testframework.sh`, which provides assertions and counters:

| Function | Purpose |
|---|---|
| `testframework::init` | Reset counters and announce the framework |
| `testframework::section "name"` | Print a section header |
| `testframework::assert_true "cond" "name"` | Pass if condition is true (`"true"`/`"false"` or a `[[ ... ]]` expression) |
| `testframework::assert_false "cmd" "name"` | Pass if the command fails |
| `testframework::assert_equal "expected" "$actual" "name"` | String equality |
| `testframework::assert_file_exists "path" "name"` | File exists |
| `testframework::assert_command "cmd" "name"` | Command exits with 0 |
| `testframework::summary` | Print totals; returns 0 when nothing failed |

A typical test (pattern used by the real unit tests):

```bash
#!/usr/bin/env bs
set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"   # needed by lib modules

main() {
    print_header "My Tests"
    testframework::init

    testframework::section "Section"
    testframework::assert_true "true" "True condition"
    testframework::assert_false "some::failing_command" "Command fails"
    testframework::assert_equal "expected" "${result}" "Equality"
    testframework::assert_file_exists "${BS_PROJECT_ROOT}/bs" "File exists"
    testframework::assert_command "ls /tmp" "Command succeeds"

    testframework::summary
}

main "$@"
```

Notes:

- Increment counters as `((++var))`: `((var++))` returns status 1 at zero and kills the script under `set -e`.
- If a module writes to `~/.config` or `~/Music`, export an isolated `HOME=$(mktemp -d)` **before** sourcing the module — readonly paths are derived from `HOME`.
- In your own checks prefer the idioms from `core/utils.sh` over raw redirections: `utils::has cmd` instead of `command -v cmd >/dev/null 2>&1`, `utils::quiet cmd` instead of `>/dev/null 2>&1`, `utils::quiet_err cmd` instead of `2>/dev/null`, `utils::ignore cmd` instead of `>/dev/null 2>&1 || true`.

## Syntax validation

```bash
bash tests/validatesyntax.sh
```

Runs `bash -n` over the required entry points (`bs`, `boot.sh`, `install.sh`, `bootstrap/init.sh`, `bootstrap/loader.sh`) and every `*.sh` file in `core/`, `lib/`, `install/`, and `tests/`. Exits `1` on any syntax error or missing required file, `0` otherwise.

## ShellCheck validation

```bash
bash tests/validateshellcheck.sh             # errors only
bash tests/validateshellcheck.sh --warnings  # + informational warnings
```

Runs `shellcheck -s bash` over all `*.sh` files plus the `bs` script (`-s bash` because the `#!/usr/bin/env bs` shebang is unknown to ShellCheck). Error severity is mandatory: any error exits `1`. Warnings are informational and do not fail the run. If ShellCheck is not installed locally, the script skips with exit code `0` (CI installs it).

## CI

`.github/workflows/ci.yml` runs on every push and pull request, with two jobs:

- **lint** (`ubuntu-latest`) — installs ShellCheck, then runs `bash tests/validatesyntax.sh` and `bash tests/validateshellcheck.sh`.
- **tests** — runs `bash tests/runalltests.sh` inside distribution containers (`fail-fast: false`):

| Matrix entry | Image | Bash |
|---|---|---|
| ubuntu, bash 5.x | `ubuntu:latest` | 5.x |
| debian stable, bash 5.x | `debian:stable` | 5.x |
| almalinux 9, bash 5.1 | `almalinux:9` | 5.1 |
| almalinux 8, bash 4.4 (minimum) | `almalinux:8` | 4.4 — the framework minimum version |

Each container first installs the test dependencies (`git`, `procps`/`procps-ng`, `jq`, `curl`, `openssl`, `python3-yaml`/`python3-pyyaml`, `iproute2`/`iproute`, `nmap`, `rsync`, `openssh-client(s)`, `bc`, and related tools).

## Debugging

```bash
export BS_LOG_LEVEL=DEBUG
bash tests/runalltests.sh

bash -x tests/unit/testloggerunit.sh
```

Result markers: `✓ PASSED` (green), `✗ FAILED` (red), `⊘ SKIP` (yellow, with a reason), `▶ RUNNING` (blue).
