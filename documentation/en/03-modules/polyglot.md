[↑ Documentation index](../README.md)

# Module `polyglot`

Run code written in **C, C++, Go, Rust, Python or JavaScript** inside a bs script:
pass arguments **in**, take the result **back** into variables and keep working
with it.

Source: [lib/polyglot/run.sh](../../../lib/polyglot/run.sh)

## Loading

```bash
#!/usr/bin/env bs

load "lib/polyglot/run"
```

## The contract

| Direction | How |
|---|---|
| script → program | arguments after `--` (argv), `--env NAME=VALUE`, `--input TEXT` (stdin) |
| program → script | stdout into `--out VAR` (scalar), `--lines VAR` (indexed array) or `--map VAR` (associative array, `key=value` lines); the exit code into `--rc VAR` or the return status |
| source | the heredoc on stdin |

Values are never pasted into the source, so a script variable cannot inject
code. The source runs with your privileges: feed only code you trust.

## Examples

```bash
#!/usr/bin/env bs

load "lib/polyglot/run"

# A number goes in, the answer comes back into a variable
polyglot::run python --out answer -- 21 <<'PY'
import sys
print(int(sys.argv[1]) * 2)
PY
echo "${answer}"

# Several lines come back as an array
polyglot::run js --lines words -- a b c <<'JS'
for (const w of process.argv.slice(2)) console.log(w.toUpperCase());
JS
echo "${#words[@]} words"

# key=value lines come back as an associative array
declare -A cfg
polyglot::run c --map cfg --env NAME=bs <<'C'
#include <stdio.h>
#include <stdlib.h>
int main(void) { printf("name=%s\nlen=2\n", getenv("NAME")); return 0; }
C
echo "${cfg[name]} ${cfg[len]}"

# The exit code does not stop the script when --rc is given
polyglot::run python --rc code --out msg <<'PY'
import sys
print("bye")
sys.exit(3)
PY
echo "${code} ${msg}"
```

## Languages

| Language | Aliases | Tool probed (first found) | How it runs |
|---|---|---|---|
| `c` | — | `cc gcc clang` | compiled, cached |
| `cpp` | `c++`, `cxx`, `cc` | `c++ g++ clang++` | compiled, cached |
| `go` | `golang` | `go` | `go build`, cached |
| `rust` | `rs` | `rustc` | compiled, cached |
| `python` | `py`, `python3` | `python3 python` | interpreted |
| `js` | `javascript`, `node` | `node bun` | interpreted |

`polyglot::languages` prints the table with the tool found on this machine
(`-` when absent). A missing tool returns `LIB_ERROR_DEPENDENCY_MISSING`, a
failed compilation `LIB_ERROR_DEPENDENCY` with the compiler output in the log.

## Options

`--out VAR`, `--lines VAR`, `--map VAR` (declare it with `declare -A` first),
`--rc VAR`, `--env NAME=VALUE` (repeatable), `--input TEXT`, `--timeout SEC`
(`LIB_ERROR_TIMEOUT` when it fires), `--flags "…"` (extra compiler flags),
`--no-cache`, `--dep SPEC`. Without `--out`/`--lines`/`--map` the program's stdout is printed.

## Dependencies (`--dep`)

`--dep SPEC` (repeatable) installs a dependency before the code runs. **The
package manager is checked first — before anything is built, installed or
executed** — and a missing one returns `LIB_ERROR_DEPENDENCY_MISSING` with the
reason and an install hint; the code is not run.

| Language | `--dep` means | Manager checked | Where it is installed |
|---|---|---|---|
| `python` | a pip requirement (`requests==2.32.0`, a wheel path) | `pip` and `venv` of the interpreter | a venv in the cache |
| `js` | an npm package (`left-pad@1.3.0`, a folder) | `npm` | `node_modules` in the cache (`NODE_PATH`) |
| `go` | a module (`example.com/m@v1.2.0`) | `go` modules | a module directory in the cache |
| `rust` | a crate (`serde@1`) | `cargo` | a cargo project in the cache |
| `c`, `cpp` | a pkg-config library (`zlib`) | `pkg-config`, and the library itself | flags go to the compiler |

Dependencies never touch the global environment: each combination gets its own
cached environment (hash of language, tool and dependencies). Installing needs
the network (except local paths and pkg-config). A spec starting with `-` or
holding spaces or shell characters is refused (`LIB_ERROR_INVALID_ARGS`).
`polyglot::doctor` shows which languages and managers are present.

```bash
#!/usr/bin/env bs

load "lib/polyglot/run"

polyglot::doctor

polyglot::run python --dep requests --out status <<'PY'
import requests
print(requests.__version__)
PY
```

## Cache and hooks

Compiled programs are cached in `POLYGLOT_CACHE_DIR`
(`~/.cache/bs/polyglot`) by the hash of language, compiler identity (path and
version), flags and source; the first run compiles, later runs start at once.
The probe order is set with `POLYGLOT_C_TOOLS`, `POLYGLOT_CPP_TOOLS`,
`POLYGLOT_GO_TOOLS`, `POLYGLOT_RUST_TOOLS`, `POLYGLOT_PYTHON_TOOLS` and
`POLYGLOT_JS_TOOLS`; for dependencies `POLYGLOT_NPM_TOOLS`, `POLYGLOT_CARGO_TOOLS`, `POLYGLOT_PKGCONFIG_TOOLS`.

See also: [math](../../../lib/math/math.sh) — the C-backed evaluator this module
generalises.
