[↑ Documentation index](../README.md)

# args module (`core/args.sh`)

A declarative script parameter tree: declare the allowed parameters once and
get validation, error messages, an auto-generated help and bash completion
from a single source of truth.

## Loading

```bash
#!/usr/bin/env bs
load "core/args"
```

Or manually, when not running under the `bs` interpreter:

```bash
source bootstrap/init.sh
load "core/args"
```

## Linear chain: `args::define`

The simplest case — one parameter per level. Name N occupies level N:

```bash
args::define first middle last
args::parse "$@" || bs::exit "${E_INVALID}"
```

## Tree branching: `args::level`

One level may hold several alternatives. Levels are 1-based:

```bash
args::level 1 deploy rollback status
args::level 2 now later
```

`args::define a b c` is a shorthand for three `args::level` calls.

## Descriptions: `args::describe`

Descriptions are used by `args::help`:

```bash
args::describe deploy "Deploy the application to servers"
args::describe now "Execute immediately"
```

## Flags: `args::flag`, `args::flag_describe`, `args::flag_get`

Flags (`--name`) do not occupy positional tree levels. Two types:

- `bool` (default) — takes no value: `--dry-run`
- `value` — requires a value: `--env production` or `--env=production`

```bash
args::flag dry-run                  # bool flag
args::flag env value                # value flag
args::flag_describe env "Target environment (staging, production)"

# After args::parse — value with a default:
env="$(args::flag_get env || printf 'staging')"

# Checking a bool flag:
if args::flag_get dry-run >/dev/null; then
    log::warn "DRY RUN"
fi
```

`args::flag_get` prints the value and returns 0 if the flag was set;
otherwise it prints nothing and returns `E_ERROR` (1).

With `core/utils` loaded, the last check can be written with the silence
idiom instead of a raw redirect:

```bash
if utils::quiet args::flag_get dry-run; then ...; fi
```

## Validation: `args::parse`, `args::get`

```bash
args::parse "$@" || bs::exit "${E_INVALID}"
action="$(args::get 1)"
```

On success `args::parse` fills the `ARGS_PARAMS` array (positional
parameters, 0-based) and the `ARGS_FLAGS` associative array, and returns 0.
On failure it prints the reason and the help to stderr and returns
`E_INVALID` (2):

- `ERROR: unknown parameter: "fly"`
- `ERROR: parameter "now" belongs to level 2, but was used at level 1`
- `ERROR: too many parameters: "x" is beyond level 2`
- `ERROR: unknown flag: "--bogus"`
- `ERROR: flag "--env" requires a value`

`-h` / `--help` prints the help to stdout, returns 0 and sets
`ARGS_HELP_REQUESTED=1`:

```bash
if ! args::parse "$@"; then
    bs::exit "${E_INVALID}"
fi
if [[ "${ARGS_HELP_REQUESTED}" == "1" ]]; then
    bs::exit "${E_SUCCESS}"
fi
```

`args::get N` prints the validated positional parameter at the 1-based
position N, or returns `E_ERROR` (1) if that position was not given.

## Help: `args::help`

Prints a help generated from the same tree that drives validation — the two
never diverge:

```bash
args::help                # program name defaults to the $0 basename
args::help "deploy.sh"    # explicit program name
```

The output contains a usage line (`Usage: deploy.sh [flags] [deploy|rollback|status] [now|later]`),
the parameters per level with their descriptions, and the flags section.

## Bash completion: `args::completion`

Generates a ready-to-use bash completion function from the same tree and
flags:

```bash
args::completion "deploy.sh" > /etc/bash_completion.d/deploy.sh
source <(args::completion "deploy.sh")
```

Completion knows the per-level choices and the declared flags; values of
`value` flags are not completed.

## Reset: `args::reset`

Clears the tree, descriptions, flags and the parsed state — needed before
re-declaring parameters in the same process:

```bash
args::reset
args::define first middle last
```

## API reference

| Function | Purpose |
|---|---|
| `args::define a b c` | linear chain, levels 1..N |
| `args::level N a b ...` | allowed alternatives at level N (1-based) |
| `args::describe name "text"` | parameter description for the help |
| `args::flag name [bool\|value]` | declare a flag (`bool` is the default) |
| `args::flag_describe name "text"` | flag description for the help |
| `args::flag_get name` | flag value after `args::parse`; 1 if not set |
| `args::parse "$@"` | validate input parameters against the tree |
| `args::get N` | validated positional parameter N (1-based) |
| `args::help [prog]` | generated help |
| `args::completion [prog]` | generate a bash completion function |
| `args::reset` | reset the tree, flags and parsed state |

### State variables

| Variable | Contents |
|---|---|
| `ARGS_PARAMS` | array of validated positional parameters (0-based) |
| `ARGS_FLAGS` | associative array of validated flags (`"1"` for bool) |
| `ARGS_HELP_REQUESTED` | `1` if `-h`/`--help` was passed |
| `ARGS_VERSION` | module version |

## Complete example

See [examples/argsparseexample.sh](../../../examples/argsparseexample.sh):

```bash
#!/usr/bin/env bs
load "core/args"

args::level 1 deploy rollback status
args::level 2 now later
args::describe deploy "Deploy the application to servers"
args::flag env value
args::flag dry-run
args::flag_describe env "Target environment (staging, production)"

if ! args::parse "$@"; then
    bs::exit "${E_INVALID}"
fi
[[ "${ARGS_HELP_REQUESTED}" == "1" ]] && bs::exit "${E_SUCCESS}"

action="${ARGS_PARAMS[0]:-status}"
env="$(args::flag_get env || printf 'staging')"
log::info "Action: ${action}, env: ${env}"
```

Run it:

```bash
bs run examples/argsparseexample.sh deploy now --env production --dry-run
bs run examples/argsparseexample.sh --help
```
