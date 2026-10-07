# Output Format Module — Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Ship `lib/data/format.sh` — a dependency-free renderer that turns canonical `key=value` records into `string`, `json`, or `xml`, selected by a parameter.

**Architecture:** The module owns a registry `FORMATTERS[format]=render-function`; `format::emit` reads records from stdin and dispatches. Methods emit canonical records via `format::record`; they never format. This is Batch 0 of the spec; later batches migrate the getters.

**Tech Stack:** Bash 4+, BS framework (`core/lang`, `core/const`, `core/utils`, `core/logger`), custom testframework.

**Spec:** `docs/superpowers/specs/2026-10-07-output-format-contract-design.md`

## Global Constraints

- Shebang `#!/usr/bin/env bs`, line 2 `# shellcheck shell=bash`, `bs::guard`, `bs::source_relative`; no `set -euo pipefail` in the library module.
- Paired bilingual `# @global` for every module variable (category: hook/constant).
- Error codes: `E_SUCCESS=0`, `LIB_ERROR_INVALID_ARGS=3`, `LIB_ERROR_INVALID_INPUT=4`.
- Run after each task: `bash tests/validatesyntax.sh`, `bash tests/validateshellcheck.sh`, `bash tests/runalltests.sh`.
- Tests invoked as `bash tests/unit/testformatunit.sh`; auto-discovered from `tests/unit/`.

## Review Focus

Failure modes no test exercises by default; each gets a test in the owning task.

1. A value containing `=` must survive (split on the first `=` only) — Task 2/4.
2. A value containing `"` `\` or a newline must be JSON-escaped, never break the object — Task 3.
3. A value containing `& < > " '` must be XML-escaped — Task 4.
4. Empty stdin must render `{}` / `<record/>` / empty, not crash — Task 2-4.
5. Unknown format must return `LIB_ERROR_INVALID_INPUT`, not print garbage — Task 5.

---

### Task 1: Module skeleton + registry + `string` renderer

**Files:**
- Create: `lib/data/format.sh`
- Test: `tests/unit/testformatunit.sh`

**Interfaces:**
- Produces: `BS_OUTPUT_FORMAT` (default `string`), `BS_FORMAT_ROOT` (default `record`), `FORMAT_NAMES=("string" "json" "xml")`, `FORMATTERS` (assoc).
- `format::list` → formats one per line; `format::validate <f>` → 0/`LIB_ERROR_INVALID_INPUT`; `format::record <k> <v> [...]` → stdout canonical lines; `format::emit <f>` (stdin canonical) → stdout rendered; `format::render::string` (stdin) → stdout.

- [ ] **Step 1: Write the failing test**

`tests/unit/testformatunit.sh`:

```bash
#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testformatunit.sh — unit tests for lib/data/format
# tests/unit/testformatunit.sh — юнит-тесты lib/data/format

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

load "lib/data/format"

main() {
    print_header "Format Unit Tests / Юнит-тесты format"
    testframework::init

    testframework::section "catalog / каталог"
    testframework::assert_equal "string json xml" "$(format::list | tr '\n' ' ' | sed 's/ $//')" "format list"
    local rc=0; format::validate json || rc=$?; testframework::assert_equal "0" "${rc}" "validate json"
    rc=0; format::validate bogus || rc=$?; testframework::assert_equal "${LIB_ERROR_INVALID_INPUT}" "${rc}" "validate unknown"

    testframework::section "record / канон"
    testframework::assert_equal $'ip=1.2.3.4\niface=eth0' "$(format::record ip 1.2.3.4 iface eth0)" "record two fields"
    testframework::assert_equal "a=b=c" "$(format::record a "b=c")" "value keeps equals"

    testframework::section "string renderer / строковый вывод"
    testframework::assert_equal "1.2.3.4" "$(format::record ip 1.2.3.4 | format::emit string)" "scalar → value only"
    testframework::assert_equal $'ip: 1.2.3.4\niface: eth0' \
        "$(printf 'ip=1.2.3.4\niface=eth0\n' | format::emit string)" "multi-field → key: value"
    testframework::assert_equal "" "$(format::emit string </dev/null)" "empty → empty"

    testframework::summary
}

main "$@"
```

- [ ] **Step 2: Run to verify failure**

Run: `bash tests/unit/testformatunit.sh`
Expected: FAIL — module not found / `format::list` not defined.

- [ ] **Step 3: Write the module**

Create `lib/data/format.sh`:

```bash
#!/usr/bin/env bs
# shellcheck shell=bash
# lib/data/format.sh — render canonical key=value records as string/json/xml
# lib/data/format.sh — рендер канонических записей key=value в string/json/xml
#
# @depends core/lang, core/const
# @tier core

# Source Guard / Защита от повторной загрузки
bs::guard "LIB_DATA_FORMAT" || return 0

# Dependencies / Зависимости
bs::source_relative "../../core/lang.sh" "../../core/const.sh"

# @global BS_OUTPUT_FORMAT — Format: selected output format (category: hook)
# @global BS_OUTPUT_FORMAT — Format: выбранный формат вывода (категория: hook)
declare -g BS_OUTPUT_FORMAT="string"
# @global BS_FORMAT_ROOT — Format: XML root element name (category: hook)
# @global BS_FORMAT_ROOT — Format: имя корневого XML-элемента (категория: hook)
declare -g BS_FORMAT_ROOT="record"

# @global FORMAT_NAMES — Format: available format names (category: constant)
# @global FORMAT_NAMES — Format: доступные имена форматов (категория: constant)
declare -ga FORMAT_NAMES=("string" "json" "xml")
# @global FORMATTERS — Format: format=render-function registry (category: constant)
# @global FORMATTERS — Format: реестр format=функция-рендер (категория: constant)
declare -gA FORMATTERS=(
    [string]="format::render::string"
    [json]="format::render::json"
    [xml]="format::render::xml"
)

# @description List available formats / Перечислить форматы
# @stdout formats one per line / форматы по одному в строке
format::list() {
    local f
    for f in "${FORMAT_NAMES[@]}"; do printf '%s\n' "${f}"; done
}

# @description Validate a format name / Проверить имя формата
# @param $1 Format / Формат
# @return E_SUCCESS or LIB_ERROR_INVALID_INPUT
format::validate() {
    local -r fmt="${1-}"
    is::empty "${fmt}" && return "${LIB_ERROR_INVALID_INPUT}"
    local f
    for f in "${FORMAT_NAMES[@]}"; do
        [[ "${f}" == "${fmt}" ]] && return "${E_SUCCESS}"
    done
    return "${LIB_ERROR_INVALID_INPUT}"
}

# @description Emit canonical records: key=value lines, one field per line.
# @description Вывести канонические записи: строки key=value, поле на строку.
# @param $1 Key, $2 Value, ... (pairs) / пары ключ-значение
# @stdout canonical lines / канонические строки
format::record() {
    local key value
    while (( $# > 0 )); do
        key="${1:?key required}"; shift
        value="${1-}"; (( $# > 0 )) && shift
        printf '%s=%s\n' "${key}" "${value}"
    done
}

# @description Render string: scalar value only, else "key: value" per line.
# @description Строковый вывод: скаляр — только значение, иначе "key: value".
# @stdin canonical records / канонические записи
# @stdout human text / человекочитаемый текст
format::render::string() {
    local line key value
    local -a fields=()
    local -i count=0 records=0
    while IFS= read -r line || is::not_empty "${line}"; do
        if is::empty "${line}"; then
            (( records > 0 )) && printf '\n'
            records=$(( records + 1 ))
            continue
        fi
        key="${line%%=*}"; value="${line#*=}"
        if (( records == 0 && count == 0 )); then
            printf '%s\n' "${key}: ${value}"
        else
            printf '%s: %s\n' "${key}" "${value}"
        fi
        count=$(( count + 1 ))
    done
    # scalar case: single field overall → print only the value
    # скаляр: единственное поле во всём вводе → только значение
    if (( count == 1 && records == 0 )); then
        : # already printed key: value; replaced below
    fi
    return 0
}
```

> The scalar special-case cannot be decided while streaming. Implement
> `format::render::string` by first **slurping** all lines into an array, then:
> if there is exactly one field across the whole input, print its value; else
> print `key: value` lines with a blank line between records. Replace the body
> above with:

```bash
format::render::string() {
    local line key value
    local -a out=()
    local -i fields=0 records=0
    while IFS= read -r line || is::not_empty "${line}"; do
        if is::empty "${line}"; then
            (( records > 0 )) && out+=("")
            records=$(( records + 1 ))
            continue
        fi
        key="${line%%=*}"; value="${line#*=}"
        out+=("${key}: ${value}")
        fields=$(( fields + 1 ))
    done
    if (( fields == 1 )); then
        # value only / только значение
        local -r only="${out[0]#*: }"
        printf '%s\n' "${only}"
        return 0
    fi
    local -i i
    for (( i = 0; i < ${#out[@]}; i++ )); do printf '%s\n' "${out[$i]}"; done
    return 0
}
```

- [ ] **Step 4: Run to verify pass**

Run: `bash tests/unit/testformatunit.sh`
Expected: PASS (json/xml will be added next; `format::emit` for string only).

- [ ] **Step 5: Commit**

```bash
git add lib/data/format.sh tests/unit/testformatunit.sh
git commit -m "feat(data): lib/data/format — canonical records, registry, string renderer; tests"
```

---

### Task 2: `format::emit` dispatcher + `json` renderer

**Files:**
- Modify: `lib/data/format.sh`
- Modify: `tests/unit/testformatunit.sh`

**Interfaces:**
- Consumes: `FORMATTERS`, `format::validate`.
- Produces: `format::emit <f>`; `format::render::json`; `format::__json_escape`.

- [ ] **Step 1: Add failing tests**

Append in `main()` before `testframework::summary`:

```bash
    testframework::section "json renderer / json"
    testframework::assert_equal '{"ip":"1.2.3.4"}' "$(printf 'ip=1.2.3.4\n' | format::emit json)" "single object"
    testframework::assert_equal '[{"a":"1"},{"a":"2"}]' \
        "$(printf 'a=1\n\na=2\n' | format::emit json)" "array of objects"
    testframework::assert_equal '{}' "$(format::emit json </dev/null)" "empty → {}"
    testframework::assert_equal '{"x":"a\"b\\c"}' \
        "$(printf 'x=a"b\\c\n' | format::emit json)" "quote/backslash escaped"
    testframework::assert_equal '{"k":"v=w"}' "$(printf 'k=v=w\n' | format::emit json)" "equals kept"

    testframework::section "emit errors / ошибки"
    local erc=0; format::emit bogus </dev/null 2>/dev/null || erc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_INPUT}" "${erc}" "unknown format"
```

- [ ] **Step 2: Run to verify failure**

Run: `bash tests/unit/testformatunit.sh`
Expected: FAIL — `format::emit: command not found`.

- [ ] **Step 3: Implement**

Append to `lib/data/format.sh`:

```bash
# @description Escape a string for JSON / Экранировать строку для JSON
# @param $1 String / Строка
# @stdout escaped / экранированная
format::__json_escape() {
    local s="${1-}"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "${s}"
}

# @description Render JSON: object for one record, array for several.
# @description Рендер JSON: объект для одной записи, массив для нескольких.
# @stdin canonical records / канонические записи
# @stdout JSON / JSON
format::render::json() {
    local -a records=()
    local cur=""
    local line key value
    while IFS= read -r line || is::not_empty "${line}"; do
        if is::empty "${line}"; then
            if is::not_empty "${cur}"; then records+=("${cur}"); cur=""; fi
            continue
        fi
        key="${line%%=*}"; value="${line#*=}"
        is::empty "${cur}" || cur+=","
        cur+="\"$(format::__json_escape "${key}")\":\"$(format::__json_escape "${value}")\""
    done
    is::not_empty "${cur}" && records+=("${cur}")
    if (( ${#records[@]} == 0 )); then printf '{}\n'; return 0; fi
    if (( ${#records[@]} == 1 )); then printf '{%s}\n' "${records[0]}"; return 0; fi
    local out="[" i
    for (( i = 0; i < ${#records[@]}; i++ )); do
        (( i == 0 )) || out+=","
        out+="{${records[$i]}}"
    done
    printf '%s]\n' "${out}"
}

# @description Dispatch records to the renderer for a format.
# @description Направить записи в рендерер выбранного формата.
# @param $1 Format / Формат
# @stdin canonical records / канонические записи
# @stdout rendered text / отрендеренный текст
format::emit() {
    local -r fmt="${1-}"
    format::validate "${fmt}" || return "${LIB_ERROR_INVALID_INPUT}"
    local -r fn="${FORMATTERS[${fmt}]}"
    is::function "${fn}" || return "${LIB_ERROR_INVALID_INPUT}"
    "${fn}"
}
```

- [ ] **Step 4: Run to verify pass**

Run: `bash tests/unit/testformatunit.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/data/format.sh tests/unit/testformatunit.sh
git commit -m "feat(data): format::emit dispatcher + JSON renderer; tests"
```

---

### Task 3: `xml` renderer

**Files:**
- Modify: `lib/data/format.sh`
- Modify: `tests/unit/testformatunit.sh`

**Interfaces:**
- Produces: `format::render::xml`, `format::__xml_escape`.

- [ ] **Step 1: Add failing tests**

```bash
    testframework::section "xml renderer / xml"
    testframework::assert_equal '<record><ip>1.2.3.4</ip></record>' \
        "$(printf 'ip=1.2.3.4\n' | format::emit xml)" "single record"
    testframework::assert_equal '<records><record><a>1</a></record><record><a>2</a></record></records>' \
        "$(printf 'a=1\n\na=2\n' | format::emit xml)" "multiple records"
    testframework::assert_equal '<record><x>a&amp;b&lt;c&gt;d&quot;e&apos;f</x></record>' \
        "$(printf 'x=a&b<c>d"e'"'"'f\n' | format::emit xml)" "xml escaping"
    testframework::assert_equal '<record/>' "$(format::emit xml </dev/null)" "empty → <record/>"
    BS_FORMAT_ROOT=node; testframework::assert_equal '<node><k>v</k></node>' \
        "$(printf 'k=v\n' | format::emit xml)" "custom root"
    unset BS_FORMAT_ROOT; BS_FORMAT_ROOT="record"
```

- [ ] **Step 2: Run to verify failure**

Run: `bash tests/unit/testformatunit.sh`
Expected: FAIL — `format::render::xml: command not found`.

- [ ] **Step 3: Implement**

```bash
# @description Escape a string for XML / Экранировать строку для XML
# @param $1 String / Строка
# @stdout escaped / экранированная
format::__xml_escape() {
    local s="${1-}"
    s="${s//&/&amp;}"
    s="${s//</&lt;}"
    s="${s//>/&gt;}"
    s="${s//\"/&quot;}"
    s="${s//\'/&apos;}"
    printf '%s' "${s}"
}

# @description Render XML: one <record>, or <records> wrapping several.
# @description Рендер XML: один <record> или <records> вокруг нескольких.
# @stdin canonical records / канонические записи
# @stdout XML / XML
format::render::xml() {
    local -a records=()
    local cur=""
    local line key value
    local -r root="${BS_FORMAT_ROOT:-record}"
    while IFS= read -r line || is::not_empty "${line}"; do
        if is::empty "${line}"; then
            if is::not_empty "${cur}"; then records+=("${cur}"); cur=""; fi
            continue
        fi
        key="${line%%=*}"; value="${line#*=}"
        cur+="<$(format::__xml_escape "${key}")>$(format::__xml_escape "${value}")</$(format::__xml_escape "${key}")>"
    done
    is::not_empty "${cur}" && records+=("${cur}")
    if (( ${#records[@]} == 0 )); then printf '<%s/>\n' "${root}"; return 0; fi
    if (( ${#records[@]} == 1 )); then printf '<%s>%s</%s>\n' "${root}" "${records[0]}" "${root}"; return 0; fi
    local out="<records>" r
    for r in "${records[@]}"; do out+="<record>${r}</record>"; done
    printf '%s</records>\n' "${out}"
}
```

- [ ] **Step 4: Run to verify pass**

Run: `bash tests/unit/testformatunit.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/data/format.sh tests/unit/testformatunit.sh
git commit -m "feat(data): format XML renderer (root override, escaping, multi-record); tests"
```

---

### Task 4: Documentation + output_contract registration

**Files:**
- Create: `documentation/en/03-modules/data-format.md`
- Create: `documentation/ru/03-modules/data-format.md`
- Modify: `documentation/en/03-modules/lib-modules-overview.md`, `documentation/ru/03-modules/lib-modules-overview.md`
- Modify: `lib/ui/output_contract.sh`

**Interfaces:** docs only.

- [ ] **Step 1:** Write `data-format.md` (en): purpose, `load "lib/data/format"`, canonical grammar, `BS_OUTPUT_FORMAT`/`BS_FORMAT_ROOT`, the API table, renderer behavior (scalar string, json object/array, xml root/escaping), error codes, and the method-integration snippet from spec §6. Mirror in RU.

- [ ] **Step 2:** Add a data group line to both overviews linking `data-format.md` and `format.sh`.

- [ ] **Step 3:** Register in `lib/ui/output_contract.sh`: add an entry
  `"formats:Форматы данных / Data formats (string/json/xml):lib/data/format.sh:examples/output_contract/formats.sh"` and create `examples/output_contract/formats.sh` demonstrating the three formats (mirror an existing demo's shape).

- [ ] **Step 4:** Run `bash tests/unit/testoutputcontractunit.sh` and `bash tests/validatedocscode.sh` (if present).

- [ ] **Step 5: Commit**

```bash
git add documentation lib/ui/output_contract.sh examples/output_contract/formats.sh
git commit -m "docs(data): data-format.md en/ru + overview + output_contract formats unit"
```

---

### Task 5: Full validation

- [ ] Run `bash tests/validatesyntax.sh` — exit 0.
- [ ] Run `bash tests/validateshellcheck.sh` — 0 errors.
- [ ] Run `bash tests/runalltests.sh` — all pass, `testformatunit` included.
- [ ] Fix any failure; commit with a `fix(...)` message.

## Self-Review

**Spec coverage:** registry+API (T1/T2/T3), grammar `=`-first (T1 test, T2 test), JSON escaping (T2), XML escaping/root/multi (T3), empty input (T2/T3), unknown format (T2), docs+output_contract (T4), validation (T5). Envelope (`result`) reuse and dataprocessor delegation are documented in the spec as optional and are not code in this foundation plan (Batch 1+ uses the envelope where needed).

**Placeholders:** the only deferred decision (scalar string slurping) is resolved inline in T1 Step 3 with the final body.

**Type consistency:** `format::record`, `format::emit`, `format::render::{string,json,xml}`, `FORMATTERS`, `FORMAT_NAMES`, `BS_OUTPUT_FORMAT`, `BS_FORMAT_ROOT` are used consistently across tasks.

**Review Focus mapping:** (1) equals-first → T1/T2 tests; (2) JSON escaping → T2 test; (3) XML escaping → T3 test; (4) empty input → T2/T3 tests; (5) unknown format → T2 test.
