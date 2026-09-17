#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testlangunit.sh — Unit tests for core/lang module
# tests/unit/testlangunit.sh — Модульные тесты для модуля core/lang

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

# Test bs::func_name returns the caller's name
test_func_name() {
    test::sample_function() {
        bs::func_name
    }
    testframework::assert_equal "test::sample_function" "$(test::sample_function)" "bs::func_name detects caller"

    # Depth 2: name of the caller's caller
    # Глубина 2: имя вызывающего выше
    test::deep_inner() { bs::func_name 2; }
    test::deep_outer() { test::deep_inner; }
    testframework::assert_equal "test::deep_outer" "$(test::deep_outer)" "bs::func_name honors depth"
}

# Test bs::call_stack prints frames
test_call_stack() {
    test::inner() { bs::call_stack; }
    test::outer() { test::inner; }
    local stack
    stack="$(test::outer)"
    testframework::assert_true "'${stack}' == *'test::inner'*" "call_stack contains inner frame"
    testframework::assert_true "'${stack}' == *'test::outer'*" "call_stack contains outer frame"
}

# Test bs::is_function / bs::is_defined / bs::type_of
test_type_predicates() {
    testframework::assert_command "bs::is_function bs::guard" "is_function finds bs::guard"
    testframework::assert_false "bs::is_function not-a-real-function-xyz" "is_function rejects unknown name"

    local sample_var="x"
    testframework::assert_command "bs::is_defined sample_var" "is_defined finds variable"
    testframework::assert_false "bs::is_defined sample_undefined_xyz" "is_defined rejects unknown variable"

    local -a sample_arr=(one two)
    local -A sample_map=([k]=v)
    local -i sample_int=42
    testframework::assert_equal "function" "$(bs::type_of bs::guard)" "type_of detects function"
    testframework::assert_equal "string" "$(bs::type_of sample_var)" "type_of detects string"
    testframework::assert_equal "array" "$(bs::type_of sample_arr)" "type_of detects array"
    testframework::assert_equal "map" "$(bs::type_of sample_map)" "type_of detects map"
    testframework::assert_equal "integer" "$(bs::type_of sample_int)" "type_of detects integer"
    testframework::assert_equal "undefined" "$(bs::type_of sample_undefined_xyz)" "type_of detects undefined"
}

# Test str:: functions
test_strings() {
    testframework::assert_equal "HELLO" "$(str::upper "hello")" "str::upper"
    testframework::assert_equal "hello" "$(str::lower "HeLLo")" "str::lower"
    testframework::assert_equal "hello" "$(str::trim "   hello   ")" "str::trim both sides"
    testframework::assert_equal "" "$(str::trim '   ')" "str::trim all-whitespace"
    testframework::assert_equal "a-b-c" "$(str::replace "a b c" " " "-")" "str::replace all spaces"
    testframework::assert_command "str::contains 'hello world' 'lo wo'" "str::contains finds substring"
    testframework::assert_false "str::contains 'hello' 'xyz'" "str::contains rejects"
    testframework::assert_command "str::starts_with 'hello' 'he'" "str::starts_with yes"
    testframework::assert_false "str::starts_with 'hello' 'lo'" "str::starts_with no"
    testframework::assert_command "str::ends_with 'hello' 'lo'" "str::ends_with yes"
    testframework::assert_false "str::ends_with 'hello' 'he'" "str::ends_with no"
}

# Test arr:: functions
test_arrays() {
    local -a fruits=(apple banana)

    testframework::assert_equal "2" "$(arr::length fruits)" "arr::length"

    arr::push fruits cherry
    testframework::assert_equal "3" "$(arr::length fruits)" "arr::push grows array"
    testframework::assert_equal "cherry" "${fruits[2]}" "arr::push appends value"

    testframework::assert_command "arr::contains fruits banana" "arr::contains finds element"
    testframework::assert_false "arr::contains fruits kiwi" "arr::contains rejects missing"

    testframework::assert_equal "apple, banana, cherry" "$(arr::join fruits ', ')" "arr::join"
}

# Test map::has
test_maps() {
    local -A colors=([red]="#f00" [green]="#0f0")
    testframework::assert_command "map::has colors red" "map::has finds key"
    testframework::assert_false "map::has colors blue" "map::has rejects missing key"
}

# Test arr::slice / str::slice / arr::reverse / str::reverse
test_slicing() {
    local -a nums=(zero one two three four five)

    # Full copy and bounded slices / Полная копия и ограниченные слайсы
    local -a out=()
    arr::slice nums out
    testframework::assert_equal "6" "${#out[@]}" "arr::slice copies whole array"
    testframework::assert_equal "one" "${out[1]}" "arr::slice preserves order"

    arr::slice nums out 1 4
    testframework::assert_equal "3" "${#out[@]}" "arr::slice [1:4] length"
    testframework::assert_equal "one two three" "$(arr::join out ' ')" "arr::slice [1:4] content"

    arr::slice nums out 0 3
    testframework::assert_equal "zero one two" "$(arr::join out ' ')" "arr::slice [0:3]"

    # Negative indices: from the end / Отрицательные индексы: с конца
    arr::slice nums out -2
    testframework::assert_equal "four five" "$(arr::join out ' ')" "arr::slice [-2:] last two"
    arr::slice nums out 2 -1
    testframework::assert_equal "two three four" "$(arr::join out ' ')" "arr::slice [2:-1]"

    # Step / Шаг
    arr::slice nums out "" "" 2
    testframework::assert_equal "zero two four" "$(arr::join out ' ')" "arr::slice step 2"
    arr::slice nums out "" "" -1
    testframework::assert_equal "five four three two one zero" "$(arr::join out ' ')" "arr::slice step -1 reverses"
    arr::slice nums out -1 -4 -1
    testframework::assert_equal "five four three" "$(arr::join out ' ')" "arr::slice negative step with bounds"

    # Empty results / Пустые результаты
    arr::slice nums out 3 3
    testframework::assert_equal "0" "${#out[@]}" "arr::slice empty range"
    arr::slice nums out 5 0
    testframework::assert_equal "0" "${#out[@]}" "arr::slice reversed range is empty"

    # Clamping / Ограничение границ
    arr::slice nums out -50 2
    testframework::assert_equal "zero one" "$(arr::join out ' ')" "arr::slice clamps start below zero"
    arr::slice nums out 4 99
    testframework::assert_equal "four five" "$(arr::join out ' ')" "arr::slice clamps end above length"

    # Invalid input / Некорректный ввод
    testframework::assert_false "arr::slice nums out '' '' 0" "arr::slice rejects step 0"
    testframework::assert_false "arr::slice nums out '' '' x" "arr::slice rejects non-numeric step"
    testframework::assert_false "arr::slice nums out a 2" "arr::slice rejects non-numeric start"

    # Empty source array / Пустой исходный массив
    local -a empty=()
    arr::slice empty out
    testframework::assert_equal "0" "${#out[@]}" "arr::slice on empty array"

    # arr::reverse / Разворот массива
    arr::reverse nums out
    testframework::assert_equal "five four three two one zero" "$(arr::join out ' ')" "arr::reverse"

    # str::slice / Слайсы строк
    testframework::assert_equal "ell" "$(str::slice "hello" 1 4)" "str::slice [1:4]"
    testframework::assert_equal "llo" "$(str::slice "hello" -3)" "str::slice [-3:]"
    testframework::assert_equal "olleh" "$(str::slice "hello" "" "" -1)" "str::slice step -1"
    testframework::assert_equal "hlo" "$(str::slice "hello" "" "" 2)" "str::slice step 2"
    testframework::assert_equal "" "$(str::slice "hello" 2 2)" "str::slice empty range"
    testframework::assert_equal "hello" "$(str::slice "hello")" "str::slice whole string"
    testframework::assert_false "str::slice 'hello' '' '' 0" "str::slice rejects step 0"
    testframework::assert_equal "cba" "$(str::reverse "abc")" "str::reverse"
}

# Test indexers, head/tail/drop, in-place ops, map and bs::slice
test_slicing_extras() {
    local -a nums=(zero one two three four five)

    # Indexers / Индексаторы
    testframework::assert_equal "three" "$(arr::get nums 3)" "arr::get positive index"
    testframework::assert_equal "five" "$(arr::get nums -1)" "arr::get negative index"
    testframework::assert_equal "four" "$(arr::get nums -2)" "arr::get negative index from end"
    testframework::assert_false "arr::get nums 99" "arr::get rejects out of bounds"
    testframework::assert_false "arr::get nums -99" "arr::get rejects negative out of bounds"
    testframework::assert_false "arr::get nums x" "arr::get rejects non-numeric index"
    testframework::assert_equal "zero" "$(arr::first nums)" "arr::first"
    testframework::assert_equal "five" "$(arr::last nums)" "arr::last"
    local -a empty_arr=()
    testframework::assert_false "arr::first empty_arr" "arr::first rejects empty array"
    testframework::assert_false "arr::last empty_arr" "arr::last rejects empty array"

    # head / tail / drop
    local -a out=()
    arr::head nums out 3
    testframework::assert_equal "zero one two" "$(arr::join out ' ')" "arr::head 3"
    arr::tail nums out 2
    testframework::assert_equal "four five" "$(arr::join out ' ')" "arr::tail 2"
    arr::tail nums out 0
    testframework::assert_equal "0" "${#out[@]}" "arr::tail 0 is empty"
    arr::drop nums out 4
    testframework::assert_equal "four five" "$(arr::join out ' ')" "arr::drop 4"
    arr::drop nums out 99
    testframework::assert_equal "0" "${#out[@]}" "arr::drop beyond length"
    testframework::assert_false "arr::head nums out x" "arr::head rejects non-numeric"
    testframework::assert_false "arr::tail nums out -1" "arr::tail rejects negative"

    # In-place: cut / splice / slice_inplace
    local -a a=(zero one two three four five)
    arr::cut a 1 4
    testframework::assert_equal "zero four five" "$(arr::join a ' ')" "arr::cut [1:4]"
    arr::cut a 0 0
    testframework::assert_equal "zero four five" "$(arr::join a ' ')" "arr::cut empty range"
    arr::cut a
    testframework::assert_equal "0" "${#a[@]}" "arr::cut whole array"

    local -a b=(zero one two three four five)
    arr::splice b 1 4 X Y
    testframework::assert_equal "zero X Y four five" "$(arr::join b ' ')" "arr::splice replace range"
    local -a c=(zero one two)
    arr::splice c 0 0 FIRST
    testframework::assert_equal "FIRST zero one two" "$(arr::join c ' ')" "arr::splice insert at front"
    arr::splice c 1 "" LAST
    testframework::assert_equal "FIRST LAST" "$(arr::join c ' ')" "arr::splice to end"

    local -a d=(zero one two three)
    arr::slice_inplace d 1 3
    testframework::assert_equal "one two" "$(arr::join d ' ')" "arr::slice_inplace [1:3]"
    local -a e=(zero one two three)
    arr::slice_inplace e "" "" -1
    testframework::assert_equal "three two one zero" "$(arr::join e ' ')" "arr::slice_inplace reverse"
    local -a f=(zero one two three)
    arr::slice_inplace f 2 2
    testframework::assert_equal "0" "${#f[@]}" "arr::slice_inplace empty range"

    # stdout mode / печать построчно
    testframework::assert_equal "$(printf 'one\ntwo\nthree')" "$(arr::slice nums '' 1 4)" "arr::slice stdout mode"

    # str::slice_to / str::chunk
    local r=""
    str::slice_to r "hello" 1 4
    testframework::assert_equal "ell" "${r}" "str::slice_to writes variable"
    str::slice_to r "hello" "" "" -1
    testframework::assert_equal "olleh" "${r}" "str::slice_to negative step"
    testframework::assert_false "str::slice_to r 'abc' '' '' 0" "str::slice_to rejects step 0"

    local -a chunks=()
    str::chunk "abcdef" chunks 2
    testframework::assert_equal "ab cd ef" "$(arr::join chunks ' ')" "str::chunk even"
    str::chunk "abcde" chunks 2
    testframework::assert_equal "ab cd e" "$(arr::join chunks ' ')" "str::chunk uneven"
    testframework::assert_false "str::chunk 'abc' chunks 0" "str::chunk rejects zero"
    testframework::assert_false "str::chunk 'abc' chunks x" "str::chunk rejects non-numeric"

    # Multibyte / мультибайт (только в UTF-8 локали)
    if [[ "${LANG:-}" == *UTF-8* ]] || [[ "${LC_ALL:-}" == *UTF-8* ]]; then
        testframework::assert_equal "мир" "$(str::slice 'привет мир' 7)" "str::slice multibyte"
        local mr=""
        str::slice_to mr "привет мир" 7
        testframework::assert_equal "мир" "${mr}" "str::slice_to multibyte"
    fi

    # Maps / Карты
    local -A m=([a]=1 [b]=2 [c]=3 [d]=4)
    testframework::assert_equal "4" "$(map::count m)" "map::count"

    local -a keys=() vals=()
    map::keys m keys
    map::values m vals
    testframework::assert_equal "4" "${#keys[@]}" "map::keys count"
    testframework::assert_equal "4" "${#vals[@]}" "map::values count"
    local -i idx
    local sync_ok=1
    for (( idx = 0; idx < 4; idx++ )); do
        [[ "${vals[idx]}" == "${m[${keys[idx]}]}" ]] || sync_ok=0
    done
    testframework::assert_true "'${sync_ok}' == '1'" "map::values stays in sync with map::keys"

    declare -A sub=()
    map::slice m sub 1 3
    testframework::assert_equal "2" "${#sub[@]}" "map::slice count"
    local sub_ok=1
    for key in "${!sub[@]}"; do
        [[ "${sub[$key]}" == "${m[$key]}" ]] || sub_ok=0
    done
    testframework::assert_true "'${sub_ok}' == '1'" "map::slice keeps key-value pairs"
    testframework::assert_false "map::slice m sub x y" "map::slice rejects non-numeric bounds"

    declare -A by=()
    map::slice_by_keys m by b d
    testframework::assert_equal "2" "${#by[@]}" "map::slice_by_keys count"
    testframework::assert_equal "2" "${by[b]}" "map::slice_by_keys value b"
    testframework::assert_equal "4" "${by[d]}" "map::slice_by_keys value d"

    # Unified bs::slice / Унифицированный слайс
    local -a ar=(zero one two)
    local -a orr=()
    bs::slice ar orr 1
    testframework::assert_equal "one two" "$(arr::join orr ' ')" "bs::slice on array"
    local sv="hello world"
    local ov=""
    bs::slice sv ov 0 5
    testframework::assert_equal "hello" "${ov}" "bs::slice on string"
    testframework::assert_equal "world" "$(bs::slice sv '' 6)" "bs::slice on string to stdout"
    declare -A mp=([k1]=v1 [k2]=v2 [k3]=v3)
    declare -A op=()
    bs::slice mp op 0 1
    testframework::assert_equal "1" "${#op[@]}" "bs::slice on map"
    testframework::assert_false "bs::slice not_defined_var_xyz out" "bs::slice rejects undefined"
}

# Test iterators: map / filter / reduce / find / index_of / range / unpack / chunk
test_iterators() {
    local -a nums=(1 2 3 4 5)

    # arr::map
    double() { printf '%s\n' "$(( $1 * 2 ))"; }
    local -a out=()
    arr::map nums out double
    testframework::assert_equal "2 4 6 8 10" "$(arr::join out ' ')" "arr::map doubles"
    prefix() { printf '%s%s\n' "$2" "$1"; }
    arr::map nums out prefix "n"
    testframework::assert_equal "n1 n2 n3 n4 n5" "$(arr::join out ' ')" "arr::map passes extra args"
    testframework::assert_false "arr::map nums out not_a_fn_xyz" "arr::map rejects missing callback"

    # arr::filter
    is_even() { (( $1 % 2 == 0 )); }
    arr::filter nums out is_even
    testframework::assert_equal "2 4" "$(arr::join out ' ')" "arr::filter keeps even"
    is_gt() { (( $1 > $2 )); }
    arr::filter nums out is_gt 3
    testframework::assert_equal "4 5" "$(arr::join out ' ')" "arr::filter passes extra args"
    arr::filter nums out is_even 2>/dev/null # ensure predicate output suppressed
    testframework::assert_equal "2 4" "$(arr::join out ' ')" "arr::filter suppresses predicate output"

    # arr::reduce
    add2() { printf '%s\n' "$(( $1 + $2 ))"; }
    testframework::assert_equal "15" "$(arr::reduce nums 0 add2)" "arr::reduce sums"
    concat() { printf '%s' "${1}${2}"; }
    local -a words=(a b c)
    testframework::assert_equal "abc" "$(arr::reduce words "" concat)" "arr::reduce concatenates"

    # arr::find / arr::index_of
    big() { (( $1 >= 4 )); }
    never() { return 1; }
    testframework::assert_equal "4" "$(arr::find nums big)" "arr::find first match"
    testframework::assert_false "arr::find nums never" "arr::find no match"
    testframework::assert_equal "2" "$(arr::index_of nums 3)" "arr::index_of finds"
    testframework::assert_false "arr::index_of nums 99" "arr::index_of missing"

    # arr::range
    local -a r=()
    arr::range r 1 6
    testframework::assert_equal "1 2 3 4 5" "$(arr::join r ' ')" "arr::range 1 6"
    arr::range r 0 10 3
    testframework::assert_equal "0 3 6 9" "$(arr::join r ' ')" "arr::range step 3"
    arr::range r 5 0 -2
    testframework::assert_equal "5 3 1" "$(arr::join r ' ')" "arr::range negative step"
    arr::range r "" 3
    testframework::assert_equal "0 1 2" "$(arr::join r ' ')" "arr::range default start"
    testframework::assert_false "arr::range r 1 5 0" "arr::range rejects step 0"
    testframework::assert_false "arr::range r 1 x" "arr::range rejects non-numeric end"

    # arr::unpack
    local -a row=(host 8080 tcp)
    local h="" p="" proto=""
    arr::unpack row h p proto
    testframework::assert_equal "host" "${h}" "arr::unpack first var"
    testframework::assert_equal "8080" "${p}" "arr::unpack second var"
    testframework::assert_equal "tcp" "${proto}" "arr::unpack third var"
    local -a short=(only)
    local s1="x" s2="x"
    arr::unpack short s1 s2
    testframework::assert_equal "only" "${s1}" "arr::unpack present element"
    testframework::assert_equal "" "${s2}" "arr::unpack missing element is empty"

    # arr::chunk
    local -a items=(a b c d e f g)
    declare -A batches=()
    arr::chunk items batches 3
    testframework::assert_equal "3" "${#batches[@]}" "arr::chunk count"
    testframework::assert_equal "$(printf 'a\nb\nc')" "${batches[0]}" "arr::chunk first chunk"
    testframework::assert_equal "$(printf 'g')" "${batches[2]}" "arr::chunk last chunk"
    testframework::assert_false "arr::chunk items batches 0" "arr::chunk rejects zero size"
    testframework::assert_false "arr::chunk items batches x" "arr::chunk rejects non-numeric"
    local -a no_items=()
    declare -A empty_batches=()
    arr::chunk no_items empty_batches 3
    testframework::assert_equal "0" "${#empty_batches[@]}" "arr::chunk on empty array"
}

# Test each / concat / pick / omit / strict slices / unwrap / expect / decorate
test_patterns() {
    # arr::each / map::each
    local -a nums=(1 2 3)
    local -a seen=()
    collect() { seen+=("$1"); }
    arr::each nums collect
    testframework::assert_equal "1 2 3" "$(arr::join seen ' ')" "arr::each visits every element"
    testframework::assert_false "arr::each nums not_a_fn_xyz" "arr::each rejects missing callback"

    declare -A m2=([a]=1 [b]=2)
    local total=0
    add_val() { total=$(( total + $2 )); }
    map::each m2 add_val
    testframework::assert_equal "3" "${total}" "map::each passes key and value"

    # arr::concat
    local -a a=(1 2) b=(3 4) c=()
    local -a out=()
    arr::concat out a b c
    testframework::assert_equal "1 2 3 4" "$(arr::join out ' ')" "arr::concat merges arrays"
    arr::concat out
    testframework::assert_equal "0" "${#out[@]}" "arr::concat no sources is empty"

    # map::pick / map::omit
    declare -A m3=([a]=1 [b]=2 [c]=3 [d]=4)
    declare -A picked=()
    map::pick m3 picked b d
    testframework::assert_equal "2" "${#picked[@]}" "map::pick count"
    testframework::assert_equal "2" "${picked[b]}" "map::pick value b"
    declare -A omitted=()
    map::omit m3 omitted a b
    testframework::assert_equal "2" "${#omitted[@]}" "map::omit count"
    testframework::assert_equal "3" "${omitted[c]}" "map::omit keeps c"
    testframework::assert_false "map::has omitted a" "map::omit removes a"

    # strict slices
    local -a sn=(zero one two three)
    local -a so=()
    arr::slice_strict sn so 1 3
    testframework::assert_equal "one two" "$(arr::join so ' ')" "arr::slice_strict in bounds"
    testframework::assert_false "arr::slice_strict sn so 0 99" "arr::slice_strict rejects high end"
    testframework::assert_false "arr::slice_strict sn so -99" "arr::slice_strict rejects low start"
    testframework::assert_false "arr::slice_strict sn so x 2" "arr::slice_strict rejects non-numeric"
    arr::slice_strict sn so -2
    testframework::assert_equal "two three" "$(arr::join so ' ')" "arr::slice_strict negative in bounds"
    testframework::assert_equal "ell" "$(str::slice_strict "hello" 1 4)" "str::slice_strict in bounds"
    testframework::assert_false "str::slice_strict 'hello' 0 99" "str::slice_strict rejects high end"
    testframework::assert_false "str::slice_strict 'hello' -99" "str::slice_strict rejects low start"
    testframework::assert_equal "olleh" "$(str::slice_strict "hello" "" "" -1)" "str::slice_strict reverse"

    # bs::unwrap / bs::expect
    local v="hello"
    testframework::assert_equal "hello" "$(bs::unwrap v)" "bs::unwrap prints value"
    local e=""
    testframework::assert_false "bs::unwrap e" "bs::unwrap rejects empty"
    testframework::assert_false "bs::unwrap not_defined_var_xyz" "bs::unwrap rejects unset"
    testframework::assert_false "bs::expect e 'must be set'" "bs::expect rejects with message"
    testframework::assert_equal "hello" "$(bs::expect v 'must be set')" "bs::expect prints value"

    # bs::decorate
    test::hello() { printf 'hello %s\n' "$1"; }
    test::deco() {
        local orig="$1"
        shift
        printf '>>> '
        "${orig}" "$@"
    }
    bs::decorate test::hello test::deco
    testframework::assert_equal ">>> hello world" "$(test::hello world)" "bs::decorate wraps call"
    testframework::assert_equal "hello world" "$(bs::__orig_test_hello world)" "bs::decorate keeps original"
    testframework::assert_command "is::function bs::__orig_test_hello" "bs::decorate saves original as bs::__orig_"
    testframework::assert_false "bs::decorate not_a_fn_xyz test::deco" "bs::decorate rejects missing function"
    testframework::assert_false "bs::decorate test::hello 'bad name'" "bs::decorate rejects invalid name"
}

# Test map basics: get / set / remove / merge / invert
test_map_basics() {
    declare -A m=([a]=1 [b]=2 [c]=3)

    testframework::assert_equal "2" "$(map::get m b)" "map::get finds key"
    testframework::assert_equal "8080" "$(map::get m port 8080)" "map::get returns default"
    testframework::assert_false "map::get m missing" "map::get without default returns 1"
    local d=""
    d="$(map::get m missing  || true)"
    testframework::assert_equal "" "${d}" "map::get without default prints nothing"

    map::set m d 4
    testframework::assert_equal "4" "${m[d]}" "map::set stores value"
    map::set m d 5
    testframework::assert_equal "5" "${m[d]}" "map::set overwrites value"

    map::remove m d
    testframework::assert_false "map::has m d" "map::remove deletes key"
    map::remove m a b
    testframework::assert_equal "1" "${#m[@]}" "map::remove multiple keys"
    testframework::assert_command "map::has m c" "map::remove keeps others"

    declare -A base=([host]=h [port]=80)
    declare -A over=([port]=8080 [user]=u)
    map::merge base over
    testframework::assert_equal "8080" "${base[port]}" "map::merge overwrites"
    testframework::assert_equal "u" "${base[user]}" "map::merge adds"
    declare -A new_dst=()
    map::merge new_dst base
    testframework::assert_equal "3" "${#new_dst[@]}" "map::merge creates destination"

    declare -A inv=()
    map::invert m inv
    testframework::assert_equal "c" "${inv[3]}" "map::invert value becomes key"
}

# Test small stdlib: sum / min / max / uniq / pad / repeat / lines / words
test_small_stdlib() {
    local -a nums=(3 1 4 1 5)
    testframework::assert_equal "14" "$(arr::sum nums)" "arr::sum"
    testframework::assert_equal "1" "$(arr::min nums)" "arr::min"
    testframework::assert_equal "5" "$(arr::max nums)" "arr::max"
    local -a empty=()
    testframework::assert_false "arr::min empty" "arr::min rejects empty"
    testframework::assert_false "arr::max empty" "arr::max rejects empty"
    local -a mixed=(1 a)
    testframework::assert_false "arr::sum mixed" "arr::sum rejects non-numeric"
    testframework::assert_false "arr::min mixed" "arr::min rejects non-numeric"

    local -a dup=(x y x z y x)
    local -a uniq_out=()
    arr::uniq dup uniq_out
    testframework::assert_equal "x y z" "$(arr::join uniq_out ' ')" "arr::uniq keeps first occurrence"

    testframework::assert_equal "abc" "$(str::pad "abc" 3)" "str::pad no padding needed"
    testframework::assert_equal "abc  " "$(str::pad "abc" 5)" "str::pad with spaces"
    testframework::assert_equal "abc.." "$(str::pad "abc" 5 ".")" "str::pad custom char"
    testframework::assert_false "str::pad 'abc' 5 '..'" "str::pad rejects multi-char"

    testframework::assert_equal "" "$(str::repeat "ab" 0)" "str::repeat zero"
    testframework::assert_equal "ababab" "$(str::repeat "ab" 3)" "str::repeat"
    testframework::assert_false "str::repeat 'ab' x" "str::repeat rejects non-numeric"

    local -a lines_out=()
    str::lines "$(printf 'a\nb\nc')" lines_out
    testframework::assert_equal "3" "${#lines_out[@]}" "str::lines count"
    testframework::assert_equal "b" "${lines_out[1]}" "str::lines middle line"
    str::lines "$(printf 'x\n\nz')" lines_out
    testframework::assert_equal "x" "${lines_out[0]}" "str::lines keeps empty line"
    testframework::assert_equal "" "${lines_out[1]}" "str::lines empty line is empty"
    testframework::assert_equal "z" "${lines_out[2]}" "str::lines after empty line"
    str::lines "" lines_out
    testframework::assert_equal "0" "${#lines_out[@]}" "str::lines empty string"

    local -a words_out=()
    str::words "  a   b  c " words_out
    testframework::assert_equal "3" "${#words_out[@]}" "str::words count"
    testframework::assert_equal "a b c" "$(arr::join words_out ' ')" "str::words splits on whitespace"
    str::words "" words_out
    testframework::assert_equal "0" "${#words_out[@]}" "str::words empty string"
}

# Test arr::from_lines reads stdin into an array
test_from_lines() {
    local -a lines=()
    arr::from_lines lines <<'EOF'
first
second
third
EOF
    testframework::assert_equal "3" "${#lines[@]}" "from_lines reads heredoc"
    testframework::assert_equal "second" "${lines[1]}" "from_lines preserves order"

    local -a pids=()
    arr::from_lines pids < <(printf 'a\nb\n')
    testframework::assert_equal "2" "${#pids[@]}" "from_lines works with process substitution"
}

# Test is:: predicate family
test_is_predicates() {
    testframework::assert_command "is::empty ''" "is::empty on empty string"
    testframework::assert_false "is::empty 'x'" "is::empty on non-empty"
    testframework::assert_command "is::not_empty 'x'" "is::not_empty on non-empty"
    testframework::assert_false "is::not_empty ''" "is::not_empty on empty"

    local tmp_file
    tmp_file="$(mktemp)"
    testframework::assert_command "is::exists '${tmp_file}'" "is::exists finds file"
    testframework::assert_command "is::file '${tmp_file}'" "is::file on regular file"
    testframework::assert_false "is::dir '${tmp_file}'" "is::dir rejects file"
    testframework::assert_command "is::readable '${tmp_file}'" "is::readable"
    testframework::assert_false "is::file_not_empty '${tmp_file}'" "is::file_not_empty on empty file"

    printf 'data' > "${tmp_file}"
    testframework::assert_command "is::file_not_empty '${tmp_file}'" "is::file_not_empty on filled file"

    local tmp_link="${tmp_file}.link"
    ln -s "${tmp_file}" "${tmp_link}"
    testframework::assert_command "is::symlink '${tmp_link}'" "is::symlink finds link"

    testframework::assert_command "is::dir /tmp" "is::dir on directory"
    testframework::assert_command "is::executable /bin/sh" "is::executable on /bin/sh"
    testframework::assert_false "is::exists '/definitely/not/here'" "is::exists rejects missing path"

    testframework::assert_command "is::number 42" "is::number on digits"
    testframework::assert_false "is::number '4x'" "is::number rejects mixed"

    testframework::assert_command "is::command bash" "is::command finds bash"
    testframework::assert_false "is::command not-a-real-cmd-xyz" "is::command rejects unknown"

    testframework::assert_command "is::function bs::guard" "is::function finds bs::guard"

    rm -f "${tmp_file}" "${tmp_link}"
}

main() {
    print_header "Core Lang Unit Tests / Модульные тесты core/lang"

    testframework::init

    testframework::section "Introspection / Интроспекция"
    test_func_name
    test_call_stack
    test_type_predicates

    testframework::section "Strings / Строки"
    test_strings

    testframework::section "Collections / Коллекции"
    test_arrays
    test_maps
    test_from_lines
    test_map_basics

    testframework::section "Slicing / Слайсы"
    test_slicing
    test_slicing_extras

    testframework::section "Iterators / Итераторы"
    test_iterators

    testframework::section "Patterns / Паттерны"
    test_patterns

    testframework::section "Stdlib / Стандартные функции"
    test_small_stdlib

    testframework::section "is:: predicates / Предикаты is::"
    test_is_predicates

    testframework::summary
}

main "$@"
