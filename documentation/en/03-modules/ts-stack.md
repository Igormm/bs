[↑ Documentation index](../README.md)

# Module `ts::stack`

Local mini TypeScript stack orchestrator. Default name: **thriller**.
BS starts processes and tracks pids/ports; the app stays TypeScript (or a
Python static mock when Node is missing).

Source: [lib/ts/stack.sh](../../../lib/ts/stack.sh)

## CLI

```bash
bs ts init ./app
bs ts up ./app
bs ts status
bs ts logs api
bs ts down
```

Overrides: `TS_STACK_NAME`, `TS_STACK_STATE`, `TS_STACK_API_CMD`,
`TS_STACK_WEB_CMD`, `TS_STACK_API_PORT`, `TS_STACK_WEB_PORT`.

Without Node: `init` writes `fixtures/` and `up` serves them with
`python3 -m http.server` if present. With `tsx`/`node`, `apps/api/index.ts`
is the API.

## Related

- [ts-toolchain.md](ts-toolchain.md) — doctor, validate, port_free
- `.agents/guides/ts-development.md` — role split (BS = ops, TS = app)
