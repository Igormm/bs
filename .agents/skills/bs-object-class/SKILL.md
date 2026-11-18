---
name: bs-object-class
description: Develop a class on the BS object model (core/object.sh) — fields, methods, properties, contracts, inheritance, delegation, lifetime — with the naming rules and a matching test
type: prompt
whenToUse: When asked to create a class or objects in BS, model stateful entities (sessions, connections, tasks, widgets), or extend code that uses object::* / bs_obj_*
arguments:
  - class_name
---

Develop the class `$class_name` on the BS object model. Rules: chapter 13 of
`documentation/{en,ru}/code-style-guide.md`; reference implementations:
`example_core/counter.sh` (single class) and `example_core/shapes.sh`
(inheritance, contract, delegation). If `$class_name` is not given, ask for the
class name and its purpose.

## 1. Decide: class or plain functions

A class needs **state + behavior + several instances**. One instance or pure
functions → plain module functions, no class (YAGNI). Say so and stop if a class
is not justified.

## 2. Pick the tier and the names

- bash4 module/script: `load "core/object"`, aliases `object::*`.
- posix code (`@shell posix`): real names `bs_obj_*` (no `::` aliases there).
- Method functions are `class_method` (`session_open`) in EVERY tier: the
  name validator rejects `::` (code 2). The module API stays `module::function`;
  a method function is an internal callback.
- Class and fields: `lower_snake_case` (§2.1), validator limit
  `[A-Za-z][A-Za-z0-9_]*`, no `__`, no trailing `_`. CamelCase is a style
  violation even though the validator accepts it.
- ID variables: semantic (`session_id`), never `obj1`. Reserved fields: `class`,
  `__init` (writing them → code 2).

## 3. Declare in order

Functions first, then: `class` → `field` (defaults) → `readonly`/`private` →
`method` → `property` → `watch` → `shared`/`const` → `type_method` →
`contract` → `delegate`. Parent classes are declared before children.

```bash
load "core/object"

session_open()  { object::set "$1" state open; }
session_close() { object::set "$1" state closed; }

object::class session
object::field session state new
object::field session token ''
object::private session token
object::method session open session_open
object::method session close session_close
object::contract session open close

object::new_to session_id session token=abc
object::call "$session_id" open
object::destroy "$session_id"
```

## 4. Method contract

- Instance method: `FN ID ARGS…`; type method: `FN CLASS ARGS…`. The ID is
  always first; never call a method function without it.
- State through `object::get/set`; private fields only through
  `object::raw_get/raw_set` inside the own class's methods.
- Result → stdout (one value = one line), status → return code. Codes:
  0 ok, 1 no such thing, 2 bad name/argument, 3 rule violation
  (readonly/private/constant/contract).
- Creation order: defaults → `init` → `field=value` pairs (pairs win). A failed
  `init` or contract leaves no object. Factory = a type method calling
  `object::new_to`. Private fields are initialized by the creation pairs
  (`token=abc`) or via `raw_set` inside `init`/methods.

## 5. Properties, watchers, reuse

- Getter `FN ID` → stdout; setter `FN ID VALUE` stores via `raw_set`;
  watcher `FN ID FIELD OLD NEW` runs after a successful write, its status is
  ignored. All three are user code and may nest model calls safely.
- Inheritance: `object::class child parent` — fields/methods/properties/type
  members/contracts are inherited; override by redeclaring the method.
- Delegation: `object::delegate class field`; the field holds another object's
  ID (set with `raw_set`). Delegate code 1 → try the next field; other codes go
  out. Caveat: a delegate method that LEGITIMATELY returns 1 is indistinguishable
  from "no method" and the next field is tried — design delegate statuses
  accordingly. **The owner destroys the delegates** — `destroy` does not cascade.

## 6. Lifetime

- Objects belong to the creating shell process; IDs never cross processes and
  are never reused. `id=$(object::new …)` loses the object in the subshell —
  always `object::new_to VAR class …`.
- Creator destroys: `object::destroy`; entry points clean up with
  `object::destroy_all` (optionally `bs_cleanup_add object::destroy_all`).
- Privacy is conventional: `__bs_dat_*` variables are visible to the whole
  process. Never present it as a security barrier.

## 7. Test and validate

- bash: unit test via `load "core/object"` (model: `tests/unit/testobjectunit.sh`).
- posix: portable test in six shells (model: `tests/unit/testobjectportableunit.sh`,
  skill `bs-write-test`).
- Required scenarios: codes 1/2/3; failed contract; readonly/private writes;
  nested calls (init/setter/destroy creating objects); delegation with an empty
  and a foreign field; subshell isolation; cleanup to count 0.

```bash
./bs tests/unit/test<name>unit.sh
bash tests/validatesyntax.sh
bash tests/validatedocscode.sh
bash tests/runalltests.sh
```

ShellCheck cannot see the ID assignment through `object::new_to` (SC2154):
add `# shellcheck disable=SC2154` with a bilingual reason, as in
`example_core/counter.sh`.

## Common mistakes (seen in this project)

| Mistake | Fix |
| --- | --- |
| `id=$(object::new …)` | `object::new_to id …` — mutation stays in the subshell otherwise |
| watcher/setter inside a pipe or `$(…)` | run it directly; capture output separately |
| CamelCase class (`Counter`) | `counter` (§2.1) |
| missing `load "core/object"` | aliases exist only after the load |
| writing `class`/`__init` fields | reserved, code 2 |
| relying on nested-call scratch (`__bs_obj_*`) | those are internal; keep own state in own variables |
| delegate target outlives its owner | destroy the delegates explicitly |
