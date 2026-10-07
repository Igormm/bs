# Output format contract for bare-metal data methods

Date: 2026-10-07
Status: review

## 1. Goal

Every read-only **bare-metal data getter** of the framework (state of a Linux
machine: network, hardware, OS, accounts, processes) must be able to render its
result as `string`, `json`, or `xml` — selected by a parameter — without each
method re-implementing the three formats. The default `string` output of a
scalar getter (e.g. an IP) stays a plain value so existing users are unaffected.

## 2. Architecture (orthogonal layers)

```
getter method  ->  canonical record (key=value lines)  ->  lib/data/format.sh  ->  renderer
                                                              |
                                              (optional) lib/integration/result envelope
```

- The **method** acquires data and emits a canonical record. It knows nothing
  about json/xml.
- **`lib/data/format.sh`** renders a stream of canonical records in one of the
  formats via a registry (Strategy/dispatch table), pure bash, no external deps.
- **`lib/integration/result`** provides the machine envelope
  (`success/exit_code/data/...`) for cases that need it; format does not
  duplicate it.
- **CLI** maps `--format` to `BS_OUTPUT_FORMAT` (via `core/args`); library
  callers set the env or pass the format to the method.

This makes `N getters × M formats = N + M` code, not `N × M`.

## 3. Canonical record grammar

- One field per line: `key=value`. The split is on the **first** `=` (values may
  contain `=`).
- A **blank line** separates records (for getters returning several rows).
- Order is preserved as emitted.
- Keys are `[A-Za-z_][A-Za-z0-9_]*`; values are arbitrary UTF-8.

## 4. Module `lib/data/format.sh`

### 4.1 Globals (hooks / constants)

| Variable | Default | Purpose |
|---|---|---|
| `BS_OUTPUT_FORMAT` | `string` | selected format (hook, env-overridable) |
| `BS_FORMAT_ROOT` | `record` | XML root element name (hook) |
| `FORMATTERS` | assoc | `format=render-function` registry (constant) |
| `FORMAT_NAMES` | array | `string json xml` (constant) |

### 4.2 API

| Function | Purpose |
|---|---|
| `format::list` | stdout: available formats, one per line |
| `format::validate <f>` | `E_SUCCESS` / `LIB_ERROR_INVALID_INPUT` |
| `format::record <key> <value> [<key> <value> ...]` | stdout: canonical lines |
| `format::emit <format>` | stdin: canonical records → stdout: rendered |
| `format::render::string` | stdin canonical → stdout human |
| `format::render::json` | stdin canonical → stdout JSON |
| `format::render::xml` | stdin canonical → stdout XML |

Private: `format::__json_escape`, `format::__xml_escape`.

### 4.3 Renderer behavior

- **string** — a single record with a single field prints the **value only**
  (scalar default, e.g. `system::network::interface` → `1.2.3.4`). Otherwise
  `key: value` per line; records separated by one blank line.
- **json** — one record → object; several → array of objects. Empty input → `{}`.
  Escapes `"`, `\`, `\n`, `\r`, `\t`, and control chars `< 0x20`.
- **xml** — one record → `<record>…</record>`; several →
  `<records>…</records>`; each field `<key>value</key>`. Root name from
  `BS_FORMAT_ROOT` (for one record) is used as-is. Escapes `& < > " '`.
  Empty input → `<record/>`.

### 4.4 Errors

- Unknown format → `LIB_ERROR_INVALID_INPUT`.
- Empty format argument → `LIB_ERROR_INVALID_ARGS`.

## 5. Reuse from `lib/data/dataprocessor` (variant B)

- Take: the format **names** (`json`, `xml`) and the `detect_format` idea.
- Optional: for **nested** structures, delegate `json → xml` to
  `dataprocessor::convert` when `jq`/`xmllint` are present; otherwise use the
  pure-bash renderer. The module never requires `python3`.

## 6. Integration convention

```bash
# scalar getter
system::network::interface() {
    local -r iface="${1:?interface required}"
    local ip family
    # ... acquire ...
    { format::record iface "${iface}"
      format::record ip "${ip}"
      format::record family "${family}"
    } | format::emit "${BS_OUTPUT_FORMAT:-string}"
}
```

- Positional signatures are **unchanged**; `--format` is parsed at the CLI layer
  (`args::flag format value string`) and exported as `BS_OUTPUT_FORMAT`.
- Library callers may pass `BS_OUTPUT_FORMAT=json fn ...`.
- `string` is the default and must reproduce the current human output.

## 7. Scope and migration batches

**Criterion:** read-only *data getters* in `lib/system/*`, `lib/platform/*`,
`lib/network/*` (functions that print machine state). **Excluded:** mutators
(`create/add/delete/install/enable/start/stop/write/apply/set/lock`), interactive
TUI, and pure helper namespaces (`system::utils`, `system::distrologic`).

| Batch | Modules | Notes |
|---|---|---|
| 0 | `lib/data/format.sh` | foundation (this plan) |
| 1 | `system/network`, `system/routing`, `network/avahi`, `network/sshnetwork` (info getters) | reference batch |
| 2 | `system/hw`, `system/gpu`, `system/sensor`, `system/devices`, `system/display` | hardware |
| 3 | `system/info`, `system/distro`, `platform/facts`, `system/time`, `system/locale`, `system/keyboard` | OS / info |
| 4 | `system/users`, `system/permissions`, `system/security`, `system/processes`, `system/services`, `system/systemd`, `system/system`, `system/logging`, `system/packages`, `system/schedule`, `system/safety`, `network/ssh` | accounts / process |

Each batch is a separate implementation plan (one subsystem per plan, per the
plan-writing guidance) so a shipped mistake stays localized and context stays
bounded. "All modules" is satisfied by executing the batches in order.

## 8. Testing

- `tests/unit/testformatunit.sh` — rendering (scalar string, multi-field,
  multi-record), JSON/XML escaping (`" \ < > & '` newline/tab), registry and
  `format::list`, `format::validate`, unknown format error, empty input.
- Per batch: extend that module's unit test to assert each migrated getter
  emits **valid** json/xml (parse with `jq`/`xmllint` when available, else
  structural asserts) and that `string` is unchanged.

## 9. Documentation

- `documentation/en/03-modules/data-format.md` + RU mirror: API, grammar,
  renderer behavior, escaping, examples, error codes.
- `lib-modules-overview.md` (en/ru): add the data group entry.
- `lib/ui/output_contract.sh`: register a `formats` unit pointing at the docs
  and a demo.

## 10. Out of scope

- Mutating methods and their reports (they keep `result`/logger output).
- Interactive TUI rendering (its own contract in `lib/ui/output_contract`).
- A general parser (json→record): only `detect_format`-style detection is
  reused; parsing stays in `dataprocessor`.

## 11. Analogy (why this shape)

A format is a **change of basis**: the data is the invariant object, `json`/`xml`
/`string` are coordinate representations. `json ↔ xml` is an **isomorphism**
(round-trip safe); `→ string` is a **lossy projection** (human view). The
renderer is an operator `R: Data → Representation`, composed as `R ∘ get`.
Keeping one canonical representation and deriving every view from it is exactly
why the layers above stay orthogonal.
