---
name: bs-variable-docs
description: Check that module-level variables (declare -g, readonly, export, : "${VAR:=...}") in documented categories carry a bilingual # @global doc snippet naming their category — so a reader can see what type of variable it is
type: prompt
whenToUse: After adding/renaming a module-level variable, when reviewing whether globals are documented, or when enforcing code-style-guide §4.2
---

The format is defined in `documentation/en|ru/code-style-guide.md` §4.2:
every module-level variable in categories 2 (module metadata), 7 (error
constants), 8 (framework flags), 9 (env vars), 10 (module hooks), 11 (module
constants) must carry a bilingual snippet directly above its declaration:

```bash
# @global FRAMEWORK_DEBUG — framework flag (category: framework-flag); default false
# @global FRAMEWORK_DEBUG — флаг фреймворка (категория: framework-flag); по умолчанию false
declare -g FRAMEWORK_DEBUG=false
```

No snippet required: guard flags (`__X_SOURCED`, set programmatically by
`bs::guard`), function-local variables (`local`, nameref `__sl_*`/`__arr_*`/
`__map_*`/`__b_*`, `_name` locals), ephemeral init.sh temps (`__name__`).
A `: "${VAR:=...}"` declaration is a hook — label it `hook`, regardless of
the name suffix.

## Check procedure

```bash
# 1. Enumerate module-level declarations and verify the @global snippet,
#    using a ROBUST name extraction (naive `rg -o '[A-Z][A-Z0-9_]*'` grabs
#    the "-A" of `declare -g -A NAME` and misses `__ARGS_*` names):
python3 - <<'PY'
import re, subprocess
decl = re.compile(r'^(declare -g[A-Za-z]*|readonly [A-Z][A-Z0-9_]*=|export [A-Z][A-Z0-9_]*=|: "\$\{[A-Z][A-Z0-9_]*:=)')
def names(line):
    if line.startswith(': "${'):
        m = re.search(r': "\$\{([A-Z_][A-Z0-9_]*):=', line)
        return [m.group(1)] if m else []
    rest = re.sub(r'^(declare -g[A-Za-z]*|readonly|export)\s*', '', line)
    for t in rest.split():
        if re.match(r'^-', t): continue
        m = re.match(r'([A-Z_][A-Z0-9_]*)', t)
        if m: return [m.group(1)]
    return []
missing = []
for path in subprocess.run(['git','ls-files','core/*.sh','lib/*/*.sh','bootstrap/*.sh'],
                           capture_output=True, text=True).stdout.split():
    for i, line in enumerate(open(path), 1):
        if not decl.match(line): continue
        for name in names(line):
            prev = open(path).readlines()[max(0,i-4):i-1]
            if not any(re.search(r'# @global ' + re.escape(name) + r'[ —-]', p) for p in prev):
                missing.append(f"{path}:{i} {name}")
print("missing:", len(missing))
for m in missing: print(" ", m)
PY

# 2. Verify each snippet names a §4.2 category label (guard-flag, module-flag,
#    ephemeral, nameref, private-fn, underscore, error-const, framework-flag,
#    env, hook, constant, private, state) — `rg -B2 <decl>` and check `(category: X)`.
```

## Mask hygiene (from §4.2)

- Anchored `\bE_[A-Z][A-Z_]*\b` for error constants — the unbounded
  `E_[A-Z_]+` false-matches `E__` inside `__BS_ROOT_CANDIDATE__`.
- Check order: anchored `__name__` (ephemeral) before open-ended `__x_y`
  (nameref) — `__bs_src__` matches both.
- `: "${VAR:=...}"` is a declaration (hook vars); `: "${VAR:-...}"` is a
  default-at-use — if it is the module's hook point (portability §8), it is a
  declaration and needs a snippet too.

## Output format

```
## bs-variable-docs check
### Missing @global snippet
- <file>:<line> — <VAR> — category <n>, mask <pattern>
### Snippet without category label
- <file>:<line> — <VAR> — snippet found but no §4.2 category label
### Verified clean
- <area> — checked, no findings
```

Report only; do not fix anything unless asked. Group findings by file.