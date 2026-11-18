#!/usr/bin/env bs
# shellcheck shell=bash
# example_core/shapes.sh — inheritance, contracts and delegation of core/object.sh
# example_core/shapes.sh — наследование, контракты и делегирование core/object.sh
#
# shape -> circle/rect: таблица методов наследуется, контракт area обязателен;
# window делегирует вызовы внутреннему объекту (композиция).
# shape -> circle/rect: the method table is inherited, the area contract is
# required; window delegates calls to its inner object (composition).
# Запуск / run: ./bs example_core/shapes.sh

# ci/re/w/bad присваивает object::new_to через bs_var_set, ShellCheck этого не видит /
# ci/re/w/bad are assigned by object::new_to via bs_var_set, which ShellCheck cannot follow
# shellcheck disable=SC2154

set -euo pipefail

load "core/object"

shape_name() { object::get "$1" name; }
circle_area() {
    local r
    r="$(object::get "$1" radius)"
    printf '%s\n' "$((3 * r * r))"
}
rect_area() {
    local w h
    w="$(object::get "$1" width)"
    h="$(object::get "$1" height)"
    printf '%s\n' "$((w * h))"
}
window_report() {
    local inner
    inner="$(object::get "$1" inner)"
    printf '%s: area=%s\n' "$(object::call "$inner" name)" "$(object::call "$inner" area)"
}

object::class shape
object::field shape name shape
object::method shape name shape_name
object::contract shape area name

object::class circle shape
object::field circle radius 1
object::method circle area circle_area

object::class rect shape
object::field rect width 1
object::field rect height 1
object::method rect area rect_area

object::class window
object::field window inner ''
object::delegate window inner
object::method window report window_report

printf 'Наследование и контракт / inheritance and contract\n'
object::new_to ci circle name=circle radius=2
object::new_to re rect name=rect width=3 height=4
for obj in "$ci" "$re"; do
    if object::is_a "$obj" shape; then
        printf '  %s is_a shape: area=%s\n' "$(object::call "$obj" name)" "$(object::call "$obj" area)"
    fi
done

printf 'Контракт проверяется при создании / the contract is checked at creation\n'
object::class broken shape
if object::new_to bad broken 2>/dev/null; then
    printf '  ERROR: a class without area was created\n'
else
    printf '  broken без area не создан / broken without area was refused (rc=3)\n'
fi

printf 'Композиция и делегирование / composition and delegation\n'
object::new_to w window
object::set "$w" inner "$ci"
object::call "$w" report
object::set "$w" inner "$re"
object::call "$w" report
printf '  window делегирует area / window delegates area: %s\n' "$(object::call "$w" area)"

object::destroy_all
