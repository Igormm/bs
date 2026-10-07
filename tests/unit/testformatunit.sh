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
    testframework::assert_equal $'ip=1.2.3.4\niface=eth0' \
        "$(printf 'ip=1.2.3.4\niface=eth0\n' | format::emit string)" "multi-field → key=value (canonical)"
    testframework::assert_equal $'eth0\nwlan0' \
        "$(printf 'iface=eth0\n\niface=wlan0\n' | format::emit string)" "list of single-field → values only"
    testframework::assert_equal "" "$(format::emit string </dev/null)" "empty → empty"

    testframework::section "json renderer / json"
    testframework::assert_equal '{"ip":"1.2.3.4"}' "$(printf 'ip=1.2.3.4\n' | format::emit json)" "single object"
    testframework::assert_equal '[{"a":"1"},{"a":"2"}]' \
        "$(printf 'a=1\n\na=2\n' | format::emit json)" "array of objects"
    testframework::assert_equal '{}' "$(format::emit json </dev/null)" "empty → {}"
    testframework::assert_equal '{"x":"a\"b\\c"}' \
        "$(printf 'x=a"b\\c\n' | format::emit json)" "quote/backslash escaped"
    testframework::assert_equal '{"k":"v=w"}' "$(printf 'k=v=w\n' | format::emit json)" "equals kept"

    testframework::section "xml renderer / xml"
    testframework::assert_equal '<record><ip>1.2.3.4</ip></record>' \
        "$(printf 'ip=1.2.3.4\n' | format::emit xml)" "single record"
    testframework::assert_equal '<records><record><a>1</a></record><record><a>2</a></record></records>' \
        "$(printf 'a=1\n\na=2\n' | format::emit xml)" "multiple records"
    local xval="a&b<c>d\"e'f"
    testframework::assert_equal '<record><x>a&amp;b&lt;c&gt;d&quot;e&apos;f</x></record>' \
        "$(format::record x "${xval}" | format::emit xml)" "xml escaping"
    testframework::assert_equal '<record/>' "$(format::emit xml </dev/null)" "empty → <record/>"
    BS_FORMAT_ROOT=node
    testframework::assert_equal '<node><k>v</k></node>' \
        "$(printf 'k=v\n' | format::emit xml)" "custom root"
    BS_FORMAT_ROOT="record"

    testframework::section "emit errors / ошибки"
    local erc=0; format::emit bogus </dev/null 2>/dev/null || erc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_INPUT}" "${erc}" "unknown format"

    testframework::summary
}

main "$@"
