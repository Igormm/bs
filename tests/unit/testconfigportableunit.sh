#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testconfigportableunit.sh — core/config.sh as POSIX code under dash, ash, ksh, mksh, zsh and bash
# tests/unit/testconfigportableunit.sh — core/config.sh как POSIX-код под dash, ash, ksh, mksh, zsh и bash
#
# core/config.sh is "@shell posix": the defaults, the file parser, the trust rule for a project-local
# file and the priority of the environment must give the same answers in every shell.
# core/config.sh — "@shell posix": умолчания, разбор файла, правило доверия к локальному файлу и
# приоритет окружения обязаны давать одинаковые ответы в любой оболочке.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly CFG_SH="${BS_PROJECT_ROOT}/core/config.sh"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

T=""

# probe <shell> <env> <snippet> — всё подключено; рабочий каталог — ${T}/proj (там лежит локальный .bsrc), HOME — ${T}/home
probe() {
    local -r sh_bin="$1" envs="$2" snippet="$3"
    local f
    : > "${T}/probe.sh"
    for f in bootstrap/shell.sh core/prereq.sh core/const.sh core/logger.sh core/quiet.sh core/fmt.sh core/data.sh core/errorhandler.sh core/utils.sh core/config.sh; do
        printf 'BS_CURRENT_FILE="%s/%s"\n. "%s/%s"\n' "${BS_PROJECT_ROOT}" "${f}" "${BS_PROJECT_ROOT}" "${f}" >> "${T}/probe.sh"
    done
    printf '%s\n' "${snippet}" >> "${T}/probe.sh"
    # shellcheck disable=SC2086  # envs — список VAR=значение / a VAR=value list
    (cd "${T}/proj" && env -i HOME="${T}/home" PATH="/usr/bin:/bin" BS_LOG_TIMESTAMP=false ${envs} "${sh_bin}" "${T}/probe.sh" 2>&1 </dev/null)
}

eq() { testframework::assert_equal "$1" "$2" "$3" || true; }

test_parses_and_lints() {
    local sh_bin
    while IFS= read -r sh_bin; do
        testframework::assert_command "'${sh_bin}' -n '${CFG_SH}'" "config.sh parses in ${sh_bin##*/}" || true
    done < <(testframework::posix_shells)
    if utils::has shellcheck; then
        testframework::assert_command "shellcheck -s sh '${CFG_SH}'" "shellcheck -s sh is clean for core/config.sh" || true
    fi
    testframework::assert_command "grep -q '^# @shell posix' '${CFG_SH}'" "core/config.sh is declared @shell posix" || true
}

test_behaviour() {
    local sh_bin sh_name
    mkdir -p "${T}/home/.config/bs" "${T}/proj" "${T}/nohome"
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        rm -f "${T}/home/.config/bs/config.sh" "${T}/proj/.bsrc"
        eq "false" "$(probe "${sh_bin}" '' 'bs_config_load; bs_config_get BS_FILES_ATOMIC')" "${sh_name}: the default of BS_FILES_ATOMIC"
        eq "INFO" "$(probe "${sh_bin}" '' 'bs_config_load; bs_config_get BS_LOG_LEVEL')" "${sh_name}: BS_LOG_LEVEL is INFO — the logger exports it, and the environment beats the defaults (as before)"
        eq "rc=2" "$(probe "${sh_bin}" '' 'bs_config_load; bs_config_get NO_SUCH_KEY >/dev/null; echo rc=$?')" "${sh_name}: a missing key with no default is E_INVALID (2)"
        eq "dflt" "$(probe "${sh_bin}" '' 'bs_config_load; bs_config_get NO_SUCH_KEY dflt')" "${sh_name}: a missing key with a default"
        eq "rc=2" "$(probe "${sh_bin}" '' 'bs_config_get "" 2>/dev/null; echo rc=$?')" "${sh_name}: an empty key is refused (2)"
        eq "debug|debug" "$(probe "${sh_bin}" '' 'bs_config_load; bs_config_set BS_FILES_ATOMIC debug; printf "%s|%s" "$(bs_config_get BS_FILES_ATOMIC)" "$BS_FILES_ATOMIC"')" "${sh_name}: set changes the map and the environment"
        eq "rc=2" "$(probe "${sh_bin}" '' 'bs_config_set "bad key" x 2>/dev/null; echo rc=$?')" "${sh_name}: set refuses a key that is not a variable name (2)"
        # файл пользователя / the user file
        printf '%s\n' '# a comment' '' 'BS_FILES_BACKUP_SUFFIX = .bak' 'BS_RESULT_FILE="/tmp/r e s"' "BS_LLM_MODEL='m 1'" 'not a pair' '  INDENTED=1' '1BAD=2' 'EMPTY=' 'BS_SILENT=1' > "${T}/home/.config/bs/config.sh"
        eq ".bak" "$(probe "${sh_bin}" '' 'bs_config_load; bs_config_get BS_FILES_BACKUP_SUFFIX')" "${sh_name}: the user file sets a key (spaces around = allowed)"
        eq "INFO" "$(probe "${sh_bin}" '' 'bs_config_load; bs_config_get BS_LOG_LEVEL')" "${sh_name}: the user file cannot beat the BS_LOG_LEVEL that the logger already exported"
        eq "/tmp/r e s" "$(probe "${sh_bin}" '' 'bs_config_load; bs_config_get BS_RESULT_FILE')" "${sh_name}: double quotes are removed"
        eq "m 1" "$(probe "${sh_bin}" '' 'bs_config_load; bs_config_get BS_LLM_MODEL')" "${sh_name}: single quotes are removed"
        eq "rc=2" "$(probe "${sh_bin}" '' 'bs_config_load; bs_config_get INDENTED >/dev/null; echo rc=$?')" "${sh_name}: a line with leading spaces is not a pair"
        eq "rc=2" "$(probe "${sh_bin}" '' 'bs_config_load; bs_config_get 1BAD >/dev/null; echo rc=$?')" "${sh_name}: a key that is not an identifier is ignored"
        eq "1" "$(probe "${sh_bin}" '' 'bs_config_load; printf "%s" "$BS_SILENT"')" "${sh_name}: a loaded value is exported to the environment"
        # окружение сильнее файла / the environment beats the file
        eq "error" "$(probe "${sh_bin}" 'BS_LOG_LEVEL=error' 'bs_config_load; bs_config_get BS_LOG_LEVEL')" "${sh_name}: an environment variable beats the user file"
        # локальный файл: только разрешённые ключи / the local file: allowed keys only
        printf '%s\n' 'BS_LLM_PROVIDER=local-p' 'BS_LLM_API_KEY=secret' 'BS_RESULT_FILE=/etc/x' > "${T}/proj/.bsrc"
        eq "local-p" "$(probe "${sh_bin}" '' 'bs_config_load 2>/dev/null; bs_config_get BS_LLM_PROVIDER')" "${sh_name}: the local file may set an allowed key"
        eq "" "$(probe "${sh_bin}" '' 'bs_config_load 2>/dev/null; bs_config_get BS_LLM_API_KEY')" "${sh_name}: the local file may not set the API key"
        eq "/tmp/r e s" "$(probe "${sh_bin}" '' 'bs_config_load 2>/dev/null; bs_config_get BS_RESULT_FILE')" "${sh_name}: the local file may not set the result file (the user value stays)"
        eq "[WARN ] config: .bsrc: key BS_LLM_API_KEY is not allowed in a project-local file, ignored" "$(probe "${sh_bin}" '' 'bs_config_load' | grep "BS_LLM_API_KEY" | head -n 1 | sed 's#config: [^ ]*/\.bsrc#config: .bsrc#')" "${sh_name}: a refused local key is reported"
        rm -f "${T}/proj/.bsrc"
        # list, пути / list, paths
        eq "BS_FILES_ATOMIC=false" "$(probe "${sh_bin}" '' 'bs_config_load; bs_config_list | grep "^BS_FILES_ATOMIC="')" "${sh_name}: list prints KEY=VALUE"
        eq "yes" "$(probe "${sh_bin}" '' 'bs_config_load; bs_config_list | sort -c && echo yes')" "${sh_name}: list is sorted"
        eq "${T}/home/.config/bs/config.sh" "$(probe "${sh_bin}" '' 'bs_config_user_file')" "${sh_name}: user_file"
        eq ".bsrc" "$(probe "${sh_bin}" '' 'bs_config_local_file')" "${sh_name}: local_file"
        # без HOME / with no HOME
        eq "|false" "$(probe "${sh_bin}" 'HOME=' 'bs_config_load; printf "%s|%s" "$(bs_config_user_file)" "$(bs_config_get BS_FILES_ATOMIC)"')" "${sh_name}: with no HOME there is no user file and the defaults still work"
    done < <(testframework::posix_shells)
}

test_aliases() {
    local sh_name sh_bin
    for sh_name in bash zsh; do
        sh_bin="$(command -v "${sh_name}" || true)"
        [[ -n "${sh_bin}" ]] || continue
        eq "false" "$(probe "${sh_bin}" '' 'config::load; config::get BS_FILES_ATOMIC')" "${sh_name}: config::load and config::get are aliases"
    done
}

main() {
    T="$(mktemp -d)"
    testframework::section "Parse and lint / Разбор и линт"; test_parses_and_lints
    testframework::section "Behaviour in every shell / Поведение в каждой оболочке"; test_behaviour
    testframework::section "Aliases / Псевдонимы"; test_aliases
    rm -rf "${T:?}"
    testframework::summary
}

main "$@"
