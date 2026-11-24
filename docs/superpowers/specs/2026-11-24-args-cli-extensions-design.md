# args: Docker/Podman-style flag extensions

Date: 2026-11-24  
Status: approved design  
Tier: `core/args.sh` remains `@shell posix`; the bash bridge remains `@shell bash4`.

## Goal

Extend the declarative argument parser with short aliases, grouped short flags,
repeatable value flags and explicit boolean values while preserving the existing
four-argument `args::flag` API and POSIX behaviour in dash, ash, ksh, mksh, zsh
and bash.

Success means that declarations remain the single source of truth for parsing,
validation, help and completion; old scripts keep working; values with spaces,
newlines, glob characters and literal shell substitutions retain their argument
boundaries.

## Approved public API

Existing API is unchanged:

```sh
args::flag NAME [bool|value] [DEFAULT] [VALIDATOR]
```

New declarations, made after `args::flag`:

```sh
args::flag_short NAME SHORT
args::flag_repeat NAME
args::flag_bool_value NAME
```

New readers:

```sh
args::flag_get_all NAME
args::flag_values NAME ARRAY_NAME
```

### Declaration rules

- `SHORT` is exactly one ASCII letter or digit.
- A short alias is unique across all declared flags.
- `h` remains the built-in help alias unless a flag explicitly declares it.
- `args::flag_short`, `args::flag_repeat` and `args::flag_bool_value` reject an
  unknown flag name with `E_INVALID`.
- `repeat` is valid only for a `value` flag.
- `bool-value` is valid only for a `bool` flag.
- Repeating the same property declaration is idempotent.
- Changing a property to an incompatible value is rejected.

### Reader semantics

- `args::flag_get NAME [FALLBACK]` keeps its current contract. For a repeatable
  flag it returns the first CLI value, then the declared default, then the
  fallback.
- `ARGS_FLAGS[NAME]` in the bash bridge also contains the first CLI value.
- `args::flag_get_all NAME` prints only CLI values, one per line, in input order.
  It works for non-repeatable flags as a one-element list. With no CLI values it
  prints nothing and returns success.
- `args::flag_values NAME ARRAY_NAME` copies only CLI values into a caller-named
  bash array without losing argument boundaries. With no CLI values it returns
  success and leaves the array empty.
- `args::flag_is_set NAME` reports whether the flag appeared, including
  `--flag=false` and an explicitly empty value.

Line-oriented `flag_get_all` cannot unambiguously represent embedded newlines;
`flag_values` is the lossless bash API.

## Internal representation

`core/args.sh` gains these data-layer maps:

- `bs_args_flag_short`: long name to short alias;
- `bs_args_short_flag`: short alias to long name;
- `bs_args_flag_repeat`: long name to `1`;
- `bs_args_flag_bool_value`: long name to `1`.

Repeat occurrences use two parallel data-layer arrays:

- `bs_args_repeat_names`: canonical long name for each occurrence;
- `bs_args_repeat_values`: value for that occurrence.

This avoids dynamic variable names and preserves empty values, spaces and
newlines. Lookup is a linear filtered walk; flag counts are small and the
implementation stays portable.

`bs_args_parsed` stores the first value of a repeatable flag. Every occurrence is
validated independently before being appended to the repeat arrays.

`bs_args_reset` and `bs_args_parse` clear the new maps/arrays together with the
existing state.

## Grammar

### Long flags

Existing forms remain:

```text
--flag
--value next
--value=next
```

For a flag declared with `args::flag_bool_value`:

| Form | Stored value |
|---|---|
| `--flag` | `1` |
| `--flag=true` | `1` |
| `--flag=false` | `0` |

Other inline values are rejected. A separate token after a bool flag is not
consumed as its value.

### Short flags

For a value flag with alias `p`:

```text
-p next
-p=next
-pnext
```

For boolean flags with aliases `a`, `b` and value alias `p`:

```text
-abc
-abp next
-abp=next
-abpnext
```

Rules:

- a cluster is scanned left to right;
- boolean flags consume only their own character;
- a value flag consumes the remainder of the cluster, or the next argument when
  the cluster ends;
- `=` immediately after a short value flag is stripped;
- a bool-value flag may use `=true` or `=false` as the final cluster item;
- an unknown short alias is rejected with `E_INVALID`;
- `-h` inside a cluster requests help when `h` is not declared.

### Backward-compatible positional dash arguments

Before this change, a token such as `-foo` could be a positional parameter.
Short parsing therefore activates only when:

1. the first character is a declared short alias; or
2. the first character is undeclared `h`, which requests help.

If a token begins with `-` but does not activate short parsing, it is offered to
the positional tree exactly as before. If short aliases exist, no positional
match exists, and the token is not a known positional form, the error names an
unknown short flag.

`--` always terminates option parsing.

## Help and completion

Help labels show both forms, for example:

```text
-p, --port <number>
-v, --verbose
    --color[=true|false]
```

Completion offers both short and long forms. Value flags still suppress free
value completion unless they declare an enum. Grouped-cluster completion is not
required; offering individual short flags is sufficient.

The help-request pre-scan must understand short aliases and clusters, skip values
of value flags, stop at `--`, and preserve the priority of a declared `help` or
`h` flag.

## Bash bridge

`lib/compat/args.sh` gains:

```bash
args::flag_get_all() {
    bs_args_flag_get_all "$@"
}

args::flag_values() {
    local name="${1:-}" array_name="${2:-}"
    # Validate the array name before eval.
    # Clear the caller's array, then append values from the parallel arrays.
}
```

The bridge validates `ARRAY_NAME` as a shell identifier before using `eval`.
It does not use namerefs. Existing `ARGS_PARAMS`, `ARGS_FLAGS` and `ARGS_REST`
remain unchanged.

No `ARGS_FLAGS_REPEAT` global is introduced in this version.

## Errors

All new declaration and parse failures return `E_INVALID` (`2`) and use the
existing diagnostic-plus-help path. Covered cases include:

- invalid or duplicate short alias;
- unknown flag in a property declaration;
- `repeat` on a bool flag;
- `bool-value` on a value flag;
- missing short value;
- invalid bool-value spelling;
- unknown short alias;
- invalid value on any repeat occurrence.

A failed parse may leave partial parsed state, matching current behaviour.

## Testing strategy

### Portable kernel tests

Extend `tests/unit/testargsportableunit.sh` to run in every installed POSIX shell:

- all short forms and mixed clusters;
- bool-value true, false, bare and invalid forms;
- repeat ordering, empty values and per-occurrence validation;
- `flag_get`, `flag_get_all`, `flag_is_set` and reset semantics;
- legacy positional `-foo`;
- help detection in clusters and after value flags;
- strict-mode probes;
- values containing spaces, newlines, globs and literal `$()`.

### Bash unit and bridge tests

Extend `tests/unit/testargsunit.sh`:

- `ARGS_FLAGS` contains the first repeat value;
- `args::flag_values` preserves exact argument boundaries;
- invalid caller array names are rejected;
- old four-argument declarations still parse identically.

### Completion tests

Add focused assertions to `tests/unit/testargs-completionportableunit.sh` for
short aliases and bool-value labels. Keep existing checksum fixtures unchanged
by adding a separate declaration set rather than modifying the old fixture.

### Documentation and example

Update both `documentation/{en,ru}/03-modules/args.md`, the complete example and
`examples/argsparseexample.sh`. The mandatory validation cycle and version check
run after implementation.

## Out of scope

- automatic `--no-flag` negation;
- `ARGS_FLAGS_REPEAT` as a public global;
- grouped short-option completion;
- a separate flag-parser module or argv preprocessor;
- changes to positional-tree semantics beyond preserving dash-prefixed names;
- fail-fast or mutually-exclusive flag groups;
- release code-name selection, which is handled during the version bump.

## Risks and mitigations

- **POSIX portability:** no arrays in shell syntax, no namerefs, no `[[` or
  shell-specific tests in `core/args.sh`; state stays in `core/data.sh`.
- **Backward compatibility:** short parsing activates only for declared aliases
  or help; existing long-flag and positional behaviour is covered by the old
  portable suite.
- **Argument splitting:** repeat storage and the bash bridge use the data-layer
  array primitives and quoted expansion only.
- **Help drift:** help and completion read the same property maps as validation.
- **Parser growth:** new logic is split into small private helpers rather than
  enlarging the main parse loop.
