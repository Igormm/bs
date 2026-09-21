#!/usr/bin/env bs
# shellcheck shell=bash
# lib/system/sensor.sh — Touch/sensor input device access via evdev+sysfs
# lib/system/sensor.sh — доступ к сенсорным устройствам ввода через evdev и sysfs
#
# Tier / Ярус: Linux-only (evdev, /sys/class/input). Деградация: чистый
# E_*-код при отсутствии доступа; проверка наличия /sys перед чтением.
#
# @depends core/const, core/logger, core/utils

# Source Guard / Защита от повторной загрузки
bs::guard "SYSTEM_SENSOR" || return 0

# Dependencies / Зависимости
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh"

# Metadata / Метаданные
# shellcheck disable=SC2034
declare -g SYSTEM_SENSOR_VERSION="1.0.0"
# shellcheck disable=SC2034
declare -g SYSTEM_SENSOR_LOADED="1"

# Test hooks: переопределяются в юнит-тестах (см. HW_DMI_PATH в lib/system/hw)
: "${SENSOR_INPUT_DIR:=/sys/class/input}"
: "${SENSOR_DEV_DIR:=/dev/input}"
: "${SENSOR_EVENT_SIZE:=}"   # пусто — авто-определение по LONG_BIT

# ==========================================
# Справочники evdev / evdev lookup tables
# ==========================================

# @description Имя типа события EV_* / Event type name
# @param $1 Числовой тип / Numeric type
# @stdout Имя или EV_<n> / Name or EV_<n>
sensor::type_name() {
    local -r t="${1}"
    case "${t}" in
        0)  printf 'EV_SYN' ;;
        1)  printf 'EV_KEY' ;;
        2)  printf 'EV_REL' ;;
        3)  printf 'EV_ABS' ;;
        4)  printf 'EV_MSC' ;;
        5)  printf 'EV_SW' ;;
        17) printf 'EV_LED' ;;
        18) printf 'EV_SND' ;;
        20) printf 'EV_FF' ;;
        *)  printf 'EV_%s' "${t}" ;;
    esac
}

# @description Имя кода осей EV_ABS / EV_ABS axis code name
# @param $1 Числовой код / Numeric code
# @stdout Имя или ABS_<n> / Name or ABS_<n>
sensor::abs_name() {
    local -r c="${1}"
    case "${c}" in
        0)  printf 'ABS_X' ;;
        1)  printf 'ABS_Y' ;;
        2)  printf 'ABS_Z' ;;
        7)  printf 'ABS_RX' ;;
        8)  printf 'ABS_RY' ;;
        9)  printf 'ABS_RZ' ;;
        16) printf 'ABS_HAT0X' ;;
        17) printf 'ABS_HAT0Y' ;;
        47) printf 'ABS_MT_SLOT' ;;
        48) printf 'ABS_MT_TOOL_TYPE' ;;
        53) printf 'ABS_MT_POSITION_X' ;;
        54) printf 'ABS_MT_POSITION_Y' ;;
        55) printf 'ABS_MT_PRESSURE' ;;
        57) printf 'ABS_MT_TOUCH_MAJOR' ;;
        58) printf 'ABS_MT_TOUCH_MINOR' ;;
        63) printf 'ABS_MT_TRACKING_ID' ;;
        *)  printf 'ABS_%s' "${c}" ;;
    esac
}

# @description Имя кода кнопки EV_KEY (только сенсорно-значимые) / EV_KEY code name
# @param $1 Числовой код / Numeric code
# @stdout Имя или KEY_<n> / Name or KEY_<n>
sensor::key_name() {
    local -r c="${1}"
    case "${c}" in
        330) printf 'BTN_TOUCH' ;;
        331) printf 'BTN_STYLUS' ;;
        332) printf 'BTN_STYLUS2' ;;
        333) printf 'BTN_TOOL_DOUBLETAP' ;;
        334) printf 'BTN_TOOL_TRIPLETAP' ;;
        335) printf 'BTN_TOOL_QUADTAP' ;;
        323) printf 'BTN_TOOL_FINGER' ;;
        325) printf 'BTN_TOOL_DOUBLETAP_ALT' ;;
        *)   printf 'KEY_%s' "${c}" ;;
    esac
}

# @description Символическое имя кода по типу / Symbolic code name by event type
# @param $1 Тип / Type
# @param $2 Код / Code
sensor::code_name() {
    local -r t="${1}" c="${2}"
    case "${t}" in
        1) sensor::key_name "${c}" ;;
        3) sensor::abs_name "${c}" ;;
        2)
            case "${c}" in
                0) printf 'REL_X' ;;
                1) printf 'REL_Y' ;;
                *) printf 'REL_%s' "${c}" ;;
            esac ;;
        *) printf 'CODE_%s' "${c}" ;;
    esac
}

# ==========================================
# Обслуживание устройств / Device discovery
# ==========================================

# @description Размер записи input_event в байтах / input_event record size
#   struct input_event = 2*sizeof(long) + u16 type + u16 code + s32 value
#   64-бит: 24, 32-бит: 16. Хук SENSOR_EVENT_SIZE для тестов.
# @stdout Число байт / Byte count
sensor::record_size() {
    if is::not_empty "${SENSOR_EVENT_SIZE}"; then
        printf '%s\n' "${SENSOR_EVENT_SIZE}"
        return "${E_SUCCESS}"
    fi
    local -r bits="$(utils::quiet_err getconf LONG_BIT)"
    case "${bits}" in
        32) printf '16\n' ;;
        64) printf '24\n' ;;
        *)  printf '24\n' ;;
    esac
}

# @description Системное имя event-устройства / Sysfs name of an event device
# @param $1 eventN или полный путь / eventN or full /dev path
# @stdout Имя из sysfs или пустая строка / Sysfs name or empty
sensor::__name_of() {
    local -r dev="$(sensor::__event_of "${1}")"
    local -r f="${SENSOR_INPUT_DIR}/${dev}/device/name"
    [[ -f "${f}" ]] && utils::quiet_err head -n1 "${f}" || true
}

# @description Нормализовать аргумент до eventN / Normalize arg to eventN
# @private
sensor::__event_of() {
    local arg="${1:-}"
    arg="${arg##*/}"
    printf '%s\n' "${arg}"
}

# @description Список event-устройств: "eventN<TAB>имя" / List event devices
# @param $1 [pattern] Подстрока фильтра (регистронезависимо) / Filter substring
# @stdout Строки "eventN\tname" / Lines "eventN\tname"
# @return E_SUCCESS, если найдено хотя бы одно / E_SUCCESS if any found
# @example
#   sensor::devices
#   sensor::devices touch
sensor::devices() {
    local -r pattern="${1:-}"
    local -i found=0
    local ev d name

    [[ -d "${SENSOR_INPUT_DIR}" ]] || {
        log::warn "No ${SENSOR_INPUT_DIR} on this platform"
        return "${LIB_ERROR_UNSUPPORTED_OS}"
    }
    for d in "${SENSOR_INPUT_DIR}"/event*; do
        [[ -d "${d}" ]] || continue
        ev="$(basename -- "${d}")"
        name="$(sensor::__name_of "${ev}")"
        if is::not_empty "${pattern}"; then
            str::contains "$(str::lower "${name}")" "$(str::lower "${pattern}")" || continue
        fi
        printf '%s\t%s\n' "${ev}" "${name}"
        found+=1
    done
    (( found > 0 )) && return "${E_SUCCESS}"
    return "${LIB_ERROR_FILE_NOT_FOUND}"
}

# @description Путь к device-файлу / Path of the device node
# @param $1 eventN / eventN
# @stdout /dev/input/eventN (или существующий by-path) / device path
sensor::device_path() {
    local -r ev="$(sensor::__event_of "${1:-}")"
    printf '%s/%s\n' "${SENSOR_DEV_DIR}" "${ev}"
}

# @description Сводка по устройству: name/phys/uniq/возможности / Device info
# @param $1 eventN или путь к устройству / eventN or device path
# @stdout k=v строки / k=v lines
# @return E_INVALID если устройства нет / E_INVALID when absent
# @example
#   sensor::info event5
sensor::info() {
    local -r ev="$(sensor::__event_of "${1:-}")"
    local -r dir="${SENSOR_INPUT_DIR}/${ev}"

    [[ -d "${dir}" ]] || {
        error::throw "Unknown input device: ${ev}" "${LIB_ERROR_FILE_NOT_FOUND}"
        return "${LIB_ERROR_FILE_NOT_FOUND}"
    }
    printf 'device=%s\n' "${ev}"
    printf 'path=%s\n' "$(sensor::device_path "${ev}")"
    printf 'name=%s\n' "$(sensor::__name_of "${ev}")"
    local f
    for f in phys uniq; do
        [[ -f "${dir}/device/${f}" ]] && printf '%s=%s\n' "${f}" "$(utils::quiet_err head -n1 "${dir}/device/${f}")"
    done
    printf 'readable=%s\n' "$(is::readable "$(sensor::device_path "${ev}")" && printf yes || printf no)"
    printf 'capabilities_ev=%s\n' "$(utils::quiet_err cat "${dir}/device/capabilities/ev" 2>/dev/null)"
    # WRAPPER-CANDIDATE: utils::quiet_err already used; the trailing 2>/dev/null is redundant here (double suppression) — drop one / кандидат-обёртка: utils::quiet_err уже применён, хвост 2>/dev/null дублирует подавление
    printf 'capabilities_key=%s\n' "$(utils::quiet_err cat "${dir}/device/capabilities/key" 2>/dev/null)"
    printf 'capabilities_abs=%s\n' "$(utils::quiet_err cat "${dir}/device/capabilities/abs" 2>/dev/null)"
    return "${E_SUCCESS}"
}

# @description Декодировать hex-битмаask sysfs capabilities в имена / Decode caps
# @param $1 eventN / eventN
# @param $2 [kind] ev|key|abs|rel|sw|msc (по умолчанию ev) / kind, default ev
# @stdout По одному имени в строке / One symbolic name per line
# @example
#   sensor::capabilities event5 abs
sensor::capabilities() {
    local -r ev="$(sensor::__event_of "${1:-}")"
    local -r kind="${2:-ev}"
    local -r f="${SENSOR_INPUT_DIR}/${ev}/device/capabilities/${kind}"

    [[ -f "${f}" ]] || {
        error::throw "No capabilities file: ${f}" "${LIB_ERROR_FILE_NOT_FOUND}"
        return "${LIB_ERROR_FILE_NOT_FOUND}"
    }
    # Sysfs печатает слова bitmask старшим первым, hex, через пробел
    # Sysfs prints bitmask words most-significant first, hex, space separated
    local -r raw="$(utils::quiet_err tr 'A-F' 'a-f' < "${f}")"
    local -a words=()
    IFS=' ' read -r -a words <<< "${raw}"
    local -i word value bit idx
    for (( word = 0; word < ${#words[@]}; word++ )); do
        value=$(( 16#${words[word]} ))
        for (( bit = 0; bit < 64; bit++ )); do
            (( (value >> bit) & 1 )) || continue
            # старшее слово идёт первым: индекс = (кол-во_слов-1-word)*64+bit
            idx=$(( ( ${#words[@]} - 1 - word ) * 64 + bit ))
            case "${kind}" in
                ev)  sensor::type_name "${idx}" ;;
                abs) sensor::abs_name "${idx}" ;;
                key) sensor::key_name "${idx}" ;;
                *)   printf '%s_%s\n' "${kind}" "${idx}" ;;
            esac
            printf '\n'
        done
    done
    return "${E_SUCCESS}"
}

# @description Диапазон оси из sysfs: "min max fuzz flat" / Axis range
# @param $1 eventN / eventN
# @param $2 Ось (число или ABS_*) / Axis (number or ABS_*)
# @stdout "min max fuzz flat" / values
# @return LIB_ERROR_FILE_NOT_FOUND если атрибута нет / when attribute absent
sensor::abs_range() {
    local ev="${1:-}" axis="${2:-}"
    ev="$(sensor::__event_of "${ev}")"
    if ! is::number "${axis}"; then
        case "${axis}" in
            ABS_X) axis=0 ;;
            ABS_Y) axis=1 ;;
            ABS_MT_POSITION_X) axis=53 ;;
            ABS_MT_POSITION_Y) axis=54 ;;
            ABS_MT_PRESSURE) axis=55 ;;
            ABS_MT_TOUCH_MAJOR) axis=57 ;;
            *)
                error::throw "Unknown axis: ${axis}" "${E_INVALID}"
                return "${E_INVALID}" ;;
        esac
    fi
    local -r dir="${SENSOR_INPUT_DIR}/${ev}/device/attributes/abs${axis}"
    [[ -d "${dir}" ]] || {
        return "${LIB_ERROR_FILE_NOT_FOUND}"
    }
    local min max fuzz flat
    min="$(utils::quiet_err cat "${dir}/min" 2>/dev/null)"
    max="$(utils::quiet_err cat "${dir}/max" 2>/dev/null)"
    fuzz="$(utils::quiet_err cat "${dir}/fuzz" 2>/dev/null)"
    flat="$(utils::quiet_err cat "${dir}/flat" 2>/dev/null)"
    printf '%s %s %s %s\n' "${min:--1}" "${max:--1}" "${fuzz:-0}" "${flat:-0}"
}

# ==========================================
# Чтение событий / Event reading
# ==========================================

# @description Проверить доступность устройства для чтения / Check readability
# @param $1 eventN / eventN
# @return 0 ok; LIB_ERROR_* коды / codes
sensor::check() {
    local -r ev="$(sensor::__event_of "${1:-}")"
    [[ -d "${SENSOR_INPUT_DIR}/${ev}" ]] || return "${LIB_ERROR_FILE_NOT_FOUND}"
    local -r path="$(sensor::device_path "${ev}")"
    is::exists "${path}" || return "${LIB_ERROR_FILE_NOT_FOUND}"
    is::readable "${path}" || return "${LIB_ERROR_PERMISSION_DENIED}"
    return "${E_SUCCESS}"
}

# @private
# @description Раскодировать одну запись из массива байтов в "sec usec type code value"
# @description Decode one record from a byte array to "sec usec type code value"
sensor::__decode_record() {
    local -r size="$(sensor::record_size)"
    local -n src_bytes="${1}"
    (( ${#src_bytes[@]} < size )) && return "${E_INVALID}"
    local -i long=4 type_at
    (( size == 24 )) && long=8
    type_at=$(( 2 * long ))

    local -i sec usec type code value
    # little-endian сборка / LE assembly (берём младшие 4 байта поля)
    sec=$(( src_bytes[0] + (src_bytes[1] << 8) + (src_bytes[2] << 16) + (src_bytes[3] << 24) ))
    usec=$(( src_bytes[long] + (src_bytes[long + 1] << 8) + (src_bytes[long + 2] << 16) + (src_bytes[long + 3] << 24) ))
    type=$(( src_bytes[type_at] + (src_bytes[type_at + 1] << 8) ))
    code=$(( src_bytes[type_at + 2] + (src_bytes[type_at + 3] << 8) ))
    value=$(( src_bytes[type_at + 4] + (src_bytes[type_at + 5] << 8) + (src_bytes[type_at + 6] << 16) + (src_bytes[type_at + 7] << 24) ))
    (( value >= 2147483648 )) && value=$(( value - 4294967296 ))
    printf '%s %s %s %s %s\n' "${sec}" "${usec}" "${type}" "${code}" "${value}"
}

# @description Читать поток событий: "sec usec type code value" по строке
#   Читает сырые записи input_event через dd+od (без внешних парсеров).
# @description Stream decoded events, one per line, from evdev via dd+od.
# @param $1 eventN или путь / eventN or path
# @param $2 [count] Сколько записей (по умолчанию бесконечно) / how many
# @stdout "sec usec type code value" lines
# @return LIB_ERROR_* при недоступности / when unavailable
# @example
#   sensor::events event5 10
sensor::events() {
    local -r dev="${1:-}"
    local -r count="${2:-}"
    local path

    if [[ "${dev}" == /* ]]; then
        path="${dev}"
    else
        path="$(sensor::device_path "${dev}")"
    fi
    is::readable "${path}" || {
        error::throw "Sensor not readable (perms?): ${path}" "${LIB_ERROR_PERMISSION_DENIED}"
        return "${LIB_ERROR_PERMISSION_DENIED}"
    }
    local -r size="$(sensor::record_size)"
    local -a dd_args=(if="${path}" bs="${size}")
    is::not_empty "${count}" && dd_args+=(count="${count}")

    local -a bytes=()
    local -i n=0 b
    local line
    while IFS= read -r line; do
        # od выводит по 16 unsigned-байт на строку / od prints 16 bytes per line
        for b in ${line}; do
            bytes+=("${b}")
            (( ${#bytes[@]} == size )) || continue
            sensor::__decode_record bytes || return "${E_INVALID}"
            bytes=()
            n=$(( n + 1 ))
            if is::not_empty "${count}" && (( n >= count )); then
                return "${E_SUCCESS}"
            fi
        done
    done < <(utils::quiet_err dd "${dd_args[@]}" 2>/dev/null | od -An -tu1 -v)
    return "${E_SUCCESS}"
}

# @description Увидеть ли событие за таймаут: первая строка события / detect event
# @param $1 eventN / eventN
# @param $2 Таймаут, сек / timeout seconds
# @stdout Строка события, если пришло / event line if arrived
# @return E_SUCCESS событие есть; LIB_ERROR_TIMEOUT таймаут; LIB_ERROR_* ошибки
sensor::detect() {
    local -r ev="${1:-}"
    local -r timeout="${2:-2}"
    sensor::check "${ev}" || return "${E_ERROR}"

    local line=""
    # read -t даёт переносной таймаут без внешнего timeout (нет на macOS/busybox)
    # read -t gives a portable timeout without the external timeout command
    while IFS= read -r -t "${timeout}" line; do
        is::not_empty "${line}" && {
            printf '%s\n' "${line}"
            return "${E_SUCCESS}"
        }
    done < <(sensor::events "${ev}")
    return "${LIB_ERROR_TIMEOUT}"
}

# ==========================================
# Диагностика / Diagnostics
# ==========================================

# @description Полный отчёт диагностики сенсора / Full sensor diagnostic report
# @param $1 eventN / eventN
# @param $2 [seconds] Окно живого наблюдения (0 = пропустить) / live window
# @stdout Строки "[PASS|WARN|FAIL|INFO] check — детали" / report lines
# @return E_SUCCESS если нет FAIL / E_SUCCESS when no FAIL
# @example
#   sensor::diagnose event5 3
sensor::diagnose() {
    local -r ev="$(sensor::__event_of "${1:-}")"
    local -r window="${2:-3}"
    local -i fails=0 warns=0
    local name path

    name="$(sensor::__name_of "${ev}")"
    path="$(sensor::device_path "${ev}")"
    printf '=== sensor::diagnose %s ("%s") ===\n' "${ev}" "${name}"
    printf '[INFO] device=%s record_size=%sB\n' "${path}" "$(sensor::record_size)"

    # 1. существование / presence
    if [[ -d "${SENSOR_INPUT_DIR}/${ev}" ]]; then
        printf '[PASS] sysfs-устройство присутствует\n'
    else
        printf '[FAIL] нет /sys/class/input/%s\n' "${ev}"
        fails+=1
    fi

    # 2. доступ / permissions
    if is::readable "${path}"; then
        printf '[PASS] %s читается\n' "${path}"
    else
        printf '[FAIL] %s не читается (добавьте пользователя в группу input)\n' "${path}"
        fails+=1
    fi

    # 3. возможности / capabilities
    local caps_abs caps_ev
    caps_ev="$(utils::quiet_err cat "${SENSOR_INPUT_DIR}/${ev}/device/capabilities/ev" 2>/dev/null)"
    caps_abs="$(utils::quiet_err cat "${SENSOR_INPUT_DIR}/${ev}/device/capabilities/abs" 2>/dev/null)"
    if [[ $(( 16#${caps_ev:-0} & 8 )) -ne 0 ]]; then
        printf '[PASS] EV_ABS заявлен (оси: %s)\n' "${caps_abs:-?}"
    else
        printf '[WARN] EV_ABS не заявлен — это не сенсорная ось?\n'
        warns+=1
    fi
    if sensor::capabilities "${ev}" key 2>/dev/null | utils::quiet grep -qx BTN_TOUCH; then
        printf '[PASS] BTN_TOUCH присутствует\n'
    else
        printf '[WARN] нет BTN_TOUCH — касания могут не репортоваться\n'
        warns+=1
    fi

    # 4. диапазоны осей / axis ranges
    local range axis_ok=0
    for axis in 0 1 53 54; do
        if range="$(sensor::abs_range "${ev}" "${axis}" 2>/dev/null)"; then
            printf '[INFO] %s: min/max/fuzz/flat = %s\n' "$(sensor::abs_name "${axis}")" "${range}"
            axis_ok=1
        fi
    done
    (( axis_ok == 0 )) && printf '[INFO] per-axis атрибуты недоступны (нужен EVIOCGABS или live-наблюдение)\n'

    # 5. живые события / live event window
    if is::number "${window}" && (( window > 0 )) && is::readable "${path}"; then
        local -a events=()
        local line="" rem=""
        # общее окно наблюдения по дедлайну (read -t перезапускается на каждой линии)
        # overall window by deadline (read -t restarts per line)
        local -i deadline=$(( $(utils::now_ms) + window * 1000 ))
        while :; do
            rem=$(( deadline - $(utils::now_ms) ))
            (( rem > 0 )) || break
            if IFS= read -r -t "$(( rem / 1000 )).$(printf '%03d' "$(( rem % 1000 ))")" line; then
                is::not_empty "${line}" && events+=("${line}")
            else
                break
            fi
        done < <(sensor::events "${ev}")
        local -i n=${#events[@]}
        if (( n == 0 )); then
            printf '[WARN] за %ss нет ни одного события (коснитесь экрана или сенсор мёртв)\n' "${window}"
            warns+=1
        else
            printf '[PASS] поток событий: %d за %ss (~%d.%02d ev/s)\n' \
                "${n}" "${window}" "$(( n / window ))" "$(( (n * 100 / window) % 100 ))"
            sensor::__diag_axes "${events[@]}"
        fi
    fi

    printf '=== итог: FAIL=%d WARN=%d ===\n' "${fails}" "${warns}"
    (( fails == 0 )) && return "${E_SUCCESS}"
    return "${E_ERROR}"
}

# @private
# @description Анализ осевых значений из окна событий: диапазоны и "залипание"
# @description Analyze axis values across the live window: spans and stuck axes
sensor::__diag_axes() {
    local -a min=() max=() cnt=()
    local line t c v i
    local -i touches=0
    for line in "$@"; do
        read -r _ _ t c v <<< "${line}"
        case "${t}" in
            1) [[ "${c}" == 330 ]] && (( v == 1 )) && touches+=1 ;;
            3)
                i="${c}"
                if [[ -z "${cnt[i]:-}" ]]; then
                    cnt[i]=1; min[i]="${v}"; max[i]="${v}"
                else
                    (( v < min[i] )) && min[i]="${v}"
                    (( v > max[i] )) && max[i]="${v}"
                    cnt[i]=$(( cnt[i] + 1 ))
                fi
                ;;
        esac
    done
    for i in "${!cnt[@]}"; do
        # "залипание" — постоянное значение при достаточной выборке
        # "stuck" — constant value with a sufficient sample
        if [[ "${min[i]}" == "${max[i]}" ]] && (( cnt[i] >= 3 )); then
            printf '[WARN] %s залипает на %s за всё окно (%d событий)\n' \
                "$(sensor::abs_name "${i}")" "${min[i]}" "${cnt[i]}"
        else
            printf '[INFO] %s: наблюдалось %s..%s (%d)\n' \
                "$(sensor::abs_name "${i}")" "${min[i]}" "${max[i]}" "${cnt[i]}"
        fi
    done
    if (( touches > 0 )); then
        printf '[PASS] касаний за окно: %d\n' "${touches}"
    else
        printf '[INFO] касаний (BTN_TOUCH press) за окно: 0\n'
    fi
}
