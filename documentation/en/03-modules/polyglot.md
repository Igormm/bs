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
`--no-cache`. Without `--out`/`--lines`/`--map` the program's stdout is printed.

## Cache and hooks

Compiled programs are cached in `POLYGLOT_CACHE_DIR`
(`~/.cache/bs/polyglot`) by the hash of language, compiler identity (path and
version), flags and source; the first run compiles, later runs start at once.
The probe order is set with `POLYGLOT_C_TOOLS`, `POLYGLOT_CPP_TOOLS`,
`POLYGLOT_GO_TOOLS`, `POLYGLOT_RUST_TOOLS`, `POLYGLOT_PYTHON_TOOLS` and
`POLYGLOT_JS_TOOLS`.

See also: [math](../../../lib/math/math.sh) — the C-backed evaluator this module
generalises.
