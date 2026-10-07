[↑ Documentation index](../README.md)

# Module `format`

Render canonical data records as `string`, `json`, or `xml` — selected by a
parameter. Methods emit data once as canonical `key=value` records; the format
layer turns them into the requested representation. Dependency-free (pure Bash);
no `jq`/`python3` required.

Tier: **portable** (pure Bash 4.2+).

Source: [lib/data/format.sh](../../../lib/data/format.sh)

## Loading

```bash
#!/usr/bin/env bs

load "lib/data/format"
```

## Test hooks

| Variable | Default | Purpose |
|---|---|---|
| `BS_OUTPUT_FORMAT` | `string` | selected format (`string`/`json`/`xml`) |
| `BS_FORMAT_ROOT` | `record` | XML root element name (single record) |

## Canonical grammar

- One field per line: `key=value`; the split is on the **first** `=`, so values
  may contain `=`.
- A blank line separates records (a getter returning several rows).
- Field order is preserved as emitted.

## API

```bash
format::list                    # string, json, xml (one per line)
format::validate json           # E_SUCCESS / LIB_ERROR_INVALID_INPUT
format::record iface eth0 ip 192.0.2.10   # canonical lines on stdout
format::emit json               # stdin canonical records → stdout rendered
format::emit_lines route        # each input line → its own record (blob getters)
format::render::string          # per-format renderers
format::render::json
format::render::xml
```

## Rendering

`string` — a lone field prints **its value only** (the human default for a
scalar such as an IP); several fields print `key=value`:

```bash
printf 'ip=192.0.2.10\n' | format::emit string      # 192.0.2.10
printf 'iface=eth0\nip=192.0.2.10\n' | format::emit string
# iface=eth0
# ip=192.0.2.10
```

`json` — one record → object, several → array of objects; escapes `" \ \n \r \t`
and control characters:

```bash
printf 'ip=192.0.2.10\n' | format::emit json        # {"ip":"192.0.2.10"}
printf 'a=1\n\na=2\n'    | format::emit json        # [{"a":"1"},{"a":"2"}]
format::emit json </dev/null                        # {}
```

`xml` — one record → `<record>…</record>`, several →
`<records><record>…</record>…</records>`; escapes `& < > " '`; the root name is
`BS_FORMAT_ROOT`:

```bash
printf 'ip=192.0.2.10\n' | format::emit xml
# <record><ip>192.0.2.10</ip></record>
BS_FORMAT_ROOT=node format::emit xml <<< 'k=v'
# <node><k>v</k></node>
```

## Method integration

```bash
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

Positional signatures stay unchanged; `--format` is parsed by the CLI (via
`core/args`) and exported as `BS_OUTPUT_FORMAT`. Library callers may set
`BS_OUTPUT_FORMAT=json` (or `xml`) in the environment.

## Error codes

| Code | Meaning |
|---|---|
| `E_SUCCESS` | rendered |
| `LIB_ERROR_INVALID_ARGS` | empty format argument |
| `LIB_ERROR_INVALID_INPUT` | unknown format |

## Why this shape

A format is a change of basis over the data: `json`/`xml` are isomorphic (round-
trip safe), `string` is a lossy projection for humans. One canonical form derived
from every view keeps the layers orthogonal (`N getters + M formats`, not
`N × M`). For nested structures, `lib/data/dataprocessor` may convert
`json → xml` when `jq`/`xmllint` are present; the renderer here never requires
them.
