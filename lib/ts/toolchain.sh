#!/usr/bin/env bs
# shellcheck shell=bash
# lib/ts/toolchain.sh — TypeScript dev-toolchain detection and validation gates
# lib/ts/toolchain.sh — обнаружение TS-инструментария и верификационные гейты
#
# Ярус: кроссплатформенный (только внешние инструменты через utils::has);
# без node в системе — чистые коды ошибок, не падение.
# Tier: cross-platform; every capability is probed (utils::has), never assumed.
#
# @depends core/const, core/logger, core/utils

# Source Guard / Защита от повторной загрузки
bs::guard "TS_TOOLCHAIN" || return 0

# Dependencies / Зависимости
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh"

# Metadata / Метаданные
# shellcheck disable=SC2034
declare -g TS_TOOLCHAIN_VERSION="1.0.0"
# shellcheck disable=SC2034
declare -g TS_TOOLCHAIN_LOADED="1"

# Тестовые хуки / test hooks
: "${TS_RUNTIMES:=node bun deno}"
: "${TS_PACKAGE_MANAGERS:=npm pnpm yarn bun}"

# ==========================================
# Обнаружение рантаймов / runtime discovery
# ==========================================

# @description Версия рантайма TS (node/bun/deno), префикс v снят / runtime version
# @param $1 Имя бинаря / binary name
# @stdout "X.Y.Z" или пусто / version or empty
# @return E_SUCCESS | LIB_ERROR_DEPENDENCY_MISSING
ts::toolchain::runtime_version() {
    local -r bin="${1:?runtime name required}"
    utils::has "${bin}" || {
        return "${LIB_ERROR_DEPENDENCY_MISSING}"
    }
    local raw
    raw="$(utils::quiet_err "${bin}" --version 2>/dev/null)" || raw=""
    raw="${raw#v}"
    str::trim "${raw}"
}

# @description Найти доступный рантайм по приоритету / first available runtime
# @stdout Имя бинаря (node→bun→deno по умолчанию) / binary name
# @return E_SUCCESS | LIB_ERROR_DEPENDENCY_MISSING
ts::toolchain::detect_runtime() {
    local -a rts=()
    IFS=' ' read -r -a rts <<< "${TS_RUNTIMES}"
    local r
    for r in "${rts[@]}"; do
        utils::has "${r}" && {
            printf '%s\n' "${r}"
            return "${E_SUCCESS}"
        }
    done
    return "${LIB_ERROR_DEPENDENCY_MISSING}"
}

# @description Все рантаймы: "bin<TAB>version<TAB>path" / all runtimes
# @stdout Строки "bin\tver\tpath" (пустая версия, если не определилась)
ts::toolchain::runtimes() {
    local -a rts=()
    IFS=' ' read -r -a rts <<< "${TS_RUNTIMES}"
    local r ver path
    for r in "${rts[@]}"; do
        utils::has "${r}" || continue
        ver="$(ts::toolchain::runtime_version "${r}")" || continue
        path="$(command -v "${r}")"
        printf '%s\t%s\t%s\n' "${r}" "${ver}" "${path}"
    done
}

# @description Все пакетные менеджеры: "pm<TAB>version<TAB>path" / all package managers
ts::toolchain::package_managers() {
    local -a pms=()
    IFS=' ' read -r -a pms <<< "${TS_PACKAGE_MANAGERS}"
    local p ver path
    for p in "${pms[@]}"; do
        utils::has "${p}" || continue
        ver="$(utils::quiet_err "${p}" --version 2>/dev/null)" || ver=""
        ver="$(str::trim "$(printf '%s\n' "${ver}" | utils::quiet_err head -n1)")"
        [[ "${ver}" == v* ]] && ver="${ver#v}"
        path="$(command -v "${p}")"
        printf '%s\t%s\t%s\n' "${p}" "${ver}" "${path}"
    done
}

# @description Пакетный менеджер по лок-файлу проекта / pm from lockfile
# @param $1 [dir] Каталог проекта (по умолчанию .) / project dir
# @stdout npm|pnpm|yarn|bun
# @return LIB_ERROR_FILE_NOT_FOUND если лок-файла нет / no lockfile
ts::toolchain::lockfile_pm() {
    local -r dir="${1:-.}"
    local pair name
    for pair in "bun.lockb:bun" "pnpm-lock.yaml:pnpm" \
                "yarn.lock:yarn" "package-lock.json:npm" "npm-shrinkwrap.json:npm"; do
        name="${pair%%:*}"
        is::file "${dir}/${name}" || continue
        printf '%s\n' "${pair#*:}"
        return "${E_SUCCESS}"
    done
    return "${LIB_ERROR_FILE_NOT_FOUND}"
}

# ==========================================
# Структура проекта / project layout
# ==========================================

# @description Есть ли tsconfig в корне проекта / project has tsconfig
# @param $1 [dir] Каталог / project dir
# @return 0 да / yes
ts::toolchain::has_tsconfig() {
    local -r dir="${1:-.}"
    is::file "${dir}/tsconfig.json" || is::file "${dir}/tsconfig.build.json"
}

# @description Разрешить локальный бинарь tsc (node_modules/.bin → PATH)
# @description Resolve local tsc, fall back to global
# @param $1 [dir] Каталог проекта / project dir
# @stdout Путь к бинарю / binary path
# @return LIB_ERROR_DEPENDENCY_MISSING если ни локального, ни глобального
ts::toolchain::tsc_bin() {
    local -r dir="${1:-.}"
    if is::executable "${dir}/node_modules/.bin/tsc"; then
        printf '%s\n' "${dir}/node_modules/.bin/tsc"
        return "${E_SUCCESS}"
    fi
    utils::has tsc && {
        command -v tsc
        return "${E_SUCCESS}"
    }
    return "${LIB_ERROR_DEPENDENCY_MISSING}"
}

# @description Установлены ли зависимости (node_modules) / deps installed?
ts::toolchain::has_node_modules() {
    is::dir "${1:-.}/node_modules"
}

# @description Поле из package.json (через jq, fallback — grep) / read package.json field
# @param $1 [dir] Каталог / project dir
# @param $2 jq-подобное имя поля / field name
# @stdout Значение / value
ts::toolchain::pkg_field() {
    local -r dir="${1:-.}" field="${2:?field required}"
    local -r pkg="${dir}/package.json"
    is::file "${pkg}" || {
        error::throw "No package.json in ${dir}" "${LIB_ERROR_FILE_NOT_FOUND}"
        return "${LIB_ERROR_FILE_NOT_FOUND}"
    }
    if utils::has jq; then
        utils::quiet_err jq -r --arg f "${field}" '.[$f] // empty | if type=="object" then keys|join(" ") else . end' "${pkg}"
    else
        utils::quiet_err grep -oE "\"${field}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "${pkg}" |
            utils::quiet_err sed -E 's/.*:[[:space:]]*"([^"]*)".*/\1/'
    fi
}

# ==========================================
# Гейты валидации / validation gates
# ==========================================

# @description Прогон гейтов: tsc, eslint, prettier — "name<TAB>status<TAB>hint"
#   Статусы: PASS, FAIL, SKIP (инструмент/конфиг не найдены).
# @description Run validation gates; emits name/status/hint lines.
# @param $1 [dir] Каталог проекта / project dir
# @return E_SUCCESS если нет FAIL / E_SUCCESS when no FAIL
ts::toolchain::validate() {
    local -r dir="${1:-.}"
    local -i failed=0
    local tsc out rc

    # 1. tsc --noEmit / tsc typecheck
    if tsc="$(ts::toolchain::tsc_bin "${dir}")"; then
        rc=0
        out="$("${tsc}" --noEmit -p "${dir}" 2>&1)" || rc=$?
        if (( rc == 0 )); then
            printf 'tsc\t%s\t\n' PASS
        else
            printf 'tsc\t%s\t%s\n' FAIL "${out%%$'\n'*}"
            failed+=1
        fi
    else
        printf 'tsc\t%s\t%s\n' SKIP "no tsc (npm i -D typescript)"
    fi

    # 2. eslint (если есть конфиг и бинарь) / eslint if configured
    if ts::toolchain::__has_eslintrc "${dir}" && \
       tsc="$(ts::toolchain::__local_bin "${dir}" eslint)"; then
        out="$("${tsc}" -f compact "${dir}/src" 2>&1)" && \
            printf 'eslint\t%s\t\n' PASS || {
            printf 'eslint\t%s\t%s\n' FAIL "${out%%$'\n'*}"
            failed+=1
        }
    else
        printf 'eslint\t%s\t%s\n' SKIP "no config or binary"
    fi

    # 3. prettier --check (только если конфиг есть) / only with config
    if tsc="$(ts::toolchain::__local_bin "${dir}" prettier)" && \
       ts::toolchain::__has_prettierc "${dir}"; then
        out="$("${tsc}" --check "${dir}/src" 2>&1)" && \
            printf 'prettier\t%s\t\n' PASS || {
            printf 'prettier\t%s\t%s\n' FAIL "${out%%$'\n'*}"
            failed+=1
        }
    else
        printf 'prettier\t%s\t%s\n' SKIP "no config or binary"
    fi

    (( failed == 0 )) && return "${E_SUCCESS}"
    return "${E_ERROR}"
}

# @private Локальный бинарь из node_modules/.bin (fallback — глобальный)
ts::toolchain::__local_bin() {
    local -r dir="$1" name="$2"
    if is::executable "${dir}/node_modules/.bin/${name}"; then
        printf '%s\n' "${dir}/node_modules/.bin/${name}"
        return 0
    fi
    utils::has "${name}" && command -v "${name}" && return 0
    return 1
}

# @private Есть ли конфиг eslint / eslint config present?
ts::toolchain::__has_eslintrc() {
    local -r dir="$1"
    local g
    for g in eslint.config.js eslint.config.mjs eslint.config.cjs .eslintrc.js \
             .eslintrc.cjs .eslintrc.json .eslintrc.yaml .eslintrc.yml; do
        is::file "${dir}/${g}" && return 0
    done
    return 1
}

# @private Есть ли конфиг prettier / prettier config present?
ts::toolchain::__has_prettierc() {
    local -r dir="$1"
    local g
    for g in .prettierrc .prettierrc.json .prettierrc.yaml .prettierrc.yml \
             .prettierrc.js .prettierrc.cjs prettier.config.js; do
        is::file "${dir}/${g}" && return 0
    done
    return 1
}

# ==========================================
# Диагностика окружения / environment doctor
# ==========================================

# @description Сводка TS-окружения в стиле bs doctor / environment summary
# @param $1 [dir] Каталог проекта / project dir
# @stdout label=value / label=v строки / report lines
ts::toolchain::doctor() {
    local -r dir="${1:-.}"
    local runtime ver name

    printf '=== ts::toolchain::doctor (%s) ===\n' "${dir}"
    if runtime="$(ts::toolchain::detect_runtime)"; then
        ver="$(ts::toolchain::runtime_version "${runtime}")"
        printf 'runtime=%s %s (%s)\n' "${runtime}" "${ver:-?}" "$(command -v "${runtime}")"
    else
        printf 'runtime=none (install node: %s)\n' "https://nodejs.org or your package manager"
    fi

    name="$(ts::toolchain::lockfile_pm "${dir}" 2>/dev/null)" || name="-"
    printf 'package-manager=%s\n' "${name}"
    printf 'tsconfig=%s\n' "$(ts::toolchain::has_tsconfig "${dir}" && printf yes || printf no)"
    printf 'node_modules=%s\n' "$(ts::toolchain::has_node_modules "${dir}" && printf yes || printf no)"

    if is::file "${dir}/package.json"; then
        local scripts
        scripts="$(ts::toolchain::pkg_field "${dir}" scripts 2>/dev/null)" || scripts=""
        is::not_empty "${scripts}" && printf 'scripts=%s\n' "${scripts}"
        ver="$(ts::toolchain::pkg_field "${dir}" version 2>/dev/null)" || ver=""
        is::not_empty "${ver}" && printf 'project-version=%s\n' "${ver}"
    fi

    local -a bins=()
    for name in tsc eslint prettier vitest jest tsx; do
        bins+=("$(ts::toolchain::__local_bin "${dir}" "${name}" >/dev/null 2>&1 && printf "%s" PASS || printf "%s" SKIP)")
    done
    printf 'tools: tsc=%s eslint=%s prettier=%s vitest=%s jest=%s tsx=%s\n' \
        "${bins[0]}" "${bins[1]}" "${bins[2]}" "${bins[3]}" "${bins[4]}" "${bins[5]}"
}

# @description Свободен ли TCP-порт (ss → netstat → /dev/tcp) / is port free
# @param $1 Порт / port
# @param $2 [host] Адрес для /dev/tcp-пробы (default 127.0.0.1)
# @return 0 свободен; E_ERROR занят; LIB_ERROR_INVALID некорректный аргумент
ts::toolchain::port_free() {
    local -r port="${1:?port required}"
    local -r host="${2:-127.0.0.1}"
    is::number "${port}" || {
        error::throw "port must be numeric, got: ${port}" "${E_INVALID}"
        return "${E_INVALID}"
    }
    (( port >= 1 && port <= 65535 )) || {
        error::throw "port out of range: ${port}" "${E_INVALID}"
        return "${E_INVALID}"
    }

    # Цепочка проб / probe chain: ss, netstat, затем connect-проба
    if utils::has ss; then
        ss -ltn 2>/dev/null | awk '{print $4}' | \
            grep -qE "[:.]${port}\$" && return "${E_ERROR}"
        return "${E_SUCCESS}"
    fi
    if utils::has netstat; then
        netstat -ltn 2>/dev/null | awk '{print $4}' | \
            grep -qE "[:.]${port}\$" && return "${E_ERROR}"
        return "${E_SUCCESS}"
    fi
    # /dev/tcp — только localhost-guaranteed (refused = instantly free)
    if (exec 3<>"/dev/tcp/${host}/${port}") 2>/dev/null; then
        exec 3<&- 2>/dev/null || true
        exec 3>&- 2>/dev/null || true
        return "${E_ERROR}"
    fi
    return "${E_SUCCESS}"
}
