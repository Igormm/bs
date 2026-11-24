# args CLI Extensions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add short aliases, grouped short flags, repeatable value flags and explicit boolean values to `core/args` without breaking existing declarations or POSIX portability.

**Architecture:** Extend the current POSIX parser in place. New declaration metadata and repeat occurrences live in `core/data.sh` maps/arrays; parsing, help and completion read the same metadata. The bash bridge copies repeat values into caller-named arrays without namerefs.

**Tech Stack:** POSIX shell, BS core/data primitives, Bash 4.2+ compatibility bridge, custom BS test framework, dash/ash/ksh/mksh/zsh/bash portable tests.

**Spec:** `docs/superpowers/specs/2026-11-24-args-cli-extensions-design.md`

## Global Constraints

- `core/args.sh` and `core/args-completion.sh` remain `@shell posix`.
- Supported shells: bash 4.2+, zsh, dash, busybox ash, ksh93, mksh.
- No `local -n`, `printf -v`, `mapfile`, `wait -n`, `${!array[@]}`, `[[ =~ ]]` or other shell-specific syntax in `core/`.
- Existing `args::flag NAME [bool|value] [DEFAULT] [VALIDATOR]` calls and output remain compatible.
- Exactly one `--` separator terminates option parsing.
- Public functions keep stdout clean except documented value/help emitters.
- Every new public function gets a bilingual DocBlock and portable tests.
- Run syntax, ShellCheck, portable/unit tests, docs snippets and version check before release.

## Review Focus

- A legacy positional named `-foo` must still parse when short aliases are declared for other flags; Task 4 pins activation only for known aliases/help.
- Repeat values containing spaces, newlines, globs and literal `$()` must survive `args::flag_values` unchanged; Task 6 pins the bash bridge with exact array elements.
- A short value flag must consume only its remainder or one next argument, never `--`; Task 4 tests `-p=value`, `-pvalue`, `-p value`, groups and missing values.
- `-h` must mean help in a group, but remain a normal value after `-p` and after `--`; Task 5 tests all three positions.
- `--flag=false` must store `0` while `args::flag_is_set` remains true; help must advertise the bool-value form and completion must offer its short alias; Tasks 3 and 7 pin both behaviour and metadata.

---

## File Structure

- `core/args.sh` — declaration metadata, repeat storage/readers, bool-value parsing, short-cluster parsing, help scanning and labels.
- `core/args-completion.sh` — emit short aliases and bool-value forms for bash, zsh, fish and nushell.
- `lib/compat/args.sh` — bash aliases and lossless `args::flag_values`.
- `tests/unit/testargsportableunit.sh` — six-shell declaration, parsing, repeat, bool-value, short-cluster and help behaviour.
- `tests/unit/testargsunit.sh` — bash bridge arrays, aliases and compatibility.
- `tests/unit/testargs-completionportableunit.sh` — short/bool-value completion text.
- `examples/argsparseexample.sh` — runnable demonstration of the new API.
- `documentation/{en,ru}/03-modules/args.md` — user documentation and API tables.
- `.agents/skills/bs-cli-flags-style/SKILL.md` — move the implemented items out of the roadmap.
- `core/version.sh`, `CHANGELOG.md`, version fixtures and repeated docs version strings — release `0.27.0 "ключи"`.

---

### Task 1: Flag property declarations and metadata

**Files:**
- Modify: `core/args.sh`
- Test: `tests/unit/testargsportableunit.sh`
- Test: `tests/unit/testargsunit.sh`

**Interfaces:**
- Consumes: `bs_args_flag`, `bs_map_*`, `bs_arr_*`, `E_INVALID`.
- Produces: `bs_args_flag_short`, `bs_args_flag_repeat`, `bs_args_flag_bool_value`; maps `bs_args_flag_short`, `bs_args_short_flag`, `bs_args_flag_repeat`, `bs_args_flag_bool_value`; aliases `args::flag_short`, `args::flag_repeat`, `args::flag_bool_value`.

- [ ] **Step 1: Write failing portable declaration tests**

Append to `test_behaviour` in `tests/unit/testargsportableunit.sh` inside the existing shell loop:

```sh
eq "$(probe "${sh_bin}" '
bs_args_flag port value 80 number
bs_args_flag verbose
bs_args_flag color bool
bs_args_flag_short port p; printf "short=%s " "$?"
bs_args_flag_short verbose v; printf "shortv=%s " "$?"
bs_args_flag_repeat port; printf "repeat=%s " "$?"
bs_args_flag_bool_value color; printf "boolv=%s " "$?"
bs_args_flag_repeat verbose >/dev/null 2>&1; printf "repeatbool=%s " "$?"
bs_args_flag_bool_value port >/dev/null 2>&1; printf "boolvalue=%s " "$?"
bs_args_flag_short verbose p >/dev/null 2>&1; printf "dup=%s " "$?"
bs_args_flag_short missing m >/dev/null 2>&1; printf "unknown=%s " "$?"
printf "map=%s,%s repeat=%s boolv=%s\n" \
  "$(bs_map_get bs_args_flag_short port)" \
  "$(bs_map_get bs_args_short_flag p)" \
  "$(bs_map_get bs_args_flag_repeat port)" \
  "$(bs_map_get bs_args_flag_bool_value color)"
')" \
"short=0 shortv=0 repeat=0 boolv=0 repeatbool=2 boolvalue=2 dup=2 unknown=2 map=p,p repeat=1 boolv=1" \
"${sh_name}: flag property declarations"
```

Append to `testargsunit.sh` after the existing flag tests:

```bash
args::reset
args::flag port value 80 number
args::flag_short port p
args::flag_repeat port
args::flag color bool
args::flag_bool_value color
testframework::assert_equal "p" "$(bs_map_get bs_args_flag_short port)" "short alias stored"
testframework::assert_equal "port" "$(bs_map_get bs_args_short_flag p)" "reverse short alias stored"
testframework::assert_true "bs_map_has bs_args_flag_repeat port" "repeat property stored"
testframework::assert_true "bs_map_has bs_args_flag_bool_value color" "bool-value property stored"
```

- [ ] **Step 2: Run tests and verify RED**

Run: `./bs run tests/unit/testargsportableunit.sh`

Expected: FAIL because `bs_args_flag_short` is not defined.

- [ ] **Step 3: Add metadata maps and reset support**

In `bs_args_reset`, add:

```sh
bs_map_clear bs_args_flag_short
bs_map_clear bs_args_short_flag
bs_map_clear bs_args_flag_repeat
bs_map_clear bs_args_flag_bool_value
```

Update the bilingual `# ДАННЫЕ / DATA` header block to list the four new maps. Add the public names to the bilingual `# ИМЕНА / NAMES` block.

Add private helpers and public declarations after `bs_args_flag`:

```sh
# @private
# @description Объявлен ли флаг / Is the flag declared
# @param $1 canonical flag name
bs_args_flag_known() {
  bs_args_mget bs_args_flags "$1" __bs_args_fk_kind
  [ -n "$__bs_args_fk_kind" ]
}

# @description Задать короткий alias флага / Assign a short alias to a flag
# @param $1 canonical flag name  $2 one-letter alias
# @returns E_SUCCESS or E_INVALID
bs_args_flag_short() {
  __bs_args_fsh_name=${1:-}
  __bs_args_fsh_short=${2:-}
  bs_args_flag_known "$__bs_args_fsh_name" || {
    bs_log_warn "args::flag_short: unknown flag: ${__bs_args_fsh_name}"
    return "${E_INVALID:-2}"
  }
  case "$__bs_args_fsh_short" in
    [A-Za-z0-9]) ;;
    *)
      bs_log_warn "args::flag_short: alias must be one ASCII letter or digit: ${__bs_args_fsh_short}"
      return "${E_INVALID:-2}"
      ;;
  esac
  if bs_map_has bs_args_short_flag "$__bs_args_fsh_short"; then
    bs_map_get_to bs_args_short_flag "$__bs_args_fsh_short" __bs_args_fsh_existing
    [ "$__bs_args_fsh_existing" = "$__bs_args_fsh_name" ] && return "${E_SUCCESS:-0}"
    bs_log_warn "args::flag_short: alias already used: -${__bs_args_fsh_short}"
    return "${E_INVALID:-2}"
  fi
  bs_map_set bs_args_flag_short "$__bs_args_fsh_name" "$__bs_args_fsh_short"
  bs_map_set bs_args_short_flag "$__bs_args_fsh_short" "$__bs_args_fsh_name"
  return "${E_SUCCESS:-0}"
}

# @description Разрешить повторение value-флага / Make a value flag repeatable
# @param $1 canonical flag name
# @returns E_SUCCESS or E_INVALID
bs_args_flag_repeat() {
  __bs_args_frp_name=${1:-}
  bs_args_flag_known "$__bs_args_frp_name" || {
    bs_log_warn "args::flag_repeat: unknown flag: ${__bs_args_frp_name}"
    return "${E_INVALID:-2}"
  }
  bs_args_mget bs_args_flags "$__bs_args_frp_name" __bs_args_frp_kind
  [ "$__bs_args_frp_kind" = value ] || {
    bs_log_warn "args::flag_repeat: only value flags may repeat: ${__bs_args_frp_name}"
    return "${E_INVALID:-2}"
  }
  bs_map_set bs_args_flag_repeat "$__bs_args_frp_name" 1
  return "${E_SUCCESS:-0}"
}

# @description Разрешить bool-флагу true/false / Allow explicit true/false for a bool flag
# @param $1 canonical flag name
# @returns E_SUCCESS or E_INVALID
bs_args_flag_bool_value() {
  __bs_args_fbv_name=${1:-}
  bs_args_flag_known "$__bs_args_fbv_name" || {
    bs_log_warn "args::flag_bool_value: unknown flag: ${__bs_args_fbv_name}"
    return "${E_INVALID:-2}"
  }
  bs_args_mget bs_args_flags "$__bs_args_fbv_name" __bs_args_fbv_kind
  [ "$__bs_args_fbv_kind" = bool ] || {
    bs_log_warn "args::flag_bool_value: only bool flags accept true/false: ${__bs_args_fbv_name}"
    return "${E_INVALID:-2}"
  }
  bs_map_set bs_args_flag_bool_value "$__bs_args_fbv_name" 1
  return "${E_SUCCESS:-0}"
}
```

Add aliases next to `args::flag`:

```sh
bs_shell_alias bs_args_flag_short args::flag_short
bs_shell_alias bs_args_flag_repeat args::flag_repeat
bs_shell_alias bs_args_flag_bool_value args::flag_bool_value
```

- [ ] **Step 4: Run tests and verify GREEN**

Run: `./bs run tests/unit/testargsportableunit.sh && ./bs run tests/unit/testargsunit.sh`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add core/args.sh tests/unit/testargsportableunit.sh tests/unit/testargsunit.sh
git commit -m "feat(args): declare short repeat and bool-value flag properties"
```

---

### Task 2: Repeat value storage and long-form parsing

**Files:**
- Modify: `core/args.sh`
- Test: `tests/unit/testargsportableunit.sh`

**Interfaces:**
- Consumes: Task 1 `bs_args_flag_repeat`.
- Produces: `bs_args_store_flag_value`, `bs_args_flag_get_all`; arrays `bs_args_repeat_names`, `bs_args_repeat_values`, scratch `bs_args_selected`; alias `args::flag_get_all`.

- [ ] **Step 1: Write failing repeat tests**

Append inside the portable shell loop:

```sh
eq "$(probe "${sh_bin}" '
bs_args_flag env value
bs_args_flag_repeat env
bs_args_parse --env dev --env=prod --env ""
printf "first=%s set=%s all=" "$(bs_args_flag_get env)" "$(bs_args_flag_is_set env; echo $?)"
bs_args_flag_get_all env | tr "\n" "|"
printf "\n"
bs_args_reset
bs_args_parse --env dev --env bad --env prod >/dev/null 2>&1
printf "rc=%s count=%s\n" "$?" "$(bs_arr_len bs_args_repeat_values)"
')" \
"first=dev set=0 all=dev|prod||
rc=0 count=3" \
"${sh_name}: repeat values keep order and validate every occurrence"
```

Add a validator failure case:

```sh
eq "$(probe "${sh_bin}" '
bs_args_flag n value "" number
bs_args_flag_repeat n
bs_args_parse --n 1 --n bad --n 3 >/dev/null 2>&1
printf "rc=%s\n" "$?"
')" "rc=2" "${sh_name}: invalid repeat occurrence is refused"
```

- [ ] **Step 2: Run tests and verify RED**

Run: `./bs run tests/unit/testargsportableunit.sh`

Expected: FAIL because repeated long flags overwrite and `bs_args_flag_get_all` is missing.

- [ ] **Step 3: Add repeat storage and route value parsing through it**

In `bs_args_reset` and at the start of `bs_args_parse`, add:

```sh
bs_arr_clear bs_args_repeat_names
bs_arr_clear bs_args_repeat_values
bs_arr_clear bs_args_selected
```

Update the bilingual data header to list the repeat arrays and the scratch selection array.

Add helpers before `bs_args_parse_value_flag`:

```sh
# @private
# @description Сохранить значение флага, накапливая повторения / Store a flag value, accumulating repeats
# @param $1 canonical name  $2 value
bs_args_store_flag_value() {
  __bs_args_sfv_name=$1
  __bs_args_sfv_value=$2
  if bs_map_has bs_args_flag_repeat "$__bs_args_sfv_name"; then
    if ! bs_map_has bs_args_parsed "$__bs_args_sfv_name"; then
      bs_map_set bs_args_parsed "$__bs_args_sfv_name" "$__bs_args_sfv_value"
    fi
    bs_arr_push bs_args_repeat_names "$__bs_args_sfv_name"
    bs_arr_push bs_args_repeat_values "$__bs_args_sfv_value"
  else
    bs_map_set bs_args_parsed "$__bs_args_sfv_name" "$__bs_args_sfv_value"
  fi
}

# @description Все CLI-значения флага, по одному на строку / All CLI values of a flag, one per line
# @param $1 canonical flag name
# @returns E_SUCCESS; empty output when the flag was not given
bs_args_flag_get_all() {
  __bs_args_fga_name=${1:-}
  bs_arr_clear bs_args_selected
  if bs_map_has bs_args_flag_repeat "$__bs_args_fga_name"; then
    bs_data_len_of bs_args_repeat_names
    __bs_args_fga_count=$__bs_dat_n
    __bs_args_fga_i=0
    while [ "$__bs_args_fga_i" -lt "$__bs_args_fga_count" ]; do
      bs_data_get_at bs_args_repeat_names "$__bs_args_fga_i"
      if [ "$__bs_dat_cur" = "$__bs_args_fga_name" ]; then
        bs_data_get_at bs_args_repeat_values "$__bs_args_fga_i"
        bs_arr_push bs_args_selected "$__bs_dat_cur"
      fi
      __bs_args_fga_i=$((__bs_args_fga_i + 1))
    done
  elif bs_map_has bs_args_parsed "$__bs_args_fga_name"; then
    bs_map_get_to bs_args_parsed "$__bs_args_fga_name" __bs_args_fga_value
    bs_arr_push bs_args_selected "$__bs_args_fga_value"
  fi
  bs_arr_to_args_to bs_args_selected __bs_args_fga_args
  eval "$__bs_args_fga_args"
  for __bs_args_fga_value in "$@"; do
    printf '%s\n' "$__bs_args_fga_value"
  done
  return "${E_SUCCESS:-0}"
}
```

Replace the body of `bs_args_parse_value_flag` so validation always uses the current occurrence, not the first stored repeat value:

```sh
bs_args_parse_value_flag() {
  if [ "$__bs_args_ps_has_inline" -eq 1 ]; then
    __bs_args_ps_val=$__bs_args_ps_inline
  elif [ $# -eq 0 ]; then
    bs_args_parse_refuse "flag \"--${__bs_args_ps_name}\" requires a value"
    return "${E_INVALID:-2}"
  elif [ "$1" = "--" ]; then
    __bs_args_ps_val=""
  else
    __bs_args_ps_val=$1
    __bs_args_ps_used=1
  fi
  bs_args_store_flag_value "$__bs_args_ps_name" "$__bs_args_ps_val"
  if ! bs_args_validate_flag_value "$__bs_args_ps_name" "$__bs_args_ps_val"; then
    bs_args_parse_refuse "flag \"--${__bs_args_ps_name}\" has an invalid value: \"${__bs_args_ps_val}\" (expected $(bs_args_flag_value_hint "$__bs_args_ps_name"))"
    return "${E_INVALID:-2}"
  fi
  return "${E_SUCCESS:-0}"
}
```

Add the alias:

```sh
bs_shell_alias bs_args_flag_get_all args::flag_get_all
```

- [ ] **Step 4: Run tests and verify GREEN**

Run: `./bs run tests/unit/testargsportableunit.sh && ./bs run tests/unit/testargsunit.sh`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add core/args.sh tests/unit/testargsportableunit.sh
git commit -m "feat(args): accumulate repeatable flag values"
```

---

### Task 3: Explicit boolean values on long flags

**Files:**
- Modify: `core/args.sh`
- Test: `tests/unit/testargsportableunit.sh`

**Interfaces:**
- Consumes: Task 1 `bs_args_flag_bool_value`, Task 2 `bs_args_store_flag_value`.
- Produces: long-form `--flag`, `--flag=true`, `--flag=false` parsing.

- [ ] **Step 1: Write failing bool-value tests**

Append inside the portable shell loop:

```sh
eq "$(probe "${sh_bin}" '
bs_args_flag color bool
bs_args_flag_bool_value color
bs_args_parse --color; printf "bare=%s set=%s " "$(bs_args_flag_get color)" "$(bs_args_flag_is_set color; echo $?)"
bs_args_parse --color=false; printf "false=%s set=%s " "$(bs_args_flag_get color)" "$(bs_args_flag_is_set color; echo $?)"
bs_args_parse --color=true; printf "true=%s " "$(bs_args_flag_get color)"
bs_args_parse --color=yes >/dev/null 2>&1; printf "bad=%s\n" "$?"
')" \
"bare=1 set=0 false=0 set=0 true=1 bad=2" \
"${sh_name}: bool-value long forms"
```

- [ ] **Step 2: Run tests and verify RED**

Run: `./bs run tests/unit/testargsportableunit.sh`

Expected: FAIL because every inline bool value is currently rejected.

- [ ] **Step 3: Implement bool-value parsing**

Replace the bool branch of `bs_args_parse_flag` with:

```sh
if bs_map_has bs_args_flag_bool_value "$__bs_args_ps_name"; then
  if [ "$__bs_args_ps_has_inline" -eq 1 ]; then
    case "$__bs_args_ps_inline" in
      true)  bs_args_store_flag_value "$__bs_args_ps_name" 1 ;;
      false) bs_args_store_flag_value "$__bs_args_ps_name" 0 ;;
      *)
        bs_args_parse_refuse "flag \"--${__bs_args_ps_name}\" accepts only true or false"
        return "${E_INVALID:-2}"
        ;;
    esac
  else
    bs_args_store_flag_value "$__bs_args_ps_name" 1
  fi
else
  if [ "$__bs_args_ps_has_inline" -eq 1 ]; then
    bs_args_parse_refuse "flag \"--${__bs_args_ps_name}\" does not take a value"
    return "${E_INVALID:-2}"
  fi
  bs_args_store_flag_value "$__bs_args_ps_name" 1
fi
return "${E_SUCCESS:-0}"
```

- [ ] **Step 4: Run tests and verify GREEN**

Run: `./bs run tests/unit/testargsportableunit.sh && ./bs run tests/unit/testargsunit.sh`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add core/args.sh tests/unit/testargsportableunit.sh
git commit -m "feat(args): accept explicit true and false for bool flags"
```

---

### Task 4: Short aliases, attached values and clusters

**Files:**
- Modify: `core/args.sh`
- Test: `tests/unit/testargsportableunit.sh`

**Interfaces:**
- Consumes: Task 1 short maps, Task 2 storage helper, Task 3 bool-value map.
- Produces: `bs_args_use_short`, `bs_args_parse_short`; main-loop `-*` dispatch; `__bs_args_ps_used` semantics for one consumed next argument.

- [ ] **Step 1: Write failing short-option tests**

Append inside the portable shell loop:

```sh
eq "$(probe "${sh_bin}" '
bs_args_define deploy
bs_args_flag port value "" number
bs_args_flag_short port p
bs_args_flag verbose
bs_args_flag_short verbose v
bs_args_flag force
bs_args_flag_short force f
bs_args_flag output value
bs_args_flag_short output o
bs_args_flag color bool
bs_args_flag_bool_value color
bs_args_flag_short color c
bs_args_parse deploy -v -p 8080; printf "a=%s,%s,%s " "$(bs_args_flag_get port)" "$(bs_args_flag_get verbose)" "$(bs_args_get 1)"
bs_args_parse -p=8081 -f deploy; printf "b=%s,%s " "$(bs_args_flag_get port)" "$(bs_args_flag_get force)"
bs_args_parse deploy -p8082; printf "c=%s " "$(bs_args_flag_get port)"
bs_args_parse -vfp=8083 deploy; printf "d=%s,%s,%s " "$(bs_args_flag_get verbose)" "$(bs_args_flag_get force)" "$(bs_args_flag_get port)"
bs_args_parse -vo report deploy; printf "e=%s,%s " "$(bs_args_flag_get verbose)" "$(bs_args_flag_get output)"
bs_args_parse -c=false deploy; printf "f=%s,%s " "$(bs_args_flag_get color)" "$(bs_args_flag_is_set color; echo $?)"
bs_args_parse -x deploy >/dev/null 2>&1; printf "x=%s " "$?"
bs_args_parse -p -- deploy >/dev/null 2>&1; printf "missing=%s\n" "$?"
')" \
"a=8080,1,deploy b=8081,1 c=8082 d=1,1,8083 e=1,report f=0,0 x=2 missing=2" \
"${sh_name}: short flags, attached values and clusters"
```

Add the legacy positional case:

```sh
eq "$(probe "${sh_bin}" '
bs_args_define -foo
bs_args_flag port value
bs_args_flag_short port p
bs_args_parse -foo; printf "rc=%s value=%s\n" "$?" "$(bs_args_get 1)"
')" "rc=0 value=-foo" "${sh_name}: legacy dash positional survives short aliases"
```

- [ ] **Step 2: Run tests and verify RED**

Run: `./bs run tests/unit/testargsportableunit.sh`

Expected: FAIL because `-p` is treated as a positional parameter.

- [ ] **Step 3: Implement short-token activation and cluster parsing**

Add before `bs_args_parse`:

```sh
# @private
# @description Должен ли "-..." разбираться как короткие опции / Should a dash token use short-option parsing
# @param $1 token
# @returns 0 short options, 1 positional
bs_args_use_short() {
  __bs_args_us_token=$1
  __bs_args_us_first=${__bs_args_us_token#-}
  __bs_args_us_first=${__bs_args_us_first%"${__bs_args_us_first#?}"}
  if [ -n "$__bs_args_us_first" ] && bs_map_has bs_args_short_flag "$__bs_args_us_first"; then
    return 0
  fi
  if [ "$__bs_args_us_token" = "-h" ]; then
    bs_args_mget bs_args_flags h __bs_args_us_h
    [ -z "$__bs_args_us_h" ] && return 0
  fi
  __bs_args_us_next=$((__bs_args_ps_pos + 1))
  if [ "$__bs_args_us_next" -le "$__bs_args_ps_max" ] && bs_args_is_allowed_at "$__bs_args_us_next" "$__bs_args_us_token"; then
    return 1
  fi
  __bs_args_us_real=$(bs_args_level_of "$__bs_args_us_token")
  [ -z "$__bs_args_us_real" ] || return 1
  [ "$(bs_map_count bs_args_short_flag)" -eq 0 ] && return 1
  return 0
}

# @private
# @description Разобрать короткий flag или cluster / Parse a short flag or cluster
# @param $1 token beginning with -
# @param $@ remaining arguments
# @returns E_SUCCESS or E_INVALID
bs_args_parse_short() {
  __bs_args_pss_token=$1
  shift
  __bs_args_pss_cluster=${__bs_args_pss_token#-}
  __bs_args_ps_used=0

  while [ -n "$__bs_args_pss_cluster" ]; do
    __bs_args_pss_char=${__bs_args_pss_cluster%"${__bs_args_pss_cluster#?}"}
    __bs_args_pss_cluster=${__bs_args_pss_cluster#?}

    if ! bs_map_has bs_args_short_flag "$__bs_args_pss_char"; then
      if [ "$__bs_args_pss_char" = h ]; then
        bs_args_mget bs_args_flags h __bs_args_pss_hkind
        if [ -z "$__bs_args_pss_hkind" ]; then
          ARGS_HELP_REQUESTED=1
          bs_args_help
          return "${E_SUCCESS:-0}"
        fi
      fi
      bs_args_parse_refuse "unknown short flag: \"-${__bs_args_pss_char}\""
      return "${E_INVALID:-2}"
    fi

    bs_map_get_to bs_args_short_flag "$__bs_args_pss_char" __bs_args_pss_name
    bs_args_mget bs_args_flags "$__bs_args_pss_name" __bs_args_pss_kind

    if [ "$__bs_args_pss_kind" = value ]; then
      if [ -n "$__bs_args_pss_cluster" ]; then
        __bs_args_pss_value=${__bs_args_pss_cluster#=}
      elif [ $# -gt 0 ] && [ "$1" != "--" ]; then
        __bs_args_pss_value=$1
        __bs_args_ps_used=1
      else
        bs_args_parse_refuse "flag \"-${__bs_args_pss_char}\" requires a value"
        return "${E_INVALID:-2}"
      fi
      if ! bs_args_validate_flag_value "$__bs_args_pss_name" "$__bs_args_pss_value"; then
        bs_args_parse_refuse "flag \"-${__bs_args_pss_char}\" has an invalid value: \"${__bs_args_pss_value}\" (expected $(bs_args_flag_value_hint "$__bs_args_pss_name"))"
        return "${E_INVALID:-2}"
      fi
      bs_args_store_flag_value "$__bs_args_pss_name" "$__bs_args_pss_value"
      return "${E_SUCCESS:-0}"
    fi

    __bs_args_pss_value=1
    if bs_map_has bs_args_flag_bool_value "$__bs_args_pss_name" && [ -n "$__bs_args_pss_cluster" ]; then
      case "$__bs_args_pss_cluster" in
        =true)  __bs_args_pss_value=1; __bs_args_pss_cluster="" ;;
        =false) __bs_args_pss_value=0; __bs_args_pss_cluster="" ;;
        =*)
          bs_args_parse_refuse "flag \"-${__bs_args_pss_char}\" accepts only true or false"
          return "${E_INVALID:-2}"
          ;;
      esac
    elif [ -n "$__bs_args_pss_cluster" ]; then
      case "$__bs_args_pss_cluster" in
        =*)
          bs_args_parse_refuse "flag \"-${__bs_args_pss_char}\" does not take a value"
          return "${E_INVALID:-2}"
          ;;
      esac
    fi
    bs_args_store_flag_value "$__bs_args_pss_name" "$__bs_args_pss_value"
  done
  return "${E_SUCCESS:-0}"
}
```

In the main parse loop, add a `-*` branch before the positional default:

```sh
-*)
  if bs_args_use_short "$__bs_args_ps_param"; then
    bs_args_parse_short "$__bs_args_ps_param" "$@" || return $?
    if [ "$__bs_args_ps_used" -eq 1 ]; then shift; fi
    if [ "${ARGS_HELP_REQUESTED:-0}" -eq 1 ]; then break; fi
  else
    __bs_args_ps_pos=$((__bs_args_ps_pos + 1))
    bs_args_parse_positional "$__bs_args_ps_param" || return $?
  fi
  ;;
```

Guard the final required-positional check:

```sh
if [ "${ARGS_HELP_REQUESTED:-0}" -eq 0 ]; then
  bs_args_parse_required "$__bs_args_ps_pos" || return $?
fi
```

- [ ] **Step 4: Run tests and verify GREEN**

Run: `./bs run tests/unit/testargsportableunit.sh && ./bs run tests/unit/testargsunit.sh`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add core/args.sh tests/unit/testargsportableunit.sh
git commit -m "feat(args): parse short aliases and option clusters"
```

---

### Task 5: Help scanning understands short options

**Files:**
- Modify: `core/args.sh`
- Test: `tests/unit/testargsportableunit.sh`

**Interfaces:**
- Consumes: Task 1 short maps, Task 4 cluster grammar.
- Produces: help detection for `-h`, grouped `-vh`, value-skip and `--` boundaries.

- [ ] **Step 1: Write failing help-scan tests**

Append inside the portable shell loop:

```sh
eq "$(probe "${sh_bin}" '
bs_args_define deploy
bs_args_flag verbose; bs_args_flag_short verbose v
bs_args_flag output value; bs_args_flag_short output o
bs_args_parse -vh >/dev/null; printf "group=%s " "$ARGS_HELP_REQUESTED"
bs_args_parse -o -h >/dev/null; printf "value=%s " "$ARGS_HELP_REQUESTED"
bs_args_parse -vo report -h >/dev/null; printf "after=%s " "$ARGS_HELP_REQUESTED"
bs_args_parse -- -h >/dev/null 2>&1; printf "raw=%s\n" "$ARGS_HELP_REQUESTED"
')" "group=1 value=0 after=1 raw=0" "${sh_name}: short help scan boundaries"
```

Add a declared `h` value flag case:

```sh
eq "$(probe "${sh_bin}" '
bs_args_flag h value
bs_args_flag_short h h
bs_args_parse -h hello >/dev/null; printf "declared=%s value=%s\n" "$ARGS_HELP_REQUESTED" "$(bs_args_flag_get h)"
')" "declared=0 value=hello" "${sh_name}: declared h wins over built-in help"
```

- [ ] **Step 2: Run tests and verify RED**

Run: `./bs run tests/unit/testargsportableunit.sh`

Expected: FAIL for grouped help because the pre-scan only recognizes exact `-h`.

- [ ] **Step 3: Extend `bs_args_parse_help_requested`**

Add this branch to its `case`, before the positional default:

```sh
-?*)
  __bs_args_ph_cluster=${__bs_args_ph_arg#-}
  while [ -n "$__bs_args_ph_cluster" ]; do
    __bs_args_ph_char=${__bs_args_ph_cluster%"${__bs_args_ph_cluster#?}"}
    __bs_args_ph_cluster=${__bs_args_ph_cluster#?}
    if ! bs_map_has bs_args_short_flag "$__bs_args_ph_char"; then
      if [ "$__bs_args_ph_char" = h ]; then
        bs_args_mget bs_args_flags h __bs_args_ph_hkind
        [ -z "$__bs_args_ph_hkind" ] && return 0
      fi
      break
    fi
    bs_map_get_to bs_args_short_flag "$__bs_args_ph_char" __bs_args_ph_long
    bs_args_mget bs_args_flags "$__bs_args_ph_long" __bs_args_ph_t
    if [ "$__bs_args_ph_t" = value ]; then
      if [ -z "$__bs_args_ph_cluster" ]; then __bs_args_ph_skip=1; fi
      break
    fi
    case "$__bs_args_ph_cluster" in
      =*) break ;;
    esac
  done
  ;;
```

Keep the existing `--`, `--*=*`, `--*` and exact `-h` handling unchanged.

- [ ] **Step 4: Run tests and verify GREEN**

Run: `./bs run tests/unit/testargsportableunit.sh && ./bs run tests/unit/testargsunit.sh`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add core/args.sh tests/unit/testargsportableunit.sh
git commit -m "fix(args): detect help inside short option clusters"
```

---

### Task 6: Bash bridge and lossless repeat arrays

**Files:**
- Modify: `lib/compat/args.sh`
- Test: `tests/unit/testargsunit.sh`
- Test: `tests/unit/testargsportableunit.sh`

**Interfaces:**
- Consumes: Task 2 repeat arrays and `bs_args_flag_get_all`.
- Produces: `args::flag_values NAME ARRAY_NAME`; `args::flag_get_all`; `ARGS_FLAGS[NAME]` remains the first value.

- [ ] **Step 1: Write failing bridge tests**

Append to `testargsunit.sh`:

```bash
args::reset
args::flag label value
args::flag_repeat label
args::flag_short label l
args::parse -l "two words" --label $'line1\nline2' -l '*'
testframework::assert_equal "two words" "${ARGS_FLAGS[label]}" "ARGS_FLAGS keeps first repeat value"
local -a labels=()
args::flag_values label labels
testframework::assert_equal "3" "${#labels[@]}" "flag_values copies every occurrence"
testframework::assert_equal "two words" "${labels[0]}" "spaces survive flag_values"
testframework::assert_equal $'line1\nline2' "${labels[1]}" "newlines survive flag_values"
testframework::assert_equal "*" "${labels[2]}" "glob characters survive flag_values"
args::parse --label '$(printf injected)'
args::flag_values label labels
testframework::assert_equal '$(printf injected)' "${labels[0]}" "literal substitution is not evaluated"
rc=0
args::flag_values label 'bad-name' >/dev/null 2>&1 || rc=$?
testframework::assert_equal "${E_INVALID}" "$rc" "flag_values rejects invalid array names"
args::parse
args::flag_values label labels
testframework::assert_equal "0" "${#labels[@]}" "flag_values leaves an empty array when unset"
```

Add a portable alias check for `args::flag_get_all` in `testargsportableunit.sh`:

```sh
eq "$(probe "${sh_bin}" 'args::flag e value; args::flag_repeat e; args::parse --e a --e b; args::flag_get_all e | tr "\n" "|"')" "a|b|" "${sh_name}: flag_get_all alias"
```

- [ ] **Step 2: Run tests and verify RED**

Run: `./bs run tests/unit/testargsunit.sh`

Expected: FAIL because `args::flag_values` is not defined.

- [ ] **Step 3: Implement the bridge functions**

Add to `lib/compat/args.sh` after `args::parse`:

```bash
# @description Все CLI-значения флага, по одному на строку / All CLI values of a flag, one per line
# @param $1 canonical flag name
args::flag_get_all() {
    bs_args_flag_get_all "$@"
}

# @description Скопировать CLI-значения флага в caller-named массив / Copy CLI flag values into a caller-named array
# @param $1 canonical flag name
# @param $2 caller array name
args::flag_values() {
    local name="${1:-}" array_name="${2:-}" i value count
    case "$array_name" in
        ''|[0-9]*|__bs_*|*[!A-Za-z0-9_]*)
            log::error "args::flag_values: invalid array name: ${array_name}"
            return "${E_INVALID:-2}"
            ;;
    esac

    bs_arr_clear bs_args_selected
    if bs_map_has bs_args_flag_repeat "$name"; then
        bs_data_len_of bs_args_repeat_names
        count=$__bs_dat_n
        for (( i=0; i<count; i++ )); do
            bs_data_get_at bs_args_repeat_names "$i"
            if [[ "$__bs_dat_cur" == "$name" ]]; then
                bs_data_get_at bs_args_repeat_values "$i"
                bs_arr_push bs_args_selected "$__bs_dat_cur"
            fi
        done
    elif bs_map_has bs_args_parsed "$name"; then
        bs_map_get_to bs_args_parsed "$name" value
        bs_arr_push bs_args_selected "$value"
    fi

    bs_arr_to_args_to bs_args_selected __bs_args_fv_args
    eval "$__bs_args_fv_args"
    if ! eval "${array_name}=(\"\$@\")"; then
        log::error "args::flag_values: cannot assign array: ${array_name}"
        return "${E_INVALID:-2}"
    fi
    return "${E_SUCCESS:-0}"
}
```

- [ ] **Step 4: Run tests and verify GREEN**

Run: `./bs run tests/unit/testargsunit.sh && ./bs run tests/unit/testargsportableunit.sh`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/compat/args.sh tests/unit/testargsunit.sh tests/unit/testargsportableunit.sh
git commit -m "feat(args): expose lossless repeat values to bash arrays"
```

---

### Task 7: Help and completion metadata

**Files:**
- Modify: `core/args.sh`
- Modify: `core/args-completion.sh`
- Test: `tests/unit/testargsunit.sh`
- Test: `tests/unit/testargs-completionportableunit.sh`

**Interfaces:**
- Consumes: Task 1 property maps.
- Produces: help labels with short aliases and bool-value forms; completion entries for both short and long forms.

- [ ] **Step 1: Write failing help/completion tests**

Add to `testargsunit.sh`:

```bash
args::reset
args::flag port value "" number
args::flag_short port p
args::flag color bool
args::flag_bool_value color
args::flag_short color c
local ext_help
ext_help="$(args::help prog)"
testframework::assert_true "\$ext_help == *'-p, --port <number>'*" "help shows short value alias"
testframework::assert_true "\$ext_help == *'-c, --color[=true|false]'*" "help shows bool-value form"
```

Add a separate declaration set and assertions to `testargs-completionportableunit.sh`:

```sh
EXT_DECL='bs_args_flag port value "" number
bs_args_flag_short port p
bs_args_flag color bool
bs_args_flag_bool_value color
bs_args_flag_short color c'

has_tokens() {
    local text="$1" token rc=0
    shift
    for token in "$@"; do
        if ! printf '%s\n' "$text" | grep -Fq -- "$token"; then rc=1; fi
    done
    printf '%s' "$rc"
}
```

Inside the shell loop:

```sh
eq "$(has_tokens "$(probe "${sh_bin}" "${EXT_DECL}"$'\n''bs_args_completion prog bash')" --port ' -p' --color ' -c')" \
"0" "${sh_name}: bash completion advertises short aliases"
eq "$(has_tokens "$(probe "${sh_bin}" "${EXT_DECL}"$'\n''bs_args_completion prog zsh')" --port '-p=:value:' --color "'-c'")" \
"0" "${sh_name}: zsh completion advertises aliases"
eq "$(has_tokens "$(probe "${sh_bin}" "${EXT_DECL}"$'\n''bs_args_completion prog fish')" '-l port' '-s p' '-l color' '-s c')" \
"0" "${sh_name}: fish completion advertises aliases"
eq "$(has_tokens "$(probe "${sh_bin}" "${EXT_DECL}"$'\n''bs_args_completion prog nu')" '--port: string' '-p: string' '  --color' '  -c')" \
"0" "${sh_name}: nu completion advertises aliases"
```

- [ ] **Step 2: Run tests and verify RED**

Run: `./bs run tests/unit/testargsunit.sh && ./bs run tests/unit/testargs-completionportableunit.sh`

Expected: FAIL because help/completion ignore the new metadata.

- [ ] **Step 3: Update help labels**

In `bs_args_help_flags`, replace label construction with:

```sh
bs_args_mget bs_args_flag_short "$__bs_args_hf_flag" __bs_args_hf_short
__bs_args_hf_label="--${__bs_args_hf_flag}"
if [ -n "$__bs_args_hf_short" ]; then
  __bs_args_hf_label="-${__bs_args_hf_short}, ${__bs_args_hf_label}"
fi
if [ "$__bs_args_hf_kind" = value ]; then
  __bs_args_hf_hint="value"
  case "$__bs_args_hf_val" in
    number) __bs_args_hf_hint="number" ;;
    enum:*) __bs_args_hf_hint="${__bs_args_hf_val#enum:}" ;;
  esac
  __bs_args_hf_label="${__bs_args_hf_label} <${__bs_args_hf_hint}>"
elif bs_map_has bs_args_flag_bool_value "$__bs_args_hf_flag"; then
  __bs_args_hf_label="${__bs_args_hf_label}[=true|false]"
fi
```

- [ ] **Step 4: Update completion generators**

In `bs_args_completion_bash`, after adding each long flag to `__bs_args_cp_words`, add:

```sh
bs_args_mget bs_args_flag_short "$__bs_args_cp_n" __bs_args_cp_short
if [ -n "$__bs_args_cp_short" ]; then
  __bs_args_cp_words="${__bs_args_cp_words} -${__bs_args_cp_short}"
fi
```

For enum completion, build the case pattern with both forms:

```sh
__bs_args_cp_match="--${__bs_args_cp_n}"
bs_args_mget bs_args_flag_short "$__bs_args_cp_n" __bs_args_cp_short
if [ -n "$__bs_args_cp_short" ]; then __bs_args_cp_match="${__bs_args_cp_match}|-${__bs_args_cp_short}"; fi
```

Use `${__bs_args_cp_match}` in the generated `case "\${prev}" in` line. For non-enum value flags, append both forms to `__bs_args_cp_vflags`:

```sh
__bs_args_cp_vflags="${__bs_args_cp_vflags} --${__bs_args_cp_n}"
bs_args_mget bs_args_flag_short "$__bs_args_cp_n" __bs_args_cp_short
if [ -n "$__bs_args_cp_short" ]; then
  __bs_args_cp_vflags="${__bs_args_cp_vflags} -${__bs_args_cp_short}"
fi
```

In `bs_args_completion_zsh`, after pushing the long spec, push a short spec when present:

```sh
bs_args_mget bs_args_flag_short "$__bs_args_zs_name" __bs_args_zs_short
if [ -n "$__bs_args_zs_short" ]; then
  case "$__bs_args_zs_kind" in
    enum)  bs_arr_push bs_args_specs "$(bs_quote "-${__bs_args_zs_short}=:value:(${__bs_args_zs_vals})")" ;;
    value) bs_arr_push bs_args_specs "$(bs_quote "-${__bs_args_zs_short}=:value: ")" ;;
    *)     bs_arr_push bs_args_specs "$(bs_quote "-${__bs_args_zs_short}")" ;;
  esac
fi
```

In `bs_args_completion_fish`, compute an optional short switch and include it in every `complete` line:

```sh
bs_args_mget bs_args_flag_short "$__bs_args_fi_name" __bs_args_fi_short
__bs_args_fi_shortopt=""
if [ -n "$__bs_args_fi_short" ]; then __bs_args_fi_shortopt="-s ${__bs_args_fi_short} "; fi
```

For example, replace the fish `case` body with:

```sh
enum)  printf 'complete -c %s %s-l %s -x -a %s\n' "$__bs_args_fi_q" "$__bs_args_fi_shortopt" "$__bs_args_fi_name" "$(bs_quote "$(printf '%s' "$__bs_args_fi_values" | tr ',' ' ')")" ;;
value) printf 'complete -c %s %s-l %s -r\n' "$__bs_args_fi_q" "$__bs_args_fi_shortopt" "$__bs_args_fi_name" ;;
*)     printf 'complete -c %s %s-l %s\n' "$__bs_args_fi_q" "$__bs_args_fi_shortopt" "$__bs_args_fi_name" ;;
```

In `bs_args_completion_nu`, push a short declaration alongside each long declaration:

```sh
bs_args_mget bs_args_flag_short "$__bs_args_nu_name" __bs_args_nu_short
if [ -n "$__bs_args_nu_short" ]; then
  case "$__bs_args_nu_kind" in
    enum|value) bs_arr_push bs_args_decl "  -${__bs_args_nu_short}: string" ;;
    *)          bs_arr_push bs_args_decl "  -${__bs_args_nu_short}" ;;
  esac
fi
```

- [ ] **Step 5: Run tests and verify GREEN**

Run: `./bs run tests/unit/testargsunit.sh && ./bs run tests/unit/testargs-completionportableunit.sh && ./bs run tests/unit/testargsportableunit.sh`

Expected: PASS. Existing completion checksum fixtures remain unchanged because `DECL_T1` has no new properties.

- [ ] **Step 6: Commit**

```bash
git add core/args.sh core/args-completion.sh tests/unit/testargsunit.sh tests/unit/testargs-completionportableunit.sh
git commit -m "feat(args): show aliases and bool-value forms in help and completion"
```

---

### Task 8: Example, documentation and release 0.27.0

**Files:**
- Modify: `examples/argsparseexample.sh`
- Modify: `documentation/en/03-modules/args.md`
- Modify: `documentation/ru/03-modules/args.md`
- Modify: `.agents/skills/bs-cli-flags-style/SKILL.md`
- Modify: `core/version.sh`
- Modify: `CHANGELOG.md`
- Modify: `tests/unit/testbsnobashunit.sh`
- Modify: `mtest/t_const_version.sh`
- Modify: `mtest/t_nu.nu`
- Modify: en/ru architecture and core-api version examples

**Interfaces:**
- Consumes: completed parser, bridge, help and completion APIs.
- Produces: runnable documented example and release `0.27.0 "ключи"`.

- [ ] **Step 1: Extend the example declarations and output**

In `examples/argsparseexample.sh`, add:

```bash
args::flag label value
args::flag_repeat label
args::flag_short label l
args::flag color bool
args::flag_bool_value color
args::flag_short color c
args::flag_describe label "Repeatable label"
args::flag_describe color "Enable colour (true or false)"
```

After parsing, add:

```bash
local -a labels=()
args::flag_values label labels
log::info "Labels: ${#labels[@]}"
local color
color="$(args::flag_get color 1)"
log::info "Color: ${color}"
```

Update the try-it comments with:

```bash
#   bs run examples/argsparseexample.sh deploy now -l one --label "two words" -c=false
```

- [ ] **Step 2: Document the new API in both languages**

Add a section after the existing flag description with this structure in both files:

```markdown
### Short aliases, repeats and boolean values

args::flag_short NAME SHORT assigns one ASCII letter or digit.
args::flag_repeat NAME makes a value flag repeatable.
args::flag_bool_value NAME lets a bool flag accept =true or =false.

args::flag port value 8080 number
args::flag_short port p
args::flag env value
args::flag_repeat env
args::flag color bool
args::flag_bool_value color

Accepted forms include -p 8080, -p=8080, -p8080, grouped bool
flags, and --color=false. args::flag_get env returns the first value;
args::flag_get_all env prints all CLI values one per line. In bash,
args::flag_values env values fills an array without losing argument
boundaries.
```

Add these rows to both API tables:

```markdown
| `args::flag_short name short` | assign a one-character short alias |
| `args::flag_repeat name` | make a value flag repeatable |
| `args::flag_bool_value name` | allow `--name=true` / `--name=false` |
| `args::flag_get_all name` | all CLI values, one per line |
| `args::flag_values name array` | copy CLI values into a bash array losslessly |
```

State that `flag_get_all` is line-oriented and `flag_values` is the lossless API.

- [ ] **Step 3: Move the implemented items out of the args roadmap**

In `.agents/skills/bs-cli-flags-style/SKILL.md`, replace the “Часть C: расширения core/args (roadmap, НЕ реализовано)” section with an implemented-API section listing:

- `args::flag_short`;
- `args::flag_repeat` plus `args::flag_get_all` / `args::flag_values`;
- `args::flag_bool_value`;
- grouped short flags;
- the remaining explicit non-goal: automatic `--no-flag`.

- [ ] **Step 4: Bump the release**

Set `BS_VERSION` to `0.27.0` and `BS_CODENAME` to `ключи` in `core/version.sh`.

Add to `CHANGELOG.md` above `0.26.0`:

```markdown
## [0.27.0] - 2026-11-25 "ключи"

### Added
- feat(args): short aliases and Docker-style clusters, repeatable value flags with lossless bash arrays, and explicit `--flag=true|false`; help and completion expose the new forms while existing declarations remain compatible.
```

Replace `0.26.0` with `0.27.0` in the en/ru architecture/core-api examples and `tests/unit/testbsnobashunit.sh`. Replace codename `параллель` with `ключи` in `mtest/t_const_version.sh` and `mtest/t_nu.nu`.

- [ ] **Step 5: Run focused tests and the example**

```bash
./bs run tests/unit/testargsunit.sh
./bs run tests/unit/testargsportableunit.sh
./bs run tests/unit/testargs-completionportableunit.sh
./bs run examples/argsparseexample.sh deploy now -l one --label "two words" -c=false
```

Expected: all tests pass; the example reports two labels and color `0`.

- [ ] **Step 6: Run the full validation cycle**

```bash
bash tests/validatesyntax.sh
bash tests/validateshellcheck.sh
bash tests/runalltests.sh --jobs 4
bash tests/validatedocscode.sh
bash .agents/skills/bs-version-bump/scripts/version.sh check
```

Expected: all pass; only known environment skips may remain.

- [ ] **Step 7: Commit**

```bash
git add examples/argsparseexample.sh documentation/en/03-modules/args.md \
  documentation/ru/03-modules/args.md .agents/skills/bs-cli-flags-style/SKILL.md \
  core/version.sh CHANGELOG.md tests/unit/testbsnobashunit.sh \
  mtest/t_const_version.sh mtest/t_nu.nu \
  documentation/en/02-core-concepts/architecture.md \
  documentation/ru/02-core-concepts/architecture.md \
  documentation/en/04-api-reference/core-api.md \
  documentation/ru/04-api-reference/core-api.md
git commit -m "chore(release): 0.27.0 \"ключи\""
```

---

## Self-Review

### Spec coverage

- Public declaration API: Task 1.
- Repeat storage/readers and long parsing: Task 2.
- Bool-value long forms: Task 3.
- Short forms, clusters and legacy dash positionals: Task 4.
- Help scanning: Task 5.
- Bash lossless arrays: Task 6.
- Help/completion metadata: Task 7.
- Example, docs, roadmap and release: Task 8.

### Placeholder scan

No step relies on unspecified code or a later task to define a referenced function.

### Signature consistency

- Canonical property functions are `bs_args_flag_short`, `bs_args_flag_repeat`, `bs_args_flag_bool_value`.
- Readers are `bs_args_flag_get_all` and bridge-only `args::flag_values`.
- Repeat arrays are `bs_args_repeat_names` / `bs_args_repeat_values`.
- Short maps are `bs_args_flag_short` / `bs_args_short_flag`.

### Review Focus coverage

- Legacy `-foo`: Task 4.
- Lossless repeat values: Task 6.
- Short value consumption and `--`: Task 4.
- Help boundaries: Task 5.
- Bool false plus help/completion: Tasks 3 and 7.
