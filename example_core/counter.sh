#!/usr/bin/env bs
# shellcheck shell=bash
# example_core/counter.sh — the object model of core/object.sh: a Counter class
# example_core/counter.sh — объектная модель core/object.sh: класс Counter
#
# Поля, методы, свойства, наблюдатель, константа, общее поле типа, readonly,
# фабрика, равенство и уничтожение. Запуск: ./bs example_core/counter.sh
# Fields, methods, a property, a watcher, a constant, a shared type field,
# readonly, a factory, equality and destruction. Run: ./bs example_core/counter.sh
#
# Вывод — по стилю проекта (bs-cli-style, bs-posix-output): рамки log::section,
# вердикты log::success, данные log::info, RU первым, цвет только на tty.
# Output follows the project style: framed sections, success verdicts, RU first.

# c/c2/c3 присваивает object::new_to через bs_var_set, ShellCheck этого не видит /
# c/c2/c3 are assigned by object::new_to via bs_var_set, which ShellCheck cannot follow
# shellcheck disable=SC2154

strict::enable

load "core/object"

# Методы — обычные функции: первый аргумент — ID объекта.
# Результат метода — stdout (printf), не логгер: stdout метода — его значение.
# Methods are plain functions: the first argument is the object ID.
# A method's result goes to stdout (printf), not the logger.
counter_init() {
    object::set "$1" count 0
}
counter_inc() {
    local v step
    v="$(object::get "$1" count)"
    step="$(object::get "$1" step)"
    object::set "$1" count "$((v + step))"
}
counter_double() {
    local v
    v="$(object::get "$1" count)"
    printf '%s\n' "$((v * 2))"
}
counter_log() {
    log::info "  наблюдатель / watcher: $2 $3 -> $4"
}
counter_from() {
    object::new_to "$2" "$1" count="$3"
}

object::class Counter
object::field Counter count 0
object::field Counter step 1
object::field Counter created ''
object::readonly Counter created
object::method Counter init counter_init
object::method Counter inc counter_inc
object::property Counter double counter_double
object::watch Counter count counter_log
object::shared Counter instances 0
object::const Counter MAX 100
object::type_method Counter from counter_from
object::contract Counter inc

log::section "Создание / Creation"
object::new_to c Counter created=now
log::info "  id=$c class=$(object::class_of "$c") count=$(object::get "$c" count)"

log::section "Методы и свойства / Methods and properties"
object::call "$c" inc
object::call "$c" inc
log::info "  count=$(object::get "$c" count) double=$(object::get "$c" double)"

log::section "Неизменяемость и константы / Immutability and constants"
if object::set "$c" created later 2>/dev/null; then
    log::error "readonly принял запись / readonly accepted a write"
else
    log::success "readonly-поле защищено / readonly field refused the write (rc=3)"
fi
log::info "  MAX=$(object::type_get Counter MAX)"

log::section "Фабрика и общее поле типа / Factory and shared type field"
object::type_call Counter from c2 10
object::type_set Counter instances 2
log::info "  c2 count=$(object::get "$c2" count) instances=$(object::type_get Counter instances)"

log::section "Идентичность и равенство / Identity and equality"
object::new_to c3 Counter created=now
object::call "$c3" inc >/dev/null
object::call "$c3" inc >/dev/null
if object::equal "$c" "$c3"; then
    log::success "c и c3 равны по содержимому / c and c3 are content-equal"
fi
if ! object::same "$c" "$c3"; then
    log::info "  c и c3 — разные объекты / c and c3 are distinct objects"
fi

log::section "Уничтожение / Destruction"
object::destroy "$c3"
log::info "  живых объектов / live objects: $(object::count)"
object::destroy_all
log::success "после destroy_all / after destroy_all: $(object::count)"
