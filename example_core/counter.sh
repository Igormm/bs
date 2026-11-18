#!/usr/bin/env bs
# shellcheck shell=bash
# example_core/counter.sh — the object model of core/object.sh: a counter class
# example_core/counter.sh — объектная модель core/object.sh: класс counter
#
# Поля, методы, свойства, наблюдатель, константа, общее поле типа, readonly,
# фабрика, равенство и уничтожение. Запуск: ./bs example_core/counter.sh
# Fields, methods, a property, a watcher, a constant, a shared type field,
# readonly, a factory, equality and destruction. Run: ./bs example_core/counter.sh

# c/c2/c3 присваивает object::new_to через bs_var_set, ShellCheck этого не видит /
# c/c2/c3 are assigned by object::new_to via bs_var_set, which ShellCheck cannot follow
# shellcheck disable=SC2154

set -euo pipefail

load "core/object"

# Методы — обычные функции: первый аргумент — ID объекта
# Methods are plain functions: the first argument is the object ID
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
    printf '  наблюдатель / watcher: %s %s -> %s\n' "$2" "$3" "$4"
}
counter_from() {
    object::new_to "$2" "$1" count="$3"
}

object::class counter
object::field counter count 0
object::field counter step 1
object::field counter created at
object::readonly counter created
object::method counter init counter_init
object::method counter inc counter_inc
object::property counter double counter_double
object::watch counter count counter_log
object::shared counter instances 0
object::const counter MAX 100
object::type_method counter from counter_from
object::contract counter inc

printf 'Создание / creation\n'
object::new_to c counter created=now
printf '  id=%s class=%s count=%s\n' "$c" "$(object::class_of "$c")" "$(object::get "$c" count)"

printf 'Методы и свойства / methods and properties\n'
object::call "$c" inc
object::call "$c" inc
printf '  count=%s double=%s\n' "$(object::get "$c" count)" "$(object::get "$c" double)"

printf 'Неизменяемость и константы / immutability and constants\n'
if object::set "$c" created later 2>/dev/null; then
    printf '  ERROR: readonly accepted a write\n'
else
    printf '  readonly-поле создано только при создании / readonly field refused the write (rc=3)\n'
fi
printf '  MAX=%s\n' "$(object::type_get counter MAX)"

printf 'Фабрика и общее поле типа / factory and shared type field\n'
object::type_call counter from c2 10
object::type_set counter instances 2
printf '  c2 count=%s instances=%s\n' "$(object::get "$c2" count)" "$(object::type_get counter instances)"

printf 'Идентичность и равенство / identity and equality\n'
object::new_to c3 counter created=now
object::call "$c3" inc >/dev/null
object::call "$c3" inc >/dev/null
if object::equal "$c" "$c3"; then
    printf '  c и c3 равны по содержимому / c and c3 are content-equal\n'
fi
if ! object::same "$c" "$c3"; then
    printf '  c и c3 — разные объекты / c and c3 are distinct objects\n'
fi

printf 'Уничтожение / destruction\n'
object::destroy "$c3"
printf '  живых объектов / live objects: %s\n' "$(object::count)"
object::destroy_all
printf '  после destroy_all / after destroy_all: %s\n' "$(object::count)"
