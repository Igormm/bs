#!/usr/bin/env bs
# shellcheck shell=bash
# examples/passwordgenexample.sh — Password generator: /dev/urandom + args
# examples/passwordgenexample.sh — Генератор паролей: /dev/urandom + args
#
# Генерирует пароли из /dev/urandom с флагами --length, --count, --hex
# и оценкой стойкости. Help и completion — из дерева args.
# Generates passwords from /dev/urandom with --length, --count, --hex flags
# and a strength estimate. Help and completion come from the args tree.
#
# Попробуйте / Try it:
#   bs run examples/passwordgenexample.sh
#   bs run examples/passwordgenexample.sh --length 24 --count 5
#   bs run examples/passwordgenexample.sh --hex --length 32

# Запуск / Run:
#   bs run examples/passwordgenexample.sh [args]
#   ./examples/passwordgenexample.sh            # bs должен быть в PATH / bs must be in PATH

load "core/args"
load "lib/io/streams"

# Оценка стойкости по длине / Strength estimate by length
strength_label() {
    local length="${1}"

    if [[ "${length}" -lt 10 ]]; then
        io::streams::print "weak"
    elif [[ "${length}" -lt 16 ]]; then
        io::streams::print "good"
    elif [[ "${length}" -lt 24 ]]; then
        io::streams::print "strong"
    else
        io::streams::print "overkill"
    fi
}

main() {
    args::flag length value
    args::flag count value
    args::flag hex
    args::flag_describe length "Password length in characters (default: 16)"
    args::flag_describe count "How many passwords to generate (default: 3)"
    args::flag_describe hex "Hex output instead of base64"

    args::parse "$@" || exit "${E_INVALID}"
    [[ "${ARGS_HELP_REQUESTED}" == "1" ]] && exit "${E_SUCCESS}"

    local length count
    length="$(args::flag_get length || printf '16')"
    count="$(args::flag_get count || printf '3')"

    # Валидация чисел / Number validation
    if ! [[ "${length}" =~ ^[0-9]+$ ]] || [[ "${length}" -lt 4 ]]; then
        log::fatal "--length must be an integer >= 4, got: ${length}" || exit "${E_INVALID}"
    fi
    if ! [[ "${count}" =~ ^[0-9]+$ ]] || [[ "${count}" -lt 1 ]]; then
        log::fatal "--count must be a positive integer, got: ${count}" || exit "${E_INVALID}"
    fi

    log::header "Password generator / Генератор паролей"
    io::streams::printf '  %-4s %-40s %s\n' "No." "password" "strength"

    local i password
    for ((i = 1; i <= count; i++)); do
        if args::flag_get hex >/dev/null; then
            # hex: каждый байт — два символа / hex: two characters per byte
            password="$(io::streams::random_bytes $(( (length + 1) / 2 )) | od -An -tx1 | tr -d ' \n' | head -c "${length}")"
        else
            # base64: отрезаем до нужной длины / base64: cut to the requested length
            password="$(io::streams::random_bytes $(( length )) | base64 | head -c "${length}")"
        fi
        io::streams::printf '  %-4d %-40s %s\n' "${i}" "${password}" "$(strength_label "${length}")"
    done

    io::streams::eprint "hint: hex doubles the length per byte, base64 is denser"
}

main "$@"
