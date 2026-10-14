#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testupdatepullunit.sh — bs update: repository, install and GitHub
# tests/unit/testupdatepullunit.sh — bs update: репозиторий, установка и GitHub
#
# The scenario table of the three things bs update has to keep in step:
#   I = the installed copy, R = the local repository (checkout), G = GitHub.
# Here G is a local repository reached through file:// (BS_UPDATE_REPO), so
# nothing touches the network or the real installs of the machine.
# Таблица сценариев про три вещи, которые bs update должен держать в
# согласии: I — установленная копия, R — локальный репозиторий, G — GitHub.
# Здесь G — локальный репозиторий по file:// (BS_UPDATE_REPO): сеть и настоящие
# установки машины не затрагиваются.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"

T="" ; R="" ; C="" ; I="" ; OUT="" ; RC=0
readonly GIT=(git -c user.name=test -c user.email=test@example.com)

# Песочница: G (remote) -> R (checkout, клон) и I (установка) на версии R.
# Sandbox: G (remote) -> R (a clone of it) and I (an install) at the version of R.
sandbox() {
    T="$(mktemp -d)"
    R="${T}/remote"; C="${T}/checkout"; I="${T}/inst"
    mkdir -p "${T}/home" "${I}"
    git init -q "${R}"
    git -C "${R}" checkout -q -b main
    cp -a "${BS_PROJECT_ROOT}/bs" "${BS_PROJECT_ROOT}/bootstrap" \
          "${BS_PROJECT_ROOT}/core" "${BS_PROJECT_ROOT}/lib" "${R}/"
    mkdir -p "${R}/tests" "${R}/examples"
    : > "${R}/tests/.keep"
    printf 'v1\n' > "${R}/examples/marker"
    git -C "${R}" add -A
    "${GIT[@]}" -C "${R}" commit -qm c1
    git clone -q "${R}" "${C}"
    cp -a "${R}/bs" "${R}/bootstrap" "${R}/core" "${R}/lib" "${I}/"
    printf 'mode=custom\n' > "${I}/.install"
}

# G уходит вперёд: новая версия и новый пример / G moves ahead: new version, new example
advance_remote() {
    sed -i 's/BS_VERSION="[0-9.]*"/BS_VERSION="9.9.9"/' "${R}/core/version.sh"
    printf 'v2\n' > "${R}/examples/marker"
    "${GIT[@]}" -C "${R}" commit -qam c2
}

# run_up [args...]  — запуск из репозитория R; OUT, RC
run_up() {
    RC=0
    OUT="$(cd "${C}" && env -i HOME="${T}/home" PATH="/usr/bin:/bin" \
        BS_SYSTEM_PREFIX="${T}/sys" BS_UPDATE_REPO="file://${R}" \
        "${TEST_BASH}" "${C}/bs" update --lib "${I}" "$@" </dev/null 2>&1)" || RC=$?
}

ver()    { grep -o 'BS_VERSION="[0-9.]*"' "$1/core/version.sh" | tr -dc '0-9.'; }
marker() { cat "${C}/examples/marker"; }
has()    { if grep -qF -- "$1" <<< "${OUT}"; then testframework::assert_true "true" "$2" || true
           else testframework::assert_true "false" "$2" || true
                printf '    not found / не найдено: %s\n' "$1"; fi; }
lacks()  { if grep -qF -- "$1" <<< "${OUT}"; then testframework::assert_true "false" "$2" || true
                printf '    unexpectedly found / найдено: %s\n' "$1"
           else testframework::assert_true "true" "$2" || true; fi; }
eq()     { testframework::assert_equal "$1" "$2" "$3" || true; }

cur_version() { ver "${BS_PROJECT_ROOT}"; }

# S1: репозиторий отстаёт, без флагов, без терминала — ставится ЛОКАЛЬНЫЙ код
test_default_behind() {
    sandbox; advance_remote
    run_up
    eq "0" "${RC}" "S1 default, repo behind: exit 0"
    has "installing the LOCAL code" "S1: says that the LOCAL code is installed"
    has "bs update --pull" "S1: offers --pull"
    eq "$(cur_version)" "$(ver "${I}")" "S1: the install got the local version, not G's"
    eq "v1" "$(marker)" "S1: the repository is untouched"
    has "ОТСТАЁТ от GitHub" "S1: the summary says the repository is behind"
    rm -rf "${T}"
}

# S2: --pull — подтягивается репозиторий, ставится из него: I = R = G
test_pull() {
    sandbox; advance_remote
    run_up --pull
    eq "0" "${RC}" "S2 --pull: exit 0"
    has "репозиторий подтянут" "S2: reports the pull"
    eq "v2" "$(marker)" "S2: examples/ of the repository are new"
    eq "$(git -C "${R}" rev-parse HEAD)" "$(git -C "${C}" rev-parse HEAD)" "S2: the repository is at the commit of G"
    eq "9.9.9" "$(ver "${I}")" "S2: the install has the new version"
    has "установка и репозиторий согласованы" "S2: the summary says they agree"
    lacks "ОТСТАЁТ" "S2: no 'behind' left in the summary"
    rm -rf "${T}"
}

# S3: --github — установка с G, репозиторий остаётся старым (и об этом сказано)
test_github_only() {
    sandbox; advance_remote
    run_up --github
    eq "0" "${RC}" "S3 --github: exit 0"
    eq "9.9.9" "$(ver "${I}")" "S3: the install comes from G"
    eq "v1" "$(marker)" "S3: the repository is NOT updated"
    has "НЕ обновлён" "S3: warns that the repository was not updated"
    has "examples/ и tests/" "S3: explains that examples/ and tests/ are not copied"
    has "bs update --pull" "S3: offers --pull"
    has "старее установки" "S3: the summary flags the mismatch"
    rm -rf "${T}"
}

# S4: --github --pull — и репозиторий, и установка
test_github_and_pull() {
    sandbox; advance_remote
    run_up --github --pull
    eq "0" "${RC}" "S4 --github --pull: exit 0"
    eq "v2" "$(marker)" "S4: the repository is pulled"
    eq "9.9.9" "$(ver "${I}")" "S4: the install is from G"
    has "установка и репозиторий согласованы" "S4: consistent"
    rm -rf "${T}"
}

# S5: грязное дерево — --pull отказывается, ничего не меняется
test_pull_dirty() {
    sandbox; advance_remote
    printf 'my edit\n' >> "${C}/examples/marker"
    local before_head; before_head="$(git -C "${C}" rev-parse HEAD)"
    local before_ver; before_ver="$(ver "${I}")"
    run_up --pull
    eq "1" "${RC}" "S5 dirty tree, --pull: exit 1"
    has "незакоммиченные правки" "S5: names the reason"
    has "ничего не изменено" "S5: says nothing was changed"
    eq "${before_head}" "$(git -C "${C}" rev-parse HEAD)" "S5: HEAD of the repository unchanged"
    eq "${before_ver}" "$(ver "${I}")" "S5: the install unchanged"
    testframework::assert_command "grep -q 'my edit' '${C}/examples/marker'" "S5: the user's edit is still there"
    rm -rf "${T}"
}

# S6: история разошлась — перемотка вперёд невозможна, ничего не сливается
test_pull_diverged() {
    sandbox
    printf 'local\n' > "${C}/local.txt"
    git -C "${C}" add local.txt
    "${GIT[@]}" -C "${C}" commit -qm local
    advance_remote
    local before_head; before_head="$(git -C "${C}" rev-parse HEAD)"
    run_up --pull
    eq "1" "${RC}" "S6 diverged history, --pull: exit 1"
    has "git pull --ff-only не удался" "S6: names the ff-only failure"
    eq "${before_head}" "$(git -C "${C}" rev-parse HEAD)" "S6: nothing was merged or rewritten"
    eq "$(cur_version)" "$(ver "${I}")" "S6: the install unchanged"
    rm -rf "${T}"
}

# S7: --pull без репозитория рядом
test_pull_without_repo() {
    sandbox
    local out rc=0
    out="$(cd "${T}" && env -i HOME="${T}/home" PATH="/usr/bin:/bin" BS_SYSTEM_PREFIX="${T}/sys" \
        "${TEST_BASH}" "${I}/bs" update --lib "${I}" --pull </dev/null 2>&1)" || rc=$?
    eq "1" "${rc}" "S7 --pull with no repository around: exit 1"
    OUT="${out}"
    has "рядом нет репозитория BS" "S7: explains that there is no repository"
    rm -rf "${T}"
}

# S8: репозиторий актуален — тихо, согласовано; --pull идемпотентен
test_up_to_date() {
    sandbox
    run_up
    eq "0" "${RC}" "S8 repo == G: exit 0"
    lacks "отстаёт" "S8: no 'behind' warning"
    run_up --pull
    eq "0" "${RC}" "S8 --pull when already up to date: exit 0"
    has "уже актуален" "S8: says the repository is already up to date"
    eq "v1" "$(marker)" "S8: nothing changed"
    rm -rf "${T}"
}

# S9: справка описывает --pull
test_help() {
    sandbox
    OUT="$(env -i HOME="${T}/home" PATH="/usr/bin:/bin" ${TEST_BASH} "${BS_PROJECT_ROOT}/bs" update --help 2>&1)"
    has "--pull" "S9: bs update --help documents --pull"
    rm -rf "${T}"
}

main() {
    print_header "Update Pull Unit Tests / Тесты bs update: репозиторий, установка, GitHub"

    testframework::init

    testframework::section "Repository behind GitHub / Репозиторий отстаёт"
    test_default_behind
    test_pull
    test_github_only
    test_github_and_pull

    testframework::section "Refusals / Отказы"
    test_pull_dirty
    test_pull_diverged
    test_pull_without_repo

    testframework::section "Up to date, help / Актуально, справка"
    test_up_to_date
    test_help

    testframework::summary
}

main "$@"
