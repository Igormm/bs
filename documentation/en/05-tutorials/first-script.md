# Tutorial: your first script

[↑ Documentation index](../README.md)

Goal: starting from an empty file, build a small CLI utility `deploy-lite.sh` with:

- declared and validated arguments ([core/args.sh](../../../core/args.sh));
- colored log output (the logger is loaded automatically by the `bs` entry point);
- formatted status output ([lib/io/streams.sh](../../../lib/io/streams.sh));
- error handling with exit codes.

All commands below are run from the repository root via `./bs run`. Every output block in this tutorial was produced by actually running the script.

## Step 1: Minimal script

Create `deploy-lite.sh`:

```bash
#!/usr/bin/env bs
log::info "Hello from BS"
```

The shebang `#!/usr/bin/env bs` makes the script run inside the BS environment when executed directly (requires `bs` in `PATH`). From the repository root you can always run it without installation:

```bash
./bs run deploy-lite.sh
```

Output:

```text
[2026-07-29 22:27:23] INFO  Hello from BS
```

The logger is part of the core and is already loaded — no `load` call is needed for `log::info`, `log::warn`, `log::error`, `log::success`. In a terminal the level names are colored; in a pipe the output is plain text.

## Step 2: Declare the parameters

Load the `core/args` module and declare what the utility accepts: two positional commands on level 1 and two flags.

```bash
#!/usr/bin/env bs

load "core/args"

main() {
    args::level 1 deploy status
    args::flag env value
    args::flag dry-run

    args::describe deploy "Deploy the application"
    args::describe status "Show environment status"
    args::flag_describe env "Target environment: staging or production (default: staging)"
    args::flag_describe dry-run "Print the plan without executing"
}

main "$@"
```

- `args::level 1 deploy status` — level 1 accepts `deploy` **or** `status` (tree branching).
- `args::flag env value` — a flag that requires a value (`--env production` or `--env=production`).
- `args::flag dry-run` — a boolean flag without a value.
- Flags do not occupy positional levels: `deploy --dry-run` and `--dry-run deploy` are equivalent.
- `args::describe` / `args::flag_describe` fill the help text. Validation and help share the same data source, so they can never diverge.

The script still prints nothing new — the tree is declared but not used yet.

## Step 3: Validation and automatic help

Add `args::require` after the declarations:

```bash
    args::require "$@"
```

- On any invalid input `args::parse` prints the reason and the help to stderr itself and returns `E_INVALID` — `args::require` then exits with that code via `bs::exit`, which runs the cleanup stack.
- `-h`/`--help` prints the help and `args::require` exits 0 — no extra line needed.
- `E_SUCCESS`, `E_ERROR`, `E_INVALID` (0/1/2) are constants from [core/const.sh](../../../core/const.sh), loaded by the BS entry point.

Run:

```bash
./bs run deploy-lite.sh --help
```

Output:

```text
Usage: bash [flags] [deploy|status]

Parameters / Параметры:
  level 1: deploy | status
    deploy           — Deploy the application
    status           — Show environment status

Flags / Флаги:
    --dry-run              — Print the plan without executing
    --env <value>          — Target environment: staging or production (default: staging)
    --help                 — Show this help and exit
```

Note: `args::help` defaults to the `$0` basename, and under `bs run` `$0` is `bash`. To print a fixed program name, call `args::help "deploy-lite.sh"` explicitly (see [examples/argsparseexample.sh](../../../examples/argsparseexample.sh)).

## Step 4: Validated values and error handling

After `args::parse` succeeds, positionals are in the `ARGS_PARAMS` array and flag values are read with `args::flag_get`:

```bash
    local action="${ARGS_PARAMS[0]:-status}"
    local env
    env="$(args::flag_get env || printf 'staging')"

    case "${env}" in
        staging|production) ;;
        *)
            log::error "Unknown environment: ${env} (expected staging or production)"
            bs::exit error
            ;;
    esac

    if args::flag_get dry-run >/dev/null; then
        log::warn "DRY RUN: no changes will be made"
    fi
```

- `args::flag_get` prints the flag value and returns 1 if the flag was not given, so `|| printf 'staging'` supplies the default.
- The argument layer validates *syntax* (unknown names, wrong levels). *Semantic* checks like "only staging/production exist" stay in the script: report them with `log::error` and exit with `E_ERROR`.
- `log::error` writes to stderr, so error output does not pollute stdout pipelines.

Run:

```bash
./bs run deploy-lite.sh deploy --env production --dry-run
```

Output:

```text
[2026-07-29 22:26:59] WARN  DRY RUN: no changes will be made
[2026-07-29 22:26:59] INFO  Deploying to production...
  artifacts  resolved
  release    applied
  health     green
[2026-07-29 22:26:59] SUCCESS Deploy to production finished
```

And a semantic error:

```bash
./bs run deploy-lite.sh deploy --env mars
```

Output (stderr) and exit code:

```text
[2026-07-29 22:26:59] ERROR Unknown environment: mars (expected staging or production)
```

```text
exit=1
```

## Step 5: Formatted output with io::streams

For machine-readable status lines use `io::streams::printf` — the format string is a separate argument, so data never lands in the format string:

```bash
#!/usr/bin/env bs

load "core/args"
load "lib/io/streams"

# ... inside main(), the status branch:
        status)
            io::streams::printf '  %-11s %s\n' "environment" "${env}" "release" "v1.0.0" "health" "green"
            ;;
```

Run:

```bash
./bs run deploy-lite.sh status
```

Output:

```text
  environment staging
  release     v1.0.0
  health      green
```

`io::streams` also provides `io::streams::print` (safe `echo` replacement), `io::streams::eprint` (stderr) and redirection helpers (`redirect_all`, `save`/`restore`) — see [lib/io/streams.sh](../../../lib/io/streams.sh) and [examples/deploytoolexample.sh](../../../examples/deploytoolexample.sh).

## Final script

```bash
#!/usr/bin/env bs
# deploy-lite.sh — tiny deploy CLI: args + colored output + error handling

load "core/args"
load "lib/io/streams"

main() {
    # 1. Declare the parameter tree and flags
    args::level 1 deploy status
    args::flag env value
    args::flag dry-run

    args::describe deploy "Deploy the application"
    args::describe status "Show environment status"
    args::flag_describe env "Target environment: staging or production (default: staging)"
    args::flag_describe dry-run "Print the plan without executing"

    # 2. Validate input; on error parse prints the reason and help itself
    args::require "$@"

    # 3. Work with validated values
    local action="${ARGS_PARAMS[0]:-status}"
    local env
    env="$(args::flag_get env || printf 'staging')"

    # Runtime validation: only two environments exist
    case "${env}" in
        staging|production) ;;
        *)
            log::error "Unknown environment: ${env} (expected staging or production)"
            bs::exit error
            ;;
    esac

    if args::flag_get dry-run >/dev/null; then
        log::warn "DRY RUN: no changes will be made"
    fi

    case "${action}" in
        deploy)
            log::info "Deploying to ${env}..."
            io::streams::printf '  %-10s %s\n' "artifacts" "resolved" "release" "applied" "health" "green"
            log::success "Deploy to ${env} finished"
            ;;
        status)
            io::streams::printf '  %-11s %s\n' "environment" "${env}" "release" "v1.0.0" "health" "green"
            ;;
    esac
}

main "$@"
```

Try the validation error path:

```bash
./bs run deploy-lite.sh fly
```

Output (stderr) and exit code:

```text
ERROR: unknown parameter: "fly"
Usage: bash [flags] [deploy|status]

Parameters / Параметры:
  level 1: deploy | status
    deploy           — Deploy the application
    status           — Show environment status

Flags / Флаги:
    --dry-run              — Print the plan without executing
    --env <value>          — Target environment: staging or production (default: staging)
    --help                 — Show this help and exit
```

```text
exit=2
```

Exit-code contract of the utility: `0` (`E_SUCCESS`) — ok, `1` (`E_ERROR`) — runtime error, `2` (`E_INVALID`) — invalid arguments.

## Notes

- Prefer BS idioms over raw redirections ([core/utils.sh](../../../core/utils.sh)): `utils::has cmd` instead of `command -v cmd >/dev/null 2>&1`, `utils::quiet cmd` instead of `cmd >/dev/null 2>&1`, `utils::quiet_err cmd` instead of `cmd 2>/dev/null`, `utils::ignore cmd` instead of `cmd >/dev/null 2>&1 || true`.
- To run the script as `./deploy-lite.sh`, `bs` must be in `PATH` (shebang mode); otherwise use `bs run`.
- The same parameter tree gives you bash completion for free via `args::completion` — see [examples/argsparseexample.sh](../../../examples/argsparseexample.sh).
- Larger real-world variant of this utility: [examples/deploytoolexample.sh](../../../examples/deploytoolexample.sh).
