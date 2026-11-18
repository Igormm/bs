#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testobjectportableunit.sh — core/object.sh (the object model) under dash, ash, ksh, mksh, zsh and bash
# tests/unit/testobjectportableunit.sh — core/object.sh (объектная модель) под dash, ash, ksh, mksh, zsh и bash
#
# core/object.sh is "@shell posix": classes, instances, methods, properties, watchers, contracts,
# inheritance, delegation, identity and lifetime must give the same answers in every shell.
# core/object.sh — "@shell posix": классы, экземпляры, методы, свойства, наблюдатели, контракты,
# наследование, делегирование, идентичность и время жизни обязаны давать одинаковые ответы в любой оболочке.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly OBJECT_SH="${BS_PROJECT_ROOT}/core/object.sh"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

T=""

# probe <shell> <snippet> — слой, prereq, data и object подключены, затем snippet (stdout+stderr)
# probe <shell> <snippet> — the layer, prereq, data and object are sourced, then the snippet (stdout+stderr)
probe() {
    local -r sh_bin="$1" snippet="$2"
    local f
    : > "${T}/probe.sh"
    for f in bootstrap/shell.sh core/prereq.sh core/data.sh core/object.sh; do
        printf 'BS_CURRENT_FILE="%s/%s"\n. "%s/%s"\n' "${BS_PROJECT_ROOT}" "${f}" "${BS_PROJECT_ROOT}" "${f}" >> "${T}/probe.sh"
    done
    printf '%s\n' "${snippet}" >> "${T}/probe.sh"
    env -i HOME="${T}/h" PATH="/usr/bin:/bin" "${sh_bin}" "${T}/probe.sh" 2>&1
}

eq() { testframework::assert_equal "$1" "$2" "$3" || true; }

# Общий сниппет объявления Counter / The shared Counter declaration snippet
readonly COUNTER='
bs_obj_class Counter
bs_obj_field Counter count 0
bs_obj_field Counter secret s0
bs_obj_private Counter secret
bs_obj_field Counter born at
bs_obj_readonly Counter born
bs_obj_shared Counter instances 0
bs_obj_const Counter MAX 100
bs_obj_method Counter inc counter_inc
bs_obj_property Counter double counter_double
bs_obj_watch Counter count counter_watch
bs_obj_type_method Counter from counter_from
bs_obj_contract Counter inc
counter_inc() { v=$(bs_obj_get "$1" count); bs_obj_set "$1" count "$((v + 1))"; bs_obj_get "$1" count; }
counter_double() { v=$(bs_obj_get "$1" count); printf "%s\n" "$((v * 2))"; }
counter_watch() { printf "watch:%s:%s>%s\n" "$2" "$3" "$4"; }
counter_from() { bs_obj_new_to "$2" "$1" count="$3"; }
'

test_parses_and_lints() {
    local sh_bin
    while IFS= read -r sh_bin; do
        testframework::assert_command "'${sh_bin}' -n '${OBJECT_SH}'" "object.sh parses in ${sh_bin##*/}" || true
    done < <(testframework::posix_shells)
    if utils::has shellcheck; then
        testframework::assert_command "shellcheck -s sh --severity=error '${OBJECT_SH}'" "shellcheck -s sh has no errors for core/object.sh" || true
    fi
    testframework::assert_command "grep -q '^# @shell posix' '${OBJECT_SH}'" "core/object.sh is declared @shell posix" || true
}

test_class_and_fields() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "o1|Counter|0|at" "$(probe "${sh_bin}" "${COUNTER}"'
bs_obj_new_to c Counter
printf "%s|%s|%s|%s" "$c" "$(bs_obj_class_of "$c")" "$(bs_obj_get "$c" count)" "$(bs_obj_get "$c" born)"')" "${sh_name}: new_to, class_of, defaults"
        eq "5" "$(probe "${sh_bin}" "${COUNTER}"'bs_obj_new_to c Counter count=5; bs_obj_get "$c" count')" "${sh_name}: field=value pair"
        eq "born count secret" "$(probe "${sh_bin}" "${COUNTER}"'bs_obj_new_to c Counter; bs_obj_fields "$c" | sort | tr "\n" " " | sed "s/ $//"')" "${sh_name}: fields list"
        eq "rc=0 rc=1" "$(probe "${sh_bin}" "${COUNTER}"'bs_obj_new_to c Counter; bs_obj_has "$c" count; printf "rc=%s " "$?"; bs_obj_has "$c" nope; printf "rc=%s" "$?"')" "${sh_name}: has"
        eq "rc=1" "$(probe "${sh_bin}" "${COUNTER}"'bs_obj_new_to c Counter; bs_obj_get "$c" nope 2>/dev/null; echo rc=$?')" "${sh_name}: unknown field is 1"
        eq "rc=1" "$(probe "${sh_bin}" 'bs_obj_new_to c NoSuch 2>/dev/null; echo rc=$?')" "${sh_name}: unknown class is 1"
        eq "rc=2" "$(probe "${sh_bin}" 'bs_obj_class Counter; bs_obj_class Counter 2>/dev/null; echo rc=$?')" "${sh_name}: redeclaration is 2"
        eq "rc=2" "$(probe "${sh_bin}" 'bs_obj_class "bad name" 2>/dev/null; echo rc=$?')" "${sh_name}: bad class name is 2"
        eq "rc=2" "$(probe "${sh_bin}" 'bs_obj_class "a;touch '"${T}"'/pwned" 2>/dev/null; echo rc=$?; [ -e '"${T}"'/pwned ] && echo LEAK')" "${sh_name}: injection in a class name is refused"
        eq "rc=2" "$(probe "${sh_bin}" "${COUNTER}"'bs_obj_new_to c Counter "\$(id)=1" >/dev/null 2>&1; echo rc=$?')" "${sh_name}: injection in a field name is refused"
        eq '$(id)' "$(probe "${sh_bin}" "${COUNTER}"'bs_obj_new_to c Counter "count=\$(id)" >/dev/null; bs_obj_get "$c" count')" "${sh_name}: a value is data, not code"
        eq "a b|it's|*|Привет" "$(probe "${sh_bin}" '
bs_obj_class V
bs_obj_field V x ""
bs_obj_new_to v V "x=a b"
printf "%s|" "$(bs_obj_get "$v" x)"
bs_obj_set "$v" x "it'"'"'s"
printf "%s|" "$(bs_obj_get "$v" x)"
bs_obj_set "$v" x "*"
printf "%s|" "$(bs_obj_get "$v" x)"
bs_obj_set "$v" x "Привет"
bs_obj_get "$v" x')" "${sh_name}: hard values survive (space, quote, glob, Cyrillic)"
    done < <(testframework::posix_shells)
}

test_methods() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "1|watch:count:1>2|1" "$(probe "${sh_bin}" "${COUNTER}"'
bs_obj_new_to c Counter
bs_obj_call "$c" inc >/dev/null
printf "%s|" "$(bs_obj_get "$c" count)"
bs_obj_call "$c" inc | grep watch | tr -d "\n"
printf "|%s" "$(bs_obj_get "$c" count)"')" "${sh_name}: instance method, watcher fires"
        eq "rc=7" "$(probe "${sh_bin}" '
bs_obj_class R
bs_obj_method R fail r_fail
r_fail() { return 7; }
bs_obj_new_to r R
bs_obj_call "$r" fail; echo rc=$?')" "${sh_name}: the method status propagates"
        eq "args:2:x y z" "$(probe "${sh_bin}" '
bs_obj_class A
bs_obj_method A echoargs a_echo
a_echo() { shift; printf "args:%s:%s" "$#" "$*"; }
bs_obj_new_to a A
bs_obj_call "$a" echoargs "x y" z')" "${sh_name}: arguments reach the method (ID first)"
        eq "T|from" "$(probe "${sh_bin}" '
bs_obj_class T
bs_obj_type_method T name t_name
t_name() { printf "%s|from" "$1"; }
bs_obj_type_call T name')" "${sh_name}: type method receives the class"
        eq "rc=1" "$(probe "${sh_bin}" "${COUNTER}"'bs_obj_new_to c Counter; bs_obj_call "$c" nosuch 2>/dev/null; echo rc=$?')" "${sh_name}: no method is 1"
        eq "rc=1" "$(probe "${sh_bin}" '
bs_obj_class M
bs_obj_method M gone m_gone
bs_obj_new_to m M
bs_obj_call "$m" gone 2>/dev/null; echo rc=$?')" "${sh_name}: a missing function is 1"
        eq "rc=2" "$(probe "${sh_bin}" "${COUNTER}"'bs_obj_new_to c Counter; bs_obj_call "$c" "bad method" 2>/dev/null; echo rc=$?')" "${sh_name}: bad method name is 2"
    done < <(testframework::posix_shells)
}

test_init_and_factory() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "3|7" "$(probe "${sh_bin}" '
bs_obj_class I
bs_obj_field I n 0
bs_obj_method I init i_init
i_init() { bs_obj_set "$1" n 3; }
bs_obj_new_to i I
printf "%s|" "$(bs_obj_get "$i" n)"
bs_obj_new_to j I n=7
bs_obj_get "$j" n')" "${sh_name}: init runs, pairs have the final word"
        eq "9" "$(probe "${sh_bin}" "${COUNTER}"'bs_obj_type_call Counter from f 9; bs_obj_get "$f" count')" "${sh_name}: factory type method"
        eq "rc=4|0" "$(probe "${sh_bin}" '
bs_obj_class F
bs_obj_field F x 0
bs_obj_method F init f_init
f_init() { return 4; }
bs_obj_new_to f F 2>/dev/null; printf "rc=%s|" "$?"
bs_obj_count')" "${sh_name}: a failed init leaves no object"
        eq "rc=2|0" "$(probe "${sh_bin}" '
bs_obj_class P
bs_obj_field P x 0
bs_obj_new_to p P notapair 2>/dev/null; printf "rc=%s|" "$?"
bs_obj_count')" "${sh_name}: a bad pair leaves no object"
        eq "rc=1|0" "$(probe "${sh_bin}" '
bs_obj_class P
bs_obj_field P x 0
bs_obj_new_to p P nope=1 2>/dev/null; printf "rc=%s|" "$?"
bs_obj_count')" "${sh_name}: an unknown field in a pair leaves no object"
        eq "5|2" "$(probe "${sh_bin}" '
bs_obj_class Inner
bs_obj_field Inner k 0
bs_obj_class Outer
bs_obj_field Outer n 0
bs_obj_method Outer init o_init
o_init() { bs_obj_new_to tmp Inner; bs_obj_set "$tmp" k 1; }
bs_obj_new_to o Outer n=5
printf "%s|%s" "$(bs_obj_get "$o" n)" "$(bs_obj_count)"')" "${sh_name}: an init nesting new keeps the pairs on the right object"
    done < <(testframework::posix_shells)
}

test_privacy_and_readonly() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "rc=3 rc=3 s0" "$(probe "${sh_bin}" "${COUNTER}"'
bs_obj_new_to c Counter
bs_obj_get "$c" secret 2>/dev/null; printf "rc=%s " "$?"
bs_obj_set "$c" secret x 2>/dev/null; printf "rc=%s " "$?"
bs_obj_raw_get "$c" secret')" "${sh_name}: private refuses the public API, raw works"
        eq "rc=3|now" "$(probe "${sh_bin}" "${COUNTER}"'
bs_obj_new_to c Counter born=now
bs_obj_set "$c" born later 2>/dev/null; printf "rc=%s|" "$?"
bs_obj_get "$c" born')" "${sh_name}: readonly refuses after creation"
        eq "set-in-init" "$(probe "${sh_bin}" '
bs_obj_class RI
bs_obj_field RI stamp none
bs_obj_readonly RI stamp
bs_obj_method RI init ri_init
ri_init() { bs_obj_set "$1" stamp set-in-init; }
bs_obj_new_to r RI
bs_obj_get "$r" stamp')" "${sh_name}: readonly is writable inside init"
        eq "100|rc=3|2" "$(probe "${sh_bin}" "${COUNTER}"'
printf "%s|" "$(bs_obj_type_get Counter MAX)"
bs_obj_type_set Counter MAX 5 2>/dev/null; printf "rc=%s|" "$?"
bs_obj_type_set Counter instances 2
bs_obj_type_get Counter instances')" "${sh_name}: constants refuse writes, shared fields accept"
        eq "rc=1" "$(probe "${sh_bin}" "${COUNTER}"'bs_obj_type_get Counter nope 2>/dev/null; echo rc=$?')" "${sh_name}: unknown type member is 1"
    done < <(testframework::posix_shells)
}

test_properties() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "6" "$(probe "${sh_bin}" "${COUNTER}"'bs_obj_new_to c Counter count=3; bs_obj_get "$c" double')" "${sh_name}: computed getter"
        eq "10|watch:n:10>20" "$(probe "${sh_bin}" '
bs_obj_class SP
bs_obj_field SP n 0
bs_obj_property SP n sp_get sp_set
bs_obj_watch SP n sp_watch
sp_get() { bs_obj_raw_get "$1" n; }
sp_set() { bs_obj_raw_set "$1" n "$2"; }
sp_watch() { printf "watch:%s:%s>%s\n" "$2" "$3" "$4"; }
bs_obj_new_to s SP
bs_obj_set "$s" n 10 >/dev/null
printf "%s|" "$(bs_obj_get "$s" n)"
bs_obj_set "$s" n 20 | grep watch | tr -d "\n"')" "${sh_name}: setter stores, watcher sees old and new"
        eq "rc=3" "$(probe "${sh_bin}" '
bs_obj_class RP
bs_obj_field RP n 0
bs_obj_property RP n rp_get
bs_obj_readonly RP n
rp_get() { bs_obj_raw_get "$1" n; }
bs_obj_new_to r RP
bs_obj_set "$r" n 5 2>/dev/null; echo rc=$?')" "${sh_name}: a getter-only readonly property refuses writes"
    done < <(testframework::posix_shells)
}

test_inheritance_and_contract() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "yes|1|e" "$(probe "${sh_bin}" "${COUNTER}"'
bs_obj_class Loud Counter
bs_obj_field Loud extra e
bs_obj_new_to l Loud
bs_obj_is_a "$l" Counter && printf "yes|"
bs_obj_call "$l" inc >/dev/null
printf "%s|%s" "$(bs_obj_get "$l" count)" "$(bs_obj_get "$l" extra)"')" "${sh_name}: child inherits methods and fields"
        eq "child" "$(probe "${sh_bin}" '
bs_obj_class B
bs_obj_field B who base
bs_obj_method B init b_init
b_init() { bs_obj_set "$1" who base; }
bs_obj_class D B
bs_obj_method D init d_init
d_init() { bs_obj_set "$1" who child; }
bs_obj_new_to d D
bs_obj_get "$d" who')" "${sh_name}: the child overrides init"
        eq "rc=1|rc=3|0" "$(probe "${sh_bin}" '
bs_obj_class C
bs_obj_contract C must
bs_obj_check C >/dev/null; printf "rc=%s|" "$?"
bs_obj_new_to c C 2>/dev/null; printf "rc=%s|" "$?"
bs_obj_count')" "${sh_name}: an unfulfilled contract blocks creation"
        eq "ok" "$(probe "${sh_bin}" '
bs_obj_class C
bs_obj_contract C must
bs_obj_class D C
bs_obj_method D must d_must
d_must() { :; }
bs_obj_check D && bs_obj_new_to d D >/dev/null && printf ok')" "${sh_name}: an inherited contract is fulfilled by the child"
        eq "rc=2" "$(probe "${sh_bin}" 'bs_obj_class A; bs_obj_class B A; bs_obj_class A B 2>/dev/null; echo rc=$?')" "${sh_name}: a parent cannot be redeclared (cycles are impossible)"
        eq "rc=1" "$(probe "${sh_bin}" 'bs_obj_class X Nope 2>/dev/null; echo rc=$?')" "${sh_name}: an unknown parent is 1"
        eq "base" "$(probe "${sh_bin}" '
bs_obj_class B
bs_obj_shared B tag base
bs_obj_class D B
bs_obj_type_get D tag')" "${sh_name}: type members are inherited"
    done < <(testframework::posix_shells)
}

test_delegation() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "2" "$(probe "${sh_bin}" "${COUNTER}"'
bs_obj_class Box
bs_obj_field Box inner ""
bs_obj_delegate Box inner
bs_obj_new_to b Box
bs_obj_new_to c Counter
bs_obj_raw_set "$b" inner "$c"
bs_obj_call "$b" inc >/dev/null
bs_obj_call "$b" inc >/dev/null
bs_obj_get "$c" count')" "${sh_name}: composition delegates the call"
        eq "own" "$(probe "${sh_bin}" "${COUNTER}"'
bs_obj_class Box
bs_obj_field Box inner ""
bs_obj_delegate Box inner
bs_obj_method Box inc box_inc
box_inc() { printf own; }
bs_obj_new_to b Box
bs_obj_new_to c Counter
bs_obj_raw_set "$b" inner "$c"
bs_obj_call "$b" inc')" "${sh_name}: the own method wins over delegation"
        eq "rc=1" "$(probe "${sh_bin}" '
bs_obj_class Box
bs_obj_field Box inner ""
bs_obj_delegate Box inner
bs_obj_new_to b Box
bs_obj_call "$b" nosuch 2>/dev/null; echo rc=$?')" "${sh_name}: an empty delegation field is skipped"
        eq "deep" "$(probe "${sh_bin}" '
bs_obj_class L1
bs_obj_field L1 next ""
bs_obj_delegate L1 next
bs_obj_class L2
bs_obj_field L2 next ""
bs_obj_delegate L2 next
bs_obj_class L3
bs_obj_method L3 hit l3_hit
l3_hit() { printf deep; }
bs_obj_new_to a L1
bs_obj_new_to b L2
bs_obj_new_to c L3
bs_obj_raw_set "$a" next "$b"
bs_obj_raw_set "$b" next "$c"
bs_obj_call "$a" hit')" "${sh_name}: delegation chains"
        eq "second" "$(probe "${sh_bin}" '
bs_obj_class Empty
bs_obj_class Target
bs_obj_method Target hit t_hit
t_hit() { printf second; }
bs_obj_class Box
bs_obj_field Box first ""
bs_obj_field Box second ""
bs_obj_delegate Box first
bs_obj_delegate Box second
bs_obj_new_to e Empty
bs_obj_new_to t Target
bs_obj_new_to b Box
bs_obj_raw_set "$b" first "$e"
bs_obj_raw_set "$b" second "$t"
bs_obj_call "$b" hit')" "${sh_name}: a failed delegation tries the next field (outer state survives)"
        eq "w:inner:m:0>7|w:outer:n:0>5|" "$(probe "${sh_bin}" '
bs_obj_class N
bs_obj_field N n 0
bs_obj_field N m 0
bs_obj_property N n n_get n_set
bs_obj_watch N n n_watch
bs_obj_watch N m m_watch
n_get() { bs_obj_raw_get "$1" n; }
n_set() { bs_obj_raw_set "$1" n "$2"; bs_obj_set "$1" m 7; }
n_watch() { printf "w:outer:%s:%s>%s|" "$2" "$3" "$4"; }
m_watch() { printf "w:inner:%s:%s>%s\n" "$2" "$3" "$4"; }
bs_obj_new_to x N
bs_obj_set "$x" n 5 | tr "\n" "|"')" "${sh_name}: a setter nesting another set keeps the outer watcher right"
        eq "0" "$(probe "${sh_bin}" '
bs_obj_class Inner
bs_obj_class Outer
bs_obj_method Outer destroy o_destroy
o_destroy() { bs_obj_new_to tmp Inner; bs_obj_destroy "$tmp"; }
bs_obj_new_to o Outer
bs_obj_destroy "$o"
bs_obj_count')" "${sh_name}: a destroy method nesting new/destroy still tears the object down"
    done < <(testframework::posix_shells)
}

test_identity_and_lifetime() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "rc=0 rc=1 rc=0 rc=1" "$(probe "${sh_bin}" "${COUNTER}"'
bs_obj_new_to a Counter
bs_obj_new_to b Counter
bs_obj_same "$a" "$a"; printf "rc=%s " "$?"
bs_obj_same "$a" "$b"; printf "rc=%s " "$?"
bs_obj_equal "$a" "$b"; printf "rc=%s " "$?"
bs_obj_set "$b" count 9 >/dev/null
bs_obj_equal "$a" "$b"; printf "rc=%s" "$?"')" "${sh_name}: identity vs content equality"
        eq "rc=1" "$(probe "${sh_bin}" '
bs_obj_class A
bs_obj_class B
bs_obj_new_to a A
bs_obj_new_to b B
bs_obj_equal "$a" "$b" 2>/dev/null; echo rc=$?')" "${sh_name}: different classes are not equal"
        eq "2|bye|1|rc=1|bye|0" "$(probe "${sh_bin}" '
bs_obj_class D
bs_obj_method D destroy d_destroy
d_destroy() { printf "bye|"; }
bs_obj_new_to a D
bs_obj_new_to b D
bs_obj_count | tr "\n" "|"
bs_obj_destroy "$a"
bs_obj_count | tr "\n" "|"
bs_obj_alive "$a"; printf "rc=%s|" "$?"
bs_obj_destroy_all
bs_obj_count')" "${sh_name}: destroy runs the method, destroy_all cleans up"
        eq "rc=1" "$(probe "${sh_bin}" 'bs_obj_destroy o999 2>/dev/null; echo rc=$?')" "${sh_name}: destroying a stranger is 1"
        eq "rc=1" "$(probe "${sh_bin}" 'bs_obj_get o999 x 2>/dev/null; echo rc=$?')" "${sh_name}: a dead or foreign ID is 1"
        eq "rc=1" "$(probe "${sh_bin}" 'bs_obj_class A; bs_obj_new_to a A; bs_obj_destroy "$a"; bs_obj_get "$a" x 2>/dev/null; echo rc=$?')" "${sh_name}: a destroyed object refuses access"
        eq "o1 o2 o3" "$(probe "${sh_bin}" '
bs_obj_class A
bs_obj_new_to a A
bs_obj_new_to b A
bs_obj_destroy "$a"
bs_obj_new_to c A
printf "%s %s %s" "$a" "$b" "$c"')" "${sh_name}: IDs are unique, never reused"
    done < <(testframework::posix_shells)
}

test_aliases() {
    local sh_bin sh_name
    for sh_bin in bash zsh; do
        command -v "${sh_bin}" >/dev/null 2>&1 || continue
        sh_name="${sh_bin}"
        eq "o1|1" "$(probe "${sh_bin}" '
object::class C
object::field C n 0
object::method C inc c_inc
c_inc() { v=$(object::get "$1" n); object::set "$1" n "$((v + 1))"; object::get "$1" n; }
object::new_to c C
printf "%s|%s" "$c" "$(object::call "$c" inc)"')" "${sh_name}: object::* aliases work"
    done
}


test_review_regressions() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "5" "$(probe "${sh_bin}" '
bs_obj_class PR
bs_obj_field PR n 0
bs_obj_property PR n pr_g pr_s1
pr_g() { bs_obj_raw_get "$1" n; }
pr_s1() { bs_obj_raw_set "$1" n "S1:$2"; }
bs_obj_new_to p PR
bs_obj_property PR n pr_g
bs_obj_set "$p" n 5
bs_obj_get "$p" n')" "${sh_name}: redeclaring a property without a setter removes the old setter"
        eq "eq" "$(probe "${sh_bin}" '
bs_obj_class EI
bs_obj_field EI n 0
bs_obj_method EI init ei_init
ei_init() {
  if [ "${ei_guard:-}" = 1 ]; then return 0; fi
  ei_guard=1
  bs_obj_new_to ref EI
  if bs_obj_equal "$1" "$ref"; then verdict=eq; else verdict=ne; fi
}
bs_obj_new_to e EI
printf "%s" "$verdict"')" "${sh_name}: equal works inside init (the __init key is not counted)"
        eq "rc=2 rc=2 rc=2" "$(probe "${sh_bin}" '
bs_obj_class RC
bs_obj_field RC class x 2>/dev/null; printf "rc=%s " "$?"
bs_obj_field RC ok 0
bs_obj_new_to r RC class=y 2>/dev/null; printf "rc=%s " "$?"
bs_obj_new_to r2 RC
bs_obj_set "$r2" class z 2>/dev/null; printf "rc=%s" "$?"')" "${sh_name}: the reserved field class is refused everywhere"
        eq "rc=3|0" "$(probe "${sh_bin}" '
bs_obj_class LK
bs_obj_field LK n 0
bs_var_declare locked "ops=read"
bs_obj_new_to locked LK 2>/dev/null; printf "rc=%s|" "$?"
bs_obj_count')" "${sh_name}: a failed ID handover tears the object down (no leak)"
        eq "gone" "$(probe "${sh_bin}" '
bs_obj_class CQ
bs_obj_contract CQ gone gone
bs_obj_check CQ')" "${sh_name}: a repeated contract method is stored once"
        eq "1" "$(probe "${sh_bin}" '
bs_obj_class DQ
bs_obj_field DQ f ""
bs_obj_delegate DQ f
bs_obj_delegate DQ f
bs_arr_len objDDQ')" "${sh_name}: a repeated delegation field is stored once"
        eq "rc=3|" "$(probe "${sh_bin}" '
bs_obj_class RQ
bs_obj_contract RQ must
out=$(bs_obj_new RQ 2>/dev/null); printf "rc=%s|%s" "$?" "$out"')" "${sh_name}: a failed contract keeps new stdout empty"
        eq "rc=1|0" "$(probe "${sh_bin}" '
bs_obj_class SD
bs_obj_method SD init sd_init
sd_init() { bs_obj_destroy "$1"; }
bs_obj_new_to s SD 2>/dev/null; printf "rc=%s|" "$?"
bs_obj_count')" "${sh_name}: an init destroying its own object yields no dead ID"
        eq "0" "$(probe "${sh_bin}" '
bs_obj_class GG
bs_obj_class GG2
bs_obj_method GG destroy gg_destroy
gg_destroy() { bs_obj_new_to tmp GG2; }
bs_obj_new_to a GG
bs_obj_new_to b GG
bs_obj_destroy_all
bs_obj_count')" "${sh_name}: destroy_all catches objects born inside destroy methods"
        eq "yes" "$(probe "${sh_bin}" '
i=0; prev=""
while [ "$i" -lt 18 ]; do
  bs_obj_class "chain$i"
  bs_obj_field "chain$i" next ""
  bs_obj_delegate "chain$i" next
  bs_obj_new_to "c$i" "chain$i"
  eval "target=\$c${i}"
  if [ -n "$prev" ]; then bs_obj_set "$prev" next "$target"; fi
  prev=$target
  i=$((i + 1))
done
bs_obj_call "$c0" hit 2>&1 | grep -q "delegation limit" && printf yes')" "${sh_name}: the delegation limit has its own diagnosis"
    done < <(testframework::posix_shells)
}

main() {
    T="$(mktemp -d)"
    mkdir -p "${T}/h"
    testframework::section "Parses and lints / Разбор и линт"; test_parses_and_lints
    testframework::section "Class and fields / Класс и поля"; test_class_and_fields
    testframework::section "Methods / Методы"; test_methods
    testframework::section "Init and factory / Init и фабрика"; test_init_and_factory
    testframework::section "Privacy and readonly / Приватность и readonly"; test_privacy_and_readonly
    testframework::section "Properties / Свойства"; test_properties
    testframework::section "Inheritance and contract / Наследование и контракт"; test_inheritance_and_contract
    testframework::section "Delegation / Делегирование"; test_delegation
    testframework::section "Identity and lifetime / Идентичность и время жизни"; test_identity_and_lifetime
    testframework::section "Review regressions / Регрессии обзора"; test_review_regressions
    testframework::section "Aliases / Псевдонимы"; test_aliases
    rm -rf "${T:?}"
    testframework::summary
}

main "$@"
