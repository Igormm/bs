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
#
# Вывод — по стилю проекта (bs-cli-style, bs-posix-output).
# Output follows the project style.

# ci/re/w/bad присваивает object::new_to через bs_var_set, ShellCheck этого не видит /
# ci/re/w/bad are assigned by object::new_to via bs_var_set, which ShellCheck cannot follow
# shellcheck disable=SC2154

strict::enable

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

object::class Shape
object::field Shape name shape
object::method Shape name shape_name
object::contract Shape area name

object::class Circle Shape
object::field Circle radius 1
object::method Circle area circle_area

object::class Rect Shape
object::field Rect width 1
object::field Rect height 1
object::method Rect area rect_area

object::class Window
object::field Window inner ''
object::delegate Window inner
object::method Window report window_report

bs_log_section "Наследование и контракт / Inheritance and contract"
object::new_to ci Circle name=circle radius=2
object::new_to re Rect name=rect width=3 height=4
for obj in "$ci" "$re"; do
    if object::is_a "$obj" Shape; then
        bs_log_info "  $(object::call "$obj" name) is_a shape: area=$(object::call "$obj" area)"
    fi
done

bs_log_section "Контракт при создании / The contract at creation"
object::class Broken Shape
if object::new_to bad Broken 2>/dev/null; then
    bs_log_error "класс без area создан / a class without area was created"
else
    bs_log_success "broken без area не создан / broken without area was refused (rc=3)"
fi

bs_log_section "Композиция и делегирование / Composition and delegation"
object::new_to w Window
object::set "$w" inner "$ci"
bs_log_info "  $(object::call "$w" report)"
object::set "$w" inner "$re"
bs_log_info "  $(object::call "$w" report)"
bs_log_success "window делегирует area / window delegates area: $(object::call "$w" area)"

object::destroy_all
