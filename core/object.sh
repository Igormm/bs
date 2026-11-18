#!/bin/sh
# shellcheck shell=sh
# @shell posix — валидный POSIX sh: классы и объекты на словарях core/data.sh, без массивов, declare, nameref, ${!x} и [[ ]] / valid POSIX sh: classes and objects on the maps of core/data.sh, no arrays, declare, namerefs, ${!x} or [[ ]]
# @tier core — builtins only; works everywhere
# @depends core/data
#
# core/object.sh — переносимая объектная модель: классы, экземпляры, методы
# core/object.sh — a portable object model: classes, instances, methods
#
# ЗАЧЕМ / WHY
#   POSIX sh не знает объектов. Этот модуль даёт единую модель: поля экземпляра
#   и общие поля типа, методы экземпляра и типа, создание и инициализация,
#   свойства (геттеры/сеттеры), наблюдатели, неизменяемые поля, контракты,
#   наследование через таблицы методов, композиция и делегирование, идентичность
#   и равенство, явное уничтожение. Всё хранится в словарях core/data.sh, поэтому
#   работает в dash, ash, ksh, mksh, zsh и bash одинаково. sqlite и C не нужны:
#   объект — это переменные процесса, а не строки внешней БД.
#   POSIX sh has no objects. This module gives one model: instance fields and
#   shared type fields, instance and type methods, creation and initialization,
#   properties (getters/setters), watchers, immutable fields, contracts,
#   inheritance through method tables, composition and delegation, identity and
#   equality, explicit destruction. Everything lives in the maps of core/data.sh,
#   so it behaves the same in dash, ash, ksh, mksh, zsh and bash. No sqlite or C
#   is needed: an object is process variables, not rows of an external database.
#
# УСТРОЙСТВО / LAYOUT
#   Класс Name — словарь objCName: parent (родитель), f:<field> (поле экземпляра
#   и его начальное значение), s:<field> (общее поле типа), k:<NAME> (константа),
#   m:<method> (функция метода экземпляра), t:<method> (функция метода типа),
#   g:<prop>/p:<prop> (геттер/сеттер свойства), ro:<field> (неизменяемое),
#   pr:<field> (приватное), w:<field> (наблюдатель), плюс массивы objDName
#   (поля делегирования) и objReqName (контракт). Экземпляр — ID o<N> и словарь
#   objI<N> (class + значения полей). Реестр живых — словарь objLive (ID → класс).
#   A class Name is the map objCName: parent, f:<field> (an instance field and
#   its default), s:<field> (a shared type field), k:<NAME> (a constant),
#   m:<method> (instance method function), t:<method> (type method function),
#   g:<prop>/p:<prop> (property getter/setter), ro:<field> (immutable),
#   pr:<field> (private), w:<field> (watcher), plus the arrays objDName
#   (delegation fields) and objReqName (contract). An instance is an ID o<N> and
#   the map objI<N> (class + field values). The live registry is objLive (ID → class).
#
# ПРАВИЛА / RULES
#   * Имена классов, полей и методов — [A-Za-z][A-Za-z0-9_]*, без «__» и без «_»
#     на конце (как у словарей core/data.sh). / Names are [A-Za-z][A-Za-z0-9_]*,
#     with no "__" and no trailing "_" (as for core/data.sh maps).
#   * Коды: 0 успех; 1 нет такого (объект, класс, поле, метод); 2 плохое имя или
#     аргумент; 3 нарушение правила (readonly, private, константа, контракт).
#     Codes: 0 ok; 1 no such thing (object, class, field, method); 2 bad name or
#     argument; 3 rule violation (readonly, private, constant, contract).
#   * Метод экземпляра — функция «FN ID АРГУМЕНТЫ…», метод типа — «FN КЛАСС АРГУМЕНТЫ…».
#     An instance method is a function "FN ID ARGS…", a type method is "FN CLASS ARGS…".
#   * ПРИВАТНОСТЬ УСЛОВНА: публичные bs_obj_get/set отказывают в доступе к pr:-полям,
#     методы класса работают через bs_obj_raw_get/raw_set. В shell нельзя скрыть
#     переменные __bs_dat_* от того же процесса: приватность — правило API, а не защита.
#     PRIVACY IS CONVENTIONAL: the public bs_obj_get/set refuse pr: fields, the
#     methods of the class use bs_obj_raw_get/raw_set. Shell cannot hide the
#     __bs_dat_* variables from the same process: privacy is an API rule, not a barrier.
#   * ВЛАДЕНИЕ: объекты принадлежат процессу оболочки, который их создал. ID не
#     передаётся между процессами; подоболочка $(...) получает копию — мутации в
#     ней не видны снаружи. bs_obj_new печатает ID, но создаёт объект в ТЕКУЩЕЙ
#     оболочке: берите ID через bs_obj_new_to ПЕРЕМЕННАЯ класс …, а не $(bs_obj_new …).
#     OWNERSHIP: objects belong to the shell process that created them. IDs do not
#     cross processes; a $(...) subshell gets a copy — its mutations are invisible
#     outside. bs_obj_new prints the ID but creates the object in the CURRENT
#     shell: take the ID via bs_obj_new_to VAR class …, not $(bs_obj_new …).
#   * Очистка: bs_obj_destroy_all уничтожает все живые объекты; точка входа может
#     зарегистрировать её через bs_cleanup_add bs_obj_destroy_all.
#     Cleanup: bs_obj_destroy_all destroys every live object; an entry point may
#     register it with bs_cleanup_add bs_obj_destroy_all.
#
# ИМЕНА / NAMES: пространство bs_ (bs_obj_*); псевдонимы object::* — в bash и zsh.
#   Namespace bs_ (bs_obj_*); the object::* aliases exist in bash and zsh.

# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points

# shellcheck disable=SC2154  # __bs_obj_ci_N/__bs_obj_eb_N присваиваются через eval, ShellCheck их не видит / assigned through eval, which ShellCheck cannot follow
bs_guard OBJECT || return 0

# Dependencies / Зависимости
bs_source_relative "data.sh"

# @global __bs_obj_seq — State: monotonic instance counter, IDs are o1, o2, … (category: state)
# @global __bs_obj_seq — Состояние: монотонный счётчик экземпляров, ID — o1, o2, … (категория: state)
__bs_obj_seq=0
# @global __bs_obj_d — State: scratch depth for nested calls (new/call/fields/equal/destroy_all) (category: state)
# @global __bs_obj_d — Состояние: глубина черновиков для вложенных вызовов (new/call/fields/equal/destroy_all) (категория: state)
__bs_obj_d=0
# @global __bs_obj_cd — State: delegation call depth, capped at 16 (category: state)
# @global __bs_obj_cd — Состояние: глубина вызовов делегирования, предел 16 (категория: state)
__bs_obj_cd=0
# @global __bs_obj_last_id — State: ID of the last object created by bs_obj_new (category: state)
# @global __bs_obj_last_id — Состояние: ID последнего объекта, созданного bs_obj_new (категория: state)
__bs_obj_last_id=''

# Служебное / Helpers

# @private
# @description Проверить имя класса, поля или метода / Check a class, field or method name
# @param $1 name / имя
# @returns 0 ok / 2 bad name / плохое имя
bs_obj__name() {
  case "${1-}" in
    ''|[!A-Za-z]*|*[!A-Za-z0-9_]*|*__*|*_)
      printf 'bs_obj: invalid name: %s\n' "${1-}" >&2
      return 2 ;;
  esac
  return 0
}

# @private
# @description Зарезервированные поля класса и инициализации / Reserved fields of the class and initialization
# @param $1 field / поле
bs_obj__reserved() {
  case "${1-}" in
    class|__init)
      printf 'bs_obj: reserved field: %s\n' "${1-}" >&2
      return 2 ;;
  esac
  return 0
}

# @private
# @description Проверить формат ID (o<цифры>) / Check the ID format (o<digits>)
# @param $1 id / ID
bs_obj__id_check() {
  case "${1-}" in
    o[0-9]*) ;;
    *) return 1 ;;
  esac
  __bs_obj_ic=${1#o}
  case "$__bs_obj_ic" in
    ''|*[!0-9]*) return 1 ;;
  esac
  return 0
}

# @private
# @description Класс объявлен (статус) / Whether the class is declared (status)
# @param $1 class / класс
bs_obj__class_exists() {
  bs_obj__name "${1-}" || return 2
  if bs_map_has "objC${1}" parent; then
    return 0
  fi
  printf 'bs_obj: unknown class: %s\n' "${1-}" >&2
  return 1
}

# @private
# @description Найти ключ <префикс>:<имя> по цепочке классов (свой класс, затем родители);
#   значение → __bs_obj_val, класс-владелец → __bs_obj_own; статус 1 — нет ключа.
#   Find the key <prefix>:<name> along the class chain (own class, then parents);
#   the value → __bs_obj_val, the owning class → __bs_obj_own; status 1 means no key.
# @param $1 class / класс
# @param $2 prefix (f, s, k, m, t, g, p, ro, pr, w) / префикс
# @param $3 name / имя
bs_obj__lookup() {
  __bs_obj_lc=${1-}
  __bs_obj_lh=0
  while [ -n "$__bs_obj_lc" ] && [ "$__bs_obj_lh" -lt 32 ]; do
    if bs_map_get_to "objC${__bs_obj_lc}" "${2}:${3}" __bs_obj_val; then
      __bs_obj_own=$__bs_obj_lc
      return 0
    fi
    bs_map_get_to "objC${__bs_obj_lc}" parent __bs_obj_lp || __bs_obj_lp=''
    __bs_obj_lc=$__bs_obj_lp
    __bs_obj_lh=$((__bs_obj_lh + 1))
  done
  return 1
}

# @private
# @description Убрать экземпляр без вызова метода destroy (путь ошибки) / Remove an instance without calling destroy (error path)
# @param $1 id / ID
bs_obj__teardown() {
  bs_map_clear "objI${1#o}"
  bs_map_remove objLive "$1"
  return 0
}

# @private
# @description Обратный вызов bs_map_each: начальные значения полей (первый выигрывает —
#   свой класс раньше родителей); контекст __bs_obj_ci_N — словарь экземпляра.
#   bs_map_each callback: field defaults (first wins — own class before parents);
#   the context __bs_obj_ci_N is the instance map.
# @param $1 key / ключ
# @param $2 value / значение
bs_obj__defaults_cb() {
  case "${1-}" in
    f:*) ;;
    *) return 0 ;;
  esac
  __bs_obj_df=${1#f:}
  eval "__bs_obj_di=\${__bs_obj_ci_${__bs_obj_d}}"
  if ! bs_map_has "$__bs_obj_di" "$__bs_obj_df"; then
    bs_map_set "$__bs_obj_di" "$__bs_obj_df" "${2-}"
  fi
  return 0
}

# @private
# @description Обратный вызов bs_map_each: собрать имена полей в objF<N> без повторов /
#   bs_map_each callback: collect field names into objF<N> without duplicates
# @param $1 key / ключ
# @param $2 value / значение
bs_obj__fields_cb() {
  case "${1-}" in
    f:*) ;;
    *) return 0 ;;
  esac
  __bs_obj_ff=${1#f:}
  if ! bs_arr_contains "objF${__bs_obj_d}" "$__bs_obj_ff"; then
    bs_arr_push "objF${__bs_obj_d}" "$__bs_obj_ff"
  fi
  return 0
}

# @private
# @description Обратный вызов bs_map_each: сравнить поле с полем второго объекта;
#   контекст __bs_obj_eb_N — словарь второго объекта, итог — __bs_obj_eqok.
#   bs_map_each callback: compare a field with the second object's field;
#   the context __bs_obj_eb_N is the second instance map, the verdict is __bs_obj_eqok.
# @param $1 key / ключ
# @param $2 value / значение
bs_obj__equal_cb() {
  case "${1-}" in
    class|__init) return 0 ;;
  esac
  eval "__bs_obj_ei=\${__bs_obj_eb_${__bs_obj_d}}"
  if ! bs_map_get_to "$__bs_obj_ei" "${1-}" __bs_obj_ev; then
    __bs_obj_eqok=0
    return 0
  fi
  if [ "${2-}" != "$__bs_obj_ev" ]; then
    __bs_obj_eqok=0
  fi
  return 0
}

# @private
# @description Вызвать наблюдателя поля, если он объявлен (статус наблюдателя не влияет на запись) /
#   Call the field watcher if declared (the watcher's status does not affect the write)
# @param $1 id / ID
# @param $2 class / класс
# @param $3 field / поле
# @param $4 old value / старое значение
# @param $5 new value / новое значение
bs_obj__notify() {
  if bs_obj__lookup "${2-}" w "${3-}"; then
    __bs_obj_wf=$__bs_obj_val
    if command -v "$__bs_obj_wf" >/dev/null 2>&1; then
      "$__bs_obj_wf" "${1-}" "${3-}" "${4-}" "${5-}" || :
    fi
  fi
  return 0
}

# Объявление класса и его членов / Class declaration and its members

# @description Объявить класс (можно с родителем — наследование таблиц методов) /
#   Declare a class (optionally with a parent — method-table inheritance)
# @param $1 class name / имя класса
# @param $2 parent class (optional) / родительский класс (необязательно)
# @returns 0 ok / 1 нет родителя / no such parent / 2 плохое имя, цикл или повтор / bad name, cycle or redeclaration
bs_obj_class() {
  bs_obj__name "${1-}" || return 2
  if bs_map_has "objC${1}" parent; then
    printf 'bs_obj: class already declared: %s\n' "$1" >&2
    return 2
  fi
  __bs_obj_cp=${2-}
  if [ -n "$__bs_obj_cp" ]; then
    bs_obj__class_exists "$__bs_obj_cp" || return 1
    __bs_obj_cc=$__bs_obj_cp
    __bs_obj_ch=0
    while [ -n "$__bs_obj_cc" ] && [ "$__bs_obj_ch" -lt 32 ]; do
      if [ "$__bs_obj_cc" = "$1" ]; then
        printf 'bs_obj: inheritance cycle: %s\n' "$1" >&2
        return 2
      fi
      bs_map_get_to "objC${__bs_obj_cc}" parent __bs_obj_cc || __bs_obj_cc=''
      __bs_obj_ch=$((__bs_obj_ch + 1))
    done
  fi
  bs_map_set "objC${1}" parent "$__bs_obj_cp"
  return 0
}

# @description Поле экземпляра с начальным значением / An instance field with a default
# @param $1 class / класс
# @param $2 field / поле
# @param $3 default (optional, empty by default) / начальное значение (необязательно, по умолчанию пусто)
bs_obj_field() {
  bs_obj__class_exists "${1-}" || return $?
  bs_obj__name "${2-}" || return 2
  bs_obj__reserved "${2-}" || return 2
  bs_map_set "objC${1}" "f:${2}" "${3-}"
  return 0
}

# @description Общее поле типа (одно на класс, видно всем экземплярам через bs_obj_type_get) /
#   A shared type field (one per class, visible to every instance through bs_obj_type_get)
# @param $1 class / класс
# @param $2 field / поле
# @param $3 default (optional) / начальное значение (необязательно)
bs_obj_shared() {
  bs_obj__class_exists "${1-}" || return $?
  bs_obj__name "${2-}" || return 2
  bs_map_set "objC${1}" "s:${2}" "${3-}"
  return 0
}

# @description Константа типа (запись запрещена) / A type constant (writes are refused)
# @param $1 class / класс
# @param $2 NAME / имя
# @param $3 value / значение
bs_obj_const() {
  bs_obj__class_exists "${1-}" || return $?
  bs_obj__name "${2-}" || return 2
  bs_map_set "objC${1}" "k:${2}" "${3-}"
  return 0
}

# @description Метод экземпляра: функция получает ID первым аргументом /
#   An instance method: the function receives the ID as its first argument
# @param $1 class / класс
# @param $2 method / метод
# @param $3 function name / имя функции
bs_obj_method() {
  bs_obj__class_exists "${1-}" || return $?
  bs_obj__name "${2-}" || return 2
  bs_obj__name "${3-}" || return 2
  bs_map_set "objC${1}" "m:${2}" "$3"
  return 0
}

# @description Метод типа: функция получает имя класса первым аргументом /
#   A type method: the function receives the class name as its first argument
# @param $1 class / класс
# @param $2 method / метод
# @param $3 function name / имя функции
bs_obj_type_method() {
  bs_obj__class_exists "${1-}" || return $?
  bs_obj__name "${2-}" || return 2
  bs_obj__name "${3-}" || return 2
  bs_map_set "objC${1}" "t:${2}" "$3"
  return 0
}

# @description Свойство: вычисляемый геттер и необязательный сеттер. Геттер — «FN ID»
#   (значение в stdout), сеттер — «FN ID ЗНАЧЕНИЕ» (сам сохраняет через bs_obj_raw_set).
#   A property: a computed getter and an optional setter. The getter is "FN ID"
#   (value on stdout), the setter is "FN ID VALUE" (it stores via bs_obj_raw_set).
# @param $1 class / класс
# @param $2 property / свойство
# @param $3 getter function / функция геттера
# @param $4 setter function (optional) / функция сеттера (необязательно)
bs_obj_property() {
  bs_obj__class_exists "${1-}" || return $?
  bs_obj__name "${2-}" || return 2
  bs_obj__name "${3-}" || return 2
  # Имя сеттера проверяется ДО записи геттера: объявление атомарно
  # The setter name is checked BEFORE writing the getter: the declaration is atomic
  if [ -n "${4-}" ]; then
    bs_obj__name "$4" || return 2
  fi
  bs_map_set "objC${1}" "g:${2}" "$3"
  if [ -n "${4-}" ]; then
    bs_map_set "objC${1}" "p:${2}" "$4"
  else
    # Повторное объявление без сеттера убирает прежний: иначе старый сеттер молча жил бы
    # Redeclaration without a setter removes the old one: otherwise it would silently live on
    bs_map_remove "objC${1}" "p:${2}" || :
  fi
  return 0
}

# @description Неизменяемое поле: запись только при создании и в методе init /
#   An immutable field: writable only during creation and inside init
# @param $1 class / класс
# @param $2 field / поле
bs_obj_readonly() {
  bs_obj__class_exists "${1-}" || return $?
  bs_obj__name "${2-}" || return 2
  if ! bs_obj__lookup "$1" f "$2"; then
    printf 'bs_obj: unknown field: %s\n' "$2" >&2
    return 1
  fi
  bs_map_set "objC${1}" "ro:${2}" 1
  return 0
}

# @description Приватное поле: публичные get/set отказывают (код 3), методы класса
#   используют bs_obj_raw_get/raw_set. Приватность условна (см. шапку).
#   A private field: the public get/set refuse (code 3), the class methods use
#   bs_obj_raw_get/raw_set. Privacy is conventional (see the header).
# @param $1 class / класс
# @param $2 field / поле
bs_obj_private() {
  bs_obj__class_exists "${1-}" || return $?
  bs_obj__name "${2-}" || return 2
  if ! bs_obj__lookup "$1" f "$2"; then
    printf 'bs_obj: unknown field: %s\n' "$2" >&2
    return 1
  fi
  bs_map_set "objC${1}" "pr:${2}" 1
  return 0
}

# @description Наблюдатель изменения поля: «FN ID ПОЛЕ СТАРОЕ НОВОЕ» после успешной записи /
#   A field-change watcher: "FN ID FIELD OLD NEW" after a successful write
# @param $1 class / класс
# @param $2 field / поле
# @param $3 function name / имя функции
bs_obj_watch() {
  bs_obj__class_exists "${1-}" || return $?
  bs_obj__name "${2-}" || return 2
  bs_obj__name "${3-}" || return 2
  if ! bs_obj__lookup "$1" f "$2"; then
    printf 'bs_obj: unknown field: %s\n' "$2" >&2
    return 1
  fi
  bs_map_set "objC${1}" "w:${2}" "$3"
  return 0
}

# @description Поле делегирования: композиция — значение поля хранит ID другого объекта;
#   если метод не найден в цепочке классов, вызов пробуется на этом объекте.
#   A delegation field: composition — the field value holds another object's ID;
#   if a method is not found in the class chain, the call is tried on that object.
# @param $1 class / класс
# @param $2 field / поле
bs_obj_delegate() {
  bs_obj__class_exists "${1-}" || return $?
  bs_obj__name "${2-}" || return 2
  if ! bs_obj__lookup "$1" f "$2"; then
    printf 'bs_obj: unknown field: %s\n' "$2" >&2
    return 1
  fi
  if ! bs_arr_contains "objD${1}" "$2"; then
    bs_arr_push "objD${1}" "$2"
  fi
  return 0
}

# @description Контракт: обязательные методы; проверяется при создании и в bs_obj_check /
#   Contract: required methods; checked at creation and by bs_obj_check
# @param $1 class / класс
# @param $@ method names / имена методов
bs_obj_contract() {
  bs_obj__class_exists "${1-}" || return $?
  __bs_obj_kc=$1
  shift
  for __bs_obj_km in "$@"; do
    bs_obj__name "$__bs_obj_km" || return 2
    if ! bs_arr_contains "objReq${__bs_obj_kc}" "$__bs_obj_km"; then
      bs_arr_push "objReq${__bs_obj_kc}" "$__bs_obj_km"
    fi
  done
  return 0
}

# @description Проверить контракт класса и его родителей: все обязательные методы
#   разрешимы в цепочке / Check the contract of the class and its parents: every
#   required method resolves in the chain
# @param $1 class / класс
# @stdout имена недостающих методов, по одному в строке / missing method names, one per line
# @returns 0 контракт выполнен / fulfilled / 1 есть недостающие / missing methods
bs_obj_check() {
  bs_obj__class_exists "${1-}" || return $?
  __bs_obj_k0=$1
  __bs_obj_kc=$1
  __bs_obj_kr=0
  __bs_obj_kh=0
  while [ -n "$__bs_obj_kc" ] && [ "$__bs_obj_kh" -lt 32 ]; do
    eval "$(bs_arr_to_args "objReq${__bs_obj_kc}")"
    for __bs_obj_km in "$@"; do
      if ! bs_obj__lookup "$__bs_obj_k0" m "$__bs_obj_km"; then
        printf '%s\n' "$__bs_obj_km"
        __bs_obj_kr=1
      fi
    done
    bs_map_get_to "objC${__bs_obj_kc}" parent __bs_obj_kc || __bs_obj_kc=''
    __bs_obj_kh=$((__bs_obj_kh + 1))
  done
  return "$__bs_obj_kr"
}

# Создание и время жизни / Creation and lifetime

# @description Создать объект: начальные значения полей, метод init (если объявлен),
#   затем пары поле=значение (пары — последнее слово). Контракт проверяется до создания.
#   НЕ вызывайте как $(...): объект останется в подоболочке — берите ID через bs_obj_new_to.
#   Create an object: field defaults, the init method (if declared), then field=value
#   pairs (the pairs have the final word). The contract is checked before creation.
#   Do NOT call as $(...): the object would stay in the subshell — take the ID via bs_obj_new_to.
# @param $1 class / класс
# @param $@ field=value pairs / пары поле=значение
# @stdout ID объекта / the object ID
# @returns 0 ok / 1 нет класса или поля / no such class or field / 2 плохой аргумент / bad argument / 3 контракт / contract
bs_obj_new() {
  __bs_obj_nc=${1-}
  bs_obj__class_exists "$__bs_obj_nc" || return $?
  shift
  if ! bs_obj_check "$__bs_obj_nc" >&2; then
    printf 'bs_obj: contract not fulfilled: %s\n' "$__bs_obj_nc" >&2
    return 3
  fi
  __bs_obj_seq=$((__bs_obj_seq + 1))
  __bs_obj_last_id="o${__bs_obj_seq}"
  __bs_obj_ni="objI${__bs_obj_seq}"
  bs_map_set "$__bs_obj_ni" class "$__bs_obj_nc"
  bs_map_set objLive "$__bs_obj_last_id" "$__bs_obj_nc"
  # Начальные значения: свой класс, затем родители; первое значение выигрывает
  # Defaults: own class, then parents; the first value wins
  __bs_obj_d=$((__bs_obj_d + 1))
  eval "__bs_obj_ci_${__bs_obj_d}=\${__bs_obj_ni}"
  __bs_obj_nd=$__bs_obj_nc
  __bs_obj_nh=0
  while [ -n "$__bs_obj_nd" ] && [ "$__bs_obj_nh" -lt 32 ]; do
    bs_map_each "objC${__bs_obj_nd}" bs_obj__defaults_cb
    bs_map_get_to "objC${__bs_obj_nd}" parent __bs_obj_nd || __bs_obj_nd=''
    __bs_obj_nh=$((__bs_obj_nh + 1))
  done
  __bs_obj_d=$((__bs_obj_d - 1))
  if bs_obj__lookup "$__bs_obj_nc" m init; then
    bs_map_set "$__bs_obj_ni" __init 1
    # init — пользовательский код: он может вложить свой bs_obj_new, поэтому класс,
    # словарь и ID сохраняются по глубине и возвращаются после вызова
    # init is user code: it may nest its own bs_obj_new, so the class, the map and
    # the ID are saved by depth and taken back after the call
    __bs_obj_d=$((__bs_obj_d + 1))
    eval "__bs_obj_nc_${__bs_obj_d}=\${__bs_obj_nc}"
    eval "__bs_obj_ni_${__bs_obj_d}=\${__bs_obj_ni}"
    eval "__bs_obj_nid_${__bs_obj_d}=\${__bs_obj_last_id}"
    if bs_obj_call "$__bs_obj_last_id" init; then
      __bs_obj_nr=0
    else
      __bs_obj_nr=$?
    fi
    eval "__bs_obj_nc=\${__bs_obj_nc_${__bs_obj_d}}"
    eval "__bs_obj_ni=\${__bs_obj_ni_${__bs_obj_d}}"
    eval "__bs_obj_last_id=\${__bs_obj_nid_${__bs_obj_d}}"
    __bs_obj_d=$((__bs_obj_d - 1))
    if [ "$__bs_obj_nr" -ne 0 ]; then
      bs_obj__teardown "$__bs_obj_last_id"
      return "$__bs_obj_nr"
    fi
    # init мог уничтожить сам объект: мёртвый ID не выдаётся, пары не воскрешают словарь
    # init may have destroyed the object itself: no dead ID is handed out, pairs do not revive the map
    if ! bs_obj_alive "$__bs_obj_last_id"; then
      return 1
    fi
  fi
  for __bs_obj_na in "$@"; do
    case "$__bs_obj_na" in
      *=*) ;;
      *)
        printf 'bs_obj: expected field=value, got: %s\n' "$__bs_obj_na" >&2
        bs_obj__teardown "$__bs_obj_last_id"
        return 2 ;;
    esac
    __bs_obj_nf=${__bs_obj_na%%=*}
    __bs_obj_nv=${__bs_obj_na#*=}
    if ! bs_obj__name "$__bs_obj_nf"; then
      bs_obj__teardown "$__bs_obj_last_id"
      return 2
    fi
    if ! bs_obj__reserved "$__bs_obj_nf"; then
      bs_obj__teardown "$__bs_obj_last_id"
      return 2
    fi
    if ! bs_obj__lookup "$__bs_obj_nc" f "$__bs_obj_nf"; then
      printf 'bs_obj: unknown field: %s\n' "$__bs_obj_nf" >&2
      bs_obj__teardown "$__bs_obj_last_id"
      return 1
    fi
    bs_map_set "$__bs_obj_ni" "$__bs_obj_nf" "$__bs_obj_nv"
  done
  bs_map_remove "$__bs_obj_ni" __init || :
  printf '%s\n' "$__bs_obj_last_id"
  return 0
}

# @description Создать объект и положить ID в переменную (без подоболочки) /
#   Create an object and put the ID into a variable (no subshell)
# @param $1 variable for the ID / переменная для ID
# @param $2 class / класс
# @param $@ field=value pairs / пары поле=значение
bs_obj_new_to() {
  bs_obj__name "${1-}" || return 2
  # bs_obj_new может вложить свой bs_obj_new_to (через init): имя переменной
  # сохраняется по глубине / bs_obj_new may nest its own bs_obj_new_to (through
  # init): the variable name is saved by depth
  __bs_obj_d=$((__bs_obj_d + 1))
  eval "__bs_obj_ntv_${__bs_obj_d}=\${1}"
  shift
  if bs_obj_new "$@" >/dev/null; then
    eval "__bs_obj_ntv=\${__bs_obj_ntv_${__bs_obj_d}}"
    __bs_obj_d=$((__bs_obj_d - 1))
    if bs_var_set "$__bs_obj_ntv" "$__bs_obj_last_id"; then
      return 0
    else
      # ID не выдан (схема/ops переменной): объект не должен утечь
      # The ID was not handed out (variable schema/ops): the object must not leak
      __bs_obj_ntr=$?
      bs_obj__teardown "$__bs_obj_last_id"
      return "$__bs_obj_ntr"
    fi
  else
    __bs_obj_ntr=$?
    __bs_obj_d=$((__bs_obj_d - 1))
    return "$__bs_obj_ntr"
  fi
}

# @description Уничтожить объект: метод destroy (если объявлен), затем очистка полей и реестра /
#   Destroy an object: the destroy method (if declared), then clear the fields and the registry
# @param $1 id / ID
# @returns 0 ok / 1 нет такого объекта / no such object
bs_obj_destroy() {
  if ! bs_obj_alive "${1-}"; then
    return 1
  fi
  # Метод destroy — пользовательский код: он может вложить свой bs_obj_destroy,
  # поэтому ID сохраняется по глубине и возвращается после вызова
  # The destroy method is user code: it may nest its own bs_obj_destroy, so the
  # ID is saved by depth and taken back after the call
  __bs_obj_d=$((__bs_obj_d + 1))
  eval "__bs_obj_did_${__bs_obj_d}=\${1}"
  bs_map_get_to "objI${1#o}" class __bs_obj_dc || __bs_obj_dc=''
  if bs_obj__lookup "$__bs_obj_dc" m destroy; then
    __bs_obj_df=$__bs_obj_val
    if command -v "$__bs_obj_df" >/dev/null 2>&1; then
      "$__bs_obj_df" "$1" || :
    fi
  fi
  eval "__bs_obj_di=\${__bs_obj_did_${__bs_obj_d}}"
  __bs_obj_d=$((__bs_obj_d - 1))
  bs_obj__teardown "$__bs_obj_di"
  return 0
}

# @description Уничтожить все живые объекты (очистка временных данных при выходе) /
#   Destroy every live object (cleanup of temporary data at exit)
bs_obj_destroy_all() {
  # Метод destroy может создать новые объекты: повторяем, пока реестр не опустеет
  # A destroy method may create new objects: repeat until the registry is empty
  __bs_obj_drounds=0
  while [ "$__bs_obj_drounds" -lt 32 ]; do
    __bs_obj_dcnt=$(bs_map_count objLive)
    if [ "$__bs_obj_dcnt" = 0 ]; then
      return 0
    fi
    __bs_obj_d=$((__bs_obj_d + 1))
    bs_map_keys_to objLive "objSnap${__bs_obj_d}"
    eval "$(bs_arr_to_args "objSnap${__bs_obj_d}")"
    for __bs_obj_da in "$@"; do
      bs_obj_destroy "$__bs_obj_da" || :
    done
    bs_arr_clear "objSnap${__bs_obj_d}"
    __bs_obj_d=$((__bs_obj_d - 1))
    __bs_obj_drounds=$((__bs_obj_drounds + 1))
  done
  printf 'bs_obj: destroy_all: objects keep appearing (32 rounds)\n' >&2
  return 1
}

# @description Число живых объектов / The number of live objects
# @stdout count / число
bs_obj_count() {
  bs_map_count objLive
}

# @description Объект жив (статус) / Whether the object is live (status)
# @param $1 id / ID
bs_obj_alive() {
  bs_obj__id_check "${1-}" || return 1
  bs_map_has objLive "$1"
}

# Доступ к состоянию / State access

# @description Класс объекта / The object's class
# @param $1 id / ID
# @stdout class name / имя класса
bs_obj_class_of() {
  bs_obj_alive "${1-}" || return 1
  bs_map_get_to "objI${1#o}" class __bs_obj_val || return 1
  printf '%s\n' "$__bs_obj_val"
  return 0
}

# @description Объект — экземпляр класса или его потомка (статус) /
#   Whether the object is an instance of the class or its descendant (status)
# @param $1 id / ID
# @param $2 class / класс
bs_obj_is_a() {
  bs_obj_alive "${1-}" || return 1
  bs_obj__name "${2-}" || return 2
  bs_map_get_to "objI${1#o}" class __bs_obj_ic || return 1
  __bs_obj_ih=0
  while [ -n "$__bs_obj_ic" ] && [ "$__bs_obj_ih" -lt 32 ]; do
    if [ "$__bs_obj_ic" = "$2" ]; then
      return 0
    fi
    bs_map_get_to "objC${__bs_obj_ic}" parent __bs_obj_ic || __bs_obj_ic=''
    __bs_obj_ih=$((__bs_obj_ih + 1))
  done
  return 1
}

# @description Прочитать поле: приватное — отказ (3), свойство — геттер, иначе сохранённое значение /
#   Read a field: private — refuse (3), property — the getter, otherwise the stored value
# @param $1 id / ID
# @param $2 field / поле
# @stdout value / значение
bs_obj_get() {
  bs_obj_alive "${1-}" || return 1
  bs_obj__name "${2-}" || return 2
  bs_map_get_to "objI${1#o}" class __bs_obj_gc || return 1
  if bs_obj__lookup "$__bs_obj_gc" pr "$2"; then
    printf 'bs_obj: private field: %s\n' "$2" >&2
    return 3
  fi
  if bs_obj__lookup "$__bs_obj_gc" g "$2"; then
    __bs_obj_gf=$__bs_obj_val
    command -v "$__bs_obj_gf" >/dev/null 2>&1 || return 1
    "$__bs_obj_gf" "$1"
    return $?
  fi
  if ! bs_obj__lookup "$__bs_obj_gc" f "$2"; then
    printf 'bs_obj: unknown field: %s\n' "$2" >&2
    return 1
  fi
  bs_map_get_to "objI${1#o}" "$2" __bs_obj_gv || return 1
  printf '%s\n' "$__bs_obj_gv"
  return 0
}

# @description Записать поле: приватное — отказ (3), readonly вне init — отказ (3),
#   свойство — сеттер, иначе запись; после успешной записи вызывается наблюдатель.
#   Write a field: private — refuse (3), readonly outside init — refuse (3),
#   property — the setter, otherwise a plain write; a watcher runs after a successful write.
# @param $1 id / ID
# @param $2 field / поле
# @param $3 value / значение
bs_obj_set() {
  bs_obj_alive "${1-}" || return 1
  bs_obj__name "${2-}" || return 2
  bs_obj__reserved "${2-}" || return 2
  bs_map_get_to "objI${1#o}" class __bs_obj_sc || return 1
  if bs_obj__lookup "$__bs_obj_sc" pr "$2"; then
    printf 'bs_obj: private field: %s\n' "$2" >&2
    return 3
  fi
  if bs_obj__lookup "$__bs_obj_sc" ro "$2"; then
    if ! bs_map_has "objI${1#o}" __init; then
      printf 'bs_obj: readonly field: %s\n' "$2" >&2
      return 3
    fi
  fi
  if bs_obj__lookup "$__bs_obj_sc" p "$2"; then
    __bs_obj_sf=$__bs_obj_val
    command -v "$__bs_obj_sf" >/dev/null 2>&1 || return 1
    # Сеттер — пользовательский код: класс и старое значение сохраняются по глубине
    # The setter is user code: the class and the old value are saved by depth
    __bs_obj_d=$((__bs_obj_d + 1))
    eval "__bs_obj_scl_${__bs_obj_d}=\${__bs_obj_sc}"
    bs_map_get_to "objI${1#o}" "$2" __bs_obj_so || __bs_obj_so=''
    eval "__bs_obj_sov_${__bs_obj_d}=\${__bs_obj_so}"
    if "$__bs_obj_sf" "$1" "${3-}"; then
      :
    else
      __bs_obj_srs=$?
      __bs_obj_d=$((__bs_obj_d - 1))
      return "$__bs_obj_srs"
    fi
    eval "__bs_obj_sc=\${__bs_obj_scl_${__bs_obj_d}}"
    eval "__bs_obj_so=\${__bs_obj_sov_${__bs_obj_d}}"
    __bs_obj_d=$((__bs_obj_d - 1))
    bs_map_get_to "objI${1#o}" "$2" __bs_obj_sn || __bs_obj_sn=''
    bs_obj__notify "$1" "$__bs_obj_sc" "$2" "$__bs_obj_so" "$__bs_obj_sn"
    return 0
  fi
  if ! bs_obj__lookup "$__bs_obj_sc" f "$2"; then
    printf 'bs_obj: unknown field: %s\n' "$2" >&2
    return 1
  fi
  bs_map_get_to "objI${1#o}" "$2" __bs_obj_so || __bs_obj_so=''
  bs_map_set "objI${1#o}" "$2" "${3-}"
  bs_obj__notify "$1" "$__bs_obj_sc" "$2" "$__bs_obj_so" "${3-}"
  return 0
}

# @description Поле объявлено в классе объекта (статус) / Whether the field is declared in the object's class (status)
# @param $1 id / ID
# @param $2 field / поле
bs_obj_has() {
  bs_obj_alive "${1-}" || return 1
  bs_obj__name "${2-}" || return 2
  bs_map_get_to "objI${1#o}" class __bs_obj_hc || return 1
  bs_obj__lookup "$__bs_obj_hc" f "$2"
}

# @description Имена полей объекта (свой класс, затем родители; без повторов) /
#   The object's field names (own class, then parents; no duplicates)
# @param $1 id / ID
# @stdout one name per line / по имени в строке
bs_obj_fields() {
  bs_obj_alive "${1-}" || return 1
  bs_map_get_to "objI${1#o}" class __bs_obj_fc || return 1
  __bs_obj_d=$((__bs_obj_d + 1))
  bs_arr_new "objF${__bs_obj_d}"
  __bs_obj_fh=0
  while [ -n "$__bs_obj_fc" ] && [ "$__bs_obj_fh" -lt 32 ]; do
    bs_map_each "objC${__bs_obj_fc}" bs_obj__fields_cb
    bs_map_get_to "objC${__bs_obj_fc}" parent __bs_obj_fc || __bs_obj_fc=''
    __bs_obj_fh=$((__bs_obj_fh + 1))
  done
  eval "$(bs_arr_to_args "objF${__bs_obj_d}")"
  for __bs_obj_ff in "$@"; do
    printf '%s\n' "$__bs_obj_ff"
  done
  bs_arr_clear "objF${__bs_obj_d}"
  __bs_obj_d=$((__bs_obj_d - 1))
  return 0
}

# @description Низкий уровень: прочитать поле без проверок приватности (для методов класса) /
#   Low level: read a field without privacy checks (for the class methods)
# @param $1 id / ID
# @param $2 field / поле
# @stdout value / значение
bs_obj_raw_get() {
  bs_obj_alive "${1-}" || return 1
  bs_obj__name "${2-}" || return 2
  bs_map_get_to "objI${1#o}" "$2" __bs_obj_val || return 1
  printf '%s\n' "$__bs_obj_val"
  return 0
}

# @description Низкий уровень: записать поле без проверок приватности/readonly и без
#   наблюдателя (для методов класса и сеттеров свойств) /
#   Low level: write a field without privacy/readonly checks and without a watcher
#   (for class methods and property setters)
# @param $1 id / ID
# @param $2 field / поле
# @param $3 value / значение
bs_obj_raw_set() {
  bs_obj_alive "${1-}" || return 1
  bs_obj__name "${2-}" || return 2
  bs_obj__reserved "${2-}" || return 2
  bs_map_set "objI${1#o}" "$2" "${3-}"
  return 0
}

# Вызов методов / Method calls

# @description Вызвать метод экземпляра: поиск в цепочке классов, затем делегирование
#   по полям-объектам (префикс d:). Метод получает ID первым аргументом.
#   Call an instance method: lookup in the class chain, then delegation through
#   object fields (the d: prefix). The method receives the ID as its first argument.
# @param $1 id / ID
# @param $2 method / метод
# @param $@ arguments / аргументы
# @returns статус метода; 1 нет объекта/метода; 2 плохое имя / the method's status; 1 no object/method; 2 bad name
bs_obj_call() {
  bs_obj_alive "${1-}" || return 1
  bs_obj__name "${2-}" || return 2
  __bs_obj_ci=$1
  __bs_obj_cm=$2
  shift 2
  # Флаг лимита сбрасывает только самый внешний вызов: вложенные не стирают диагноз
  # Only the outermost call resets the limit flag: nested calls do not wipe the diagnosis
  if [ "$__bs_obj_cd" = 0 ]; then
    __bs_obj_climit=0
  fi
  bs_map_get_to "objI${__bs_obj_ci#o}" class __bs_obj_cc || return 1
  if bs_obj__lookup "$__bs_obj_cc" m "$__bs_obj_cm"; then
    __bs_obj_cf=$__bs_obj_val
    if ! command -v "$__bs_obj_cf" >/dev/null 2>&1; then
      printf 'bs_obj: method function not found: %s\n' "$__bs_obj_cf" >&2
      return 1
    fi
    "$__bs_obj_cf" "$__bs_obj_ci" "$@"
    return $?
  fi
  # Делегирование: поля-объекты своего класса, затем родителей; аргументы сохраняются в objA<N>
  # Delegation: object fields of the own class, then parents; the arguments are kept in objA<N>
  __bs_obj_d=$((__bs_obj_d + 1))
  bs_arr_new "objA${__bs_obj_d}"
  for __bs_obj_ca in "$@"; do
    bs_arr_push "objA${__bs_obj_d}" "$__bs_obj_ca"
  done
  __bs_obj_cd2=$__bs_obj_cc
  __bs_obj_ch=0
  while [ -n "$__bs_obj_cd2" ] && [ "$__bs_obj_ch" -lt 32 ]; do
    __bs_obj_cn=$(bs_arr_len "objD${__bs_obj_cd2}")
    if [ "$__bs_obj_cn" -gt 0 ]; then
      eval "$(bs_arr_to_args "objD${__bs_obj_cd2}")"
      for __bs_obj_cfl in "$@"; do
        if bs_map_get_to "objI${__bs_obj_ci#o}" "$__bs_obj_cfl" __bs_obj_ct && bs_obj_alive "$__bs_obj_ct"; then
          if [ "$__bs_obj_cd" -ge 16 ]; then
            __bs_obj_climit=1
          fi
          if [ "$__bs_obj_cd" -lt 16 ]; then
            eval "$(bs_arr_to_args "objA${__bs_obj_d}")"
            # Состояние внешнего цикла сохраняется: вложенный bs_obj_call использует
            # те же имена __bs_obj_ci/cm/cd2/ch и затрёт их
            # The outer loop state is saved: the nested bs_obj_call uses the same
            # __bs_obj_ci/cm/cd2/ch names and would clobber them
            eval "__bs_obj_sci_${__bs_obj_d}=\${__bs_obj_ci}"
            eval "__bs_obj_scm_${__bs_obj_d}=\${__bs_obj_cm}"
            eval "__bs_obj_scc_${__bs_obj_d}=\${__bs_obj_cd2}"
            eval "__bs_obj_sch_${__bs_obj_d}=\${__bs_obj_ch}"
            __bs_obj_cd=$((__bs_obj_cd + 1))
            if bs_obj_call "$__bs_obj_ct" "$__bs_obj_cm" "$@"; then
              __bs_obj_cr=0
            else
              __bs_obj_cr=$?
            fi
            __bs_obj_cd=$((__bs_obj_cd - 1))
            eval "__bs_obj_ci=\${__bs_obj_sci_${__bs_obj_d}}"
            eval "__bs_obj_cm=\${__bs_obj_scm_${__bs_obj_d}}"
            eval "__bs_obj_cd2=\${__bs_obj_scc_${__bs_obj_d}}"
            eval "__bs_obj_ch=\${__bs_obj_sch_${__bs_obj_d}}"
            if [ "$__bs_obj_cr" = 0 ]; then
              bs_arr_clear "objA${__bs_obj_d}"
              __bs_obj_d=$((__bs_obj_d - 1))
              return 0
            fi
            # Код 1 — «нет метода»: пробуем следующее делегирование; прочие коды — наружу
            # Code 1 means "no method": try the next delegation; other codes go out
            if [ "$__bs_obj_cr" -ne 1 ]; then
              bs_arr_clear "objA${__bs_obj_d}"
              __bs_obj_d=$((__bs_obj_d - 1))
              return "$__bs_obj_cr"
            fi
          fi
        fi
      done
    fi
    bs_map_get_to "objC${__bs_obj_cd2}" parent __bs_obj_cd2 || __bs_obj_cd2=''
    __bs_obj_ch=$((__bs_obj_ch + 1))
  done
  bs_arr_clear "objA${__bs_obj_d}"
  __bs_obj_d=$((__bs_obj_d - 1))
  # Внутри попытки делегирования (__bs_obj_cd > 0) сообщение не печатается: вызывающий
  # попробует следующее поле; наружу оно выходит только от самого внешнего вызова
  # Inside a delegation attempt (__bs_obj_cd > 0) the message is not printed: the
  # caller will try the next field; it goes out only from the outermost call
  if [ "$__bs_obj_cd" = 0 ]; then
    if [ "$__bs_obj_climit" = 1 ]; then
      printf 'bs_obj: delegation limit (16) reached for %s on %s\n' "$__bs_obj_cm" "$__bs_obj_ci" >&2
    else
      printf 'bs_obj: no method %s on %s\n' "$__bs_obj_cm" "$__bs_obj_ci" >&2
    fi
  fi
  return 1
}

# Члены типа / Type members

# @description Прочитать общее поле или константу типа (по цепочке классов) /
#   Read a shared field or a type constant (along the class chain)
# @param $1 class / класс
# @param $2 name / имя
# @stdout value / значение
bs_obj_type_get() {
  bs_obj__class_exists "${1-}" || return $?
  bs_obj__name "${2-}" || return 2
  if bs_obj__lookup "$1" s "$2"; then
    printf '%s\n' "$__bs_obj_val"
    return 0
  fi
  if bs_obj__lookup "$1" k "$2"; then
    printf '%s\n' "$__bs_obj_val"
    return 0
  fi
  return 1
}

# @description Записать общее поле типа; константа — отказ (3) /
#   Write a shared type field; a constant — refuse (3)
# @param $1 class / класс
# @param $2 name / имя
# @param $3 value / значение
bs_obj_type_set() {
  bs_obj__class_exists "${1-}" || return $?
  bs_obj__name "${2-}" || return 2
  if bs_obj__lookup "$1" k "$2"; then
    printf 'bs_obj: constant: %s\n' "$2" >&2
    return 3
  fi
  if ! bs_obj__lookup "$1" s "$2"; then
    printf 'bs_obj: unknown shared field: %s\n' "$2" >&2
    return 1
  fi
  bs_map_set "objC${__bs_obj_own}" "s:${2}" "${3-}"
  return 0
}

# @description Вызвать метод типа (по цепочке классов); функция получает класс первым аргументом /
#   Call a type method (along the class chain); the function receives the class as its first argument
# @param $1 class / класс
# @param $2 method / метод
# @param $@ arguments / аргументы
bs_obj_type_call() {
  bs_obj__class_exists "${1-}" || return $?
  bs_obj__name "${2-}" || return 2
  __bs_obj_tc=$1
  __bs_obj_tm=$2
  shift 2
  if ! bs_obj__lookup "$__bs_obj_tc" t "$__bs_obj_tm"; then
    printf 'bs_obj: no type method %s on %s\n' "$__bs_obj_tm" "$__bs_obj_tc" >&2
    return 1
  fi
  __bs_obj_tf=$__bs_obj_val
  if ! command -v "$__bs_obj_tf" >/dev/null 2>&1; then
    printf 'bs_obj: method function not found: %s\n' "$__bs_obj_tf" >&2
    return 1
  fi
  "$__bs_obj_tf" "$__bs_obj_tc" "$@"
  return $?
}

# Идентичность и равенство / Identity and equality

# @description Идентичность: один и тот же живой объект (статус) /
#   Identity: one and the same live object (status)
# @param $1 id / ID
# @param $2 id / ID
bs_obj_same() {
  bs_obj_alive "${1-}" || return 1
  bs_obj_alive "${2-}" || return 1
  [ "$1" = "$2" ]
}

# @description Равенство содержимого: тот же класс и те же значения полей (статус).
#   Вычисляемые свойства не сравниваются — только сохранённые поля.
#   Content equality: the same class and the same field values (status).
#   Computed properties are not compared — only stored fields.
# @param $1 id / ID
# @param $2 id / ID
bs_obj_equal() {
  bs_obj_alive "${1-}" || return 1
  bs_obj_alive "${2-}" || return 1
  bs_map_get_to "objI${1#o}" class __bs_obj_ea || return 1
  bs_map_get_to "objI${2#o}" class __bs_obj_eb || return 1
  if [ "$__bs_obj_ea" != "$__bs_obj_eb" ]; then
    return 1
  fi
  __bs_obj_ena=$(bs_map_count "objI${1#o}")
  __bs_obj_enb=$(bs_map_count "objI${2#o}")
  # Служебный __init не считается: сравнение с эталоном внутри init должно работать
  # The service __init is not counted: comparing against a reference inside init must work
  if bs_map_has "objI${1#o}" __init; then
    __bs_obj_ena=$((__bs_obj_ena - 1))
  fi
  if bs_map_has "objI${2#o}" __init; then
    __bs_obj_enb=$((__bs_obj_enb - 1))
  fi
  if [ "$__bs_obj_ena" != "$__bs_obj_enb" ]; then
    return 1
  fi
  __bs_obj_d=$((__bs_obj_d + 1))
  __bs_obj_em="objI${2#o}"
  eval "__bs_obj_eb_${__bs_obj_d}=\${__bs_obj_em}"
  __bs_obj_eqok=1
  bs_map_each "objI${1#o}" bs_obj__equal_cb
  __bs_obj_d=$((__bs_obj_d - 1))
  [ "$__bs_obj_eqok" = 1 ]
}

# Псевдонимы object::* — только в bash и zsh / The object::* aliases — bash and zsh only
bs_shell_alias bs_obj_class object::class
bs_shell_alias bs_obj_field object::field
bs_shell_alias bs_obj_shared object::shared
bs_shell_alias bs_obj_const object::const
bs_shell_alias bs_obj_method object::method
bs_shell_alias bs_obj_type_method object::type_method
bs_shell_alias bs_obj_property object::property
bs_shell_alias bs_obj_readonly object::readonly
bs_shell_alias bs_obj_private object::private
bs_shell_alias bs_obj_watch object::watch
bs_shell_alias bs_obj_delegate object::delegate
bs_shell_alias bs_obj_contract object::contract
bs_shell_alias bs_obj_check object::check
bs_shell_alias bs_obj_new object::new
bs_shell_alias bs_obj_new_to object::new_to
bs_shell_alias bs_obj_destroy object::destroy
bs_shell_alias bs_obj_destroy_all object::destroy_all
bs_shell_alias bs_obj_count object::count
bs_shell_alias bs_obj_alive object::alive
bs_shell_alias bs_obj_class_of object::class_of
bs_shell_alias bs_obj_is_a object::is_a
bs_shell_alias bs_obj_get object::get
bs_shell_alias bs_obj_set object::set
bs_shell_alias bs_obj_has object::has
bs_shell_alias bs_obj_fields object::fields
bs_shell_alias bs_obj_raw_get object::raw_get
bs_shell_alias bs_obj_raw_set object::raw_set
bs_shell_alias bs_obj_call object::call
bs_shell_alias bs_obj_type_get object::type_get
bs_shell_alias bs_obj_type_set object::type_set
bs_shell_alias bs_obj_type_call object::type_call
bs_shell_alias bs_obj_same object::same
bs_shell_alias bs_obj_equal object::equal
