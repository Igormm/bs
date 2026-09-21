[↑ Documentation index](../README.md)

# Module `ts::toolchain`

Detection and validation gates for the TypeScript dev toolchain: runtimes
(node/bun/deno), package managers (lockfile-aware), `tsconfig`/`node_modules`
inspection, a `tsc`/`eslint`/`prettier` gate with machine-readable output,
environment doctor and port checks. Pure probing — nothing is assumed,
everything degrades with defined `LIB_ERROR_*` codes.

Source: [lib/ts/toolchain.sh](../../../lib/ts/toolchain.sh)

## Loading

```bash
#!/usr/bin/env bs

load "lib/ts/toolchain"
```

## Test hooks

| Variable | Default | Purpose |
|---|---|---|
| `TS_RUNTIMES` | `node bun deno` | runtime probe order |
| `TS_PACKAGE_MANAGERS` | `npm pnpm yarn bun` | package-manager probe order |

## Runtimes & package managers

```bash
ts::toolchain::detect_runtime          # first available: "node"
ts::toolchain::runtime_version node    # "22.1.2" (v prefix stripped)
ts::toolchain::runtimes                # "bin<TAB>version<TAB>path" lines
ts::toolchain::package_managers        # same shape
ts::toolchain::lockfile_pm ./proj      # pnpm|yarn|bun|npm from lockfile
```

## Project layout

```bash
ts::toolchain::has_tsconfig ./proj     # 0/1 predicate
ts::toolchain::has_node_modules ./proj # 0/1 predicate
ts::toolchain::tsc_bin ./proj          # node_modules/.bin/tsc, then global
ts::toolchain::pkg_field ./proj version  # package.json field (jq, grep fallback)
```

## Validation gate

```bash
ts::toolchain::validate ./proj
# tsc	PASS
# eslint	SKIP	no config or binary
# prettier	FAIL	"src/a.ts" is not Prettier-formatted
```

`name<TAB>status<TAB>hint` lines; exit `E_SUCCESS` when nothing `FAIL`s.
Tools that are not installed are `SKIP`, not errors — the gate is honest
about what it actually checked.

## Doctor & ports

```bash
ts::toolchain::doctor ./proj   # runtime, pm, tsconfig, scripts, tools summary
ts::toolchain::port_free 5173  # 0 free / E_ERROR occupied (ss→netstat→/dev/tcp)
```

## Related

- `.agents/guides/ts-development.md` — how BS wraps a local TS front/back-end stack.
- `lib/integration/http.sh` + `lib/data/dataprocessor.sh` — API smoke tests.
