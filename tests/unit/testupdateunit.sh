#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testupdateunit.sh — Unit tests for `bs update` (CLI command)
# tests/unit/testupdateunit.sh — Модульные тесты для `bs update` (команда CLI)

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

# Фейковый источник BS: bs печатает версию, как настоящий (smoke-test update).
# Fake BS source: its bs prints a version like the real one (update smoke test).
make_fake_src() {
    local -r dir="$1" ver="${2:-9.9.9}"
    mkdir -p "${dir}/core" "${dir}/lib" "${dir}/bootstrap"
    printf '#!/usr/bin/env bash\ncase "${1:-}" in version) echo "BS Framework version: %s";; esac\n' "${ver}" > "${dir}/bs"
    chmod +x "${dir}/bs"
    # файлы, без которых update отвергает источник / files without which update refuses a source
    : > "${dir}/bootstrap/shell.sh"; : > "${dir}/bootstrap/trampoline.sh"; : > "${dir}/bootstrap/shebang.sh"; : > "${dir}/bootstrap/bs.sh"; : > "${dir}/core/prereq.sh"
    printf '#!/usr/bin/env bash\n' > "${dir}/bootstrap/init.sh"
    printf '#!/usr/bin/env bash\n' > "${dir}/bootstrap/loader.sh"
    printf 'export BS_VERSION="%s"\n' "${ver}" > "${dir}/core/version.sh"
}

# Фейковая установка: маркеры BS (bs + bootstrap/init.sh) — иначе update откажет.
# Fake install with the BS markers (bs + bootstrap/init.sh) — else update refuses.
make_fake_target() {
    make_fake_src "$@"
}

test_update_basic() {
    local tmp_dir src target
    tmp_dir="$(mktemp -d)"
    src="${tmp_dir}/repo"
    target="${tmp_dir}/installed"

    # Минимальный фейковый репозиторий и установка / Fake repo and install
    make_fake_src "${src}" 9.9.9
    make_fake_target "${target}" 9.0.0
    mkdir -p "${src}/lib/data" "${target}/lib/data"
    printf 'old_core() { :; }\n' > "${target}/old.sh"
    printf 'new_func() { :; }\n' > "${src}/core/new.sh"
    printf 'mod_func() { :; }\n' > "${src}/lib/data/mod.sh"
    printf 'old_lib() { :; }\n' > "${target}/lib/data/old_lib.sh"

    "${TEST_BASH}" "${BS_PROJECT_ROOT}/bs" update --lib "${target}" --from "${src}" >/dev/null 2>&1
    testframework::assert_equal "0" "$?" "bs update exits 0"
    testframework::assert_command "test -f '${target}/core/new.sh'" "bs update copies new core files"
    testframework::assert_command "test -f '${target}/lib/data/mod.sh'" "bs update copies lib modules"
    testframework::assert_command "test -f '${target}/bs'" "bs update copies launcher"
    testframework::assert_command "test -f '${target}/bootstrap/init.sh'" "bs update copies bootstrap"
    testframework::assert_equal "new_func() { :; }" "$(cat "${target}/core/new.sh")" "bs update copies content"

    # Манифест: update записывает, откуда обновлено / manifest records the source
    testframework::assert_command "grep -qx 'updated_from=${src}' '${target}/.install'" "bs update records the source in the manifest"
    testframework::assert_command "grep -qx 'mode=custom' '${target}/.install'" "bs update creates a manifest for an old install"

    # Повторный update — идемпотентность / Second update is idempotent
    "${TEST_BASH}" "${BS_PROJECT_ROOT}/bs" update --lib "${target}" --from "${src}" >/dev/null 2>&1
    testframework::assert_equal "0" "$?" "bs update idempotent"

    rm -rf "${tmp_dir}"
}

# Автодетект: каталог установки берётся из обёртки `bs` в PATH
# Autodetect: the install directory comes from the `bs` wrapper in PATH
test_update_autodetect() {
    local tmp_dir src target
    tmp_dir="$(mktemp -d)"
    src="${tmp_dir}/repo"
    target="${tmp_dir}/custom/lib/bs"

    make_fake_src "${src}" 9.9.9
    make_fake_target "${target}" 9.0.0
    mkdir -p "${tmp_dir}/bin" "${tmp_dir}/home"
    printf 'new_func() { :; }\n' > "${src}/core/new.sh"
    printf '#!/usr/bin/env bash\nexport BS_ROOT="%s"\nexec "${BS_ROOT}/bs" "$@"\n' "${target}" > "${tmp_dir}/bin/bs"
    chmod +x "${tmp_dir}/bin/bs"

    # Изоляция: автопоиск обходит PATH и находит ВСЕ обёртки bs, поэтому PATH
    # урезан до поддельной обёртки и системных каталогов — настоящая установка
    # пользователя (~/.local/bin/bs) не должна быть видна. Реальная системная
    # установка, доступная на запись (запуск от root), — повод пропустить тест.
    # Isolation: the autodetect walks PATH and finds EVERY bs wrapper, so PATH
    # is cut down to the fake wrapper and the system directories — the user's
    # real install (~/.local/bin/bs) must not be visible. A real system
    # install writable by us (a run as root) is a reason to skip the test.
    if [[ -d /usr/local/lib/bs && -w /usr/local/lib/bs ]]; then
        printf "  ⊘ Skipping PATH autodetect: a writable system install exists\n"
        rm -rf "${tmp_dir}"
        return 0
    fi
    # Без терминала (stdin не TTY) sudo не вызывается / no TTY, so no sudo
    HOME="${tmp_dir}/home" PATH="${tmp_dir}/bin:/usr/bin:/bin" \
        "${TEST_BASH}" "${BS_PROJECT_ROOT}/bs" update --from "${src}" >/dev/null 2>&1 </dev/null || true
    testframework::assert_command "test -f '${target}/core/new.sh'" "bs update detects the install behind the PATH wrapper"

    rm -rf "${tmp_dir}"
}

# bs uninstall из самой установленной копии удаляет её; чекаут не трогает
# bs uninstall run from the installed copy removes it; a checkout is kept
test_uninstall_self() {
    local tmp_dir lib_dir checkout
    tmp_dir="$(mktemp -d)"
    lib_dir="${tmp_dir}/prefix/lib/bs"
    checkout="${tmp_dir}/checkout"

    mkdir -p "${lib_dir}" "${tmp_dir}/prefix/bin" "${checkout}/tests"
    cp -a "${BS_PROJECT_ROOT}/bootstrap" "${BS_PROJECT_ROOT}/core" "${BS_PROJECT_ROOT}/lib" "${BS_PROJECT_ROOT}/bs" "${lib_dir}/"
    cp -a "${BS_PROJECT_ROOT}/bootstrap" "${BS_PROJECT_ROOT}/bs" "${checkout}/"
    printf '#!/usr/bin/env bash\nexport BS_ROOT="%s"\nexec "${BS_ROOT}/bs" "$@"\n' "${lib_dir}" > "${tmp_dir}/prefix/bin/bs"
    chmod +x "${tmp_dir}/prefix/bin/bs"

    testframework::assert_false "'${tmp_dir}/prefix/bin/bs' uninstall --lib '${checkout}'" "bs uninstall refuses a source checkout"
    testframework::assert_command "test -f '${checkout}/bs'" "source checkout is left intact"

    "${tmp_dir}/prefix/bin/bs" uninstall --lib "${lib_dir}" >/dev/null 2>&1
    testframework::assert_equal "0" "$?" "bs uninstall from the installed copy exits 0"
    testframework::assert_command "test ! -e '${lib_dir}'" "bs uninstall removes the copy it runs from"
    testframework::assert_command "test ! -e '${tmp_dir}/prefix/bin/bs'" "bs uninstall removes the wrapper"

    rm -rf "${tmp_dir}"
}

test_update_errors() {
    local tmp_dir src missing
    tmp_dir="$(mktemp -d)"
    src="${tmp_dir}/repo"
    missing="${tmp_dir}/missing"

    make_fake_src "${src}" 9.9.9

    testframework::assert_false "bash '${BS_PROJECT_ROOT}/bs' sync --lib '${missing}' --from '${src}'" "bs update fails when target missing"
    testframework::assert_false "bash '${BS_PROJECT_ROOT}/bs' sync --lib '${tmp_dir}/x' --from '${tmp_dir}/not-a-repo'" "bs update fails when source is not a repo"

    rm -rf "${tmp_dir}"
}

# Фейковый git-репозиторий BS с веткой main / Fake BS git repo on branch main
make_git_repo() {
    local -r repo="$1"
    make_fake_src "${repo}" 5.0.0
    printf 'remote_func() { :; }\n' > "${repo}/core/remote.sh"
    printf 'remote_lib() { :; }\n' > "${repo}/lib/remote.sh"
    git -C "${repo}" init --quiet --initial-branch=main
    git -C "${repo}" add -A
    git -C "${repo}" -c user.name=test -c user.email=test@example.com commit --quiet -m init
}

test_update_github() {
    if ! utils::has git; then
        testframework::assert_true "true" "bs update --github skipped (no git)"
        return 0
    fi
    local tmp_dir repo target
    tmp_dir="$(mktemp -d)"
    repo="${tmp_dir}/remote"
    target="${tmp_dir}/installed"
    make_git_repo "${repo}"
    make_fake_target "${target}" 4.0.0

    # Явный источник: --repo подразумевает --github / --repo implies --github
    "${TEST_BASH}" "${BS_PROJECT_ROOT}/bs" update --lib "${target}" --repo "file://${repo}" >/dev/null 2>&1
    testframework::assert_equal "0" "$?" "bs update --repo exits 0"
    testframework::assert_command "test -f '${target}/core/remote.sh'" "bs update --repo copies remote core"
    testframework::assert_command "test -f '${target}/lib/remote.sh'" "bs update --repo copies remote lib"
    testframework::assert_command "test ! -e '${target}/.git'" "bs update --repo does not copy .git"

    testframework::assert_false "bash '${BS_PROJECT_ROOT}/bs' update --lib '${target}' --repo 'file://${repo}' --ref no-such-ref" "bs update fails on unknown ref"
    testframework::assert_false "bash '${BS_PROJECT_ROOT}/bs' update --lib '${target}' --github --from '${repo}'" "bs update rejects --from with --github"

    # Развилка: установленная копия без репозитория рядом идёт на GitHub
    # Fork: an installed copy with no repo around falls back to GitHub
    local installed="${tmp_dir}/copy"
    mkdir -p "${installed}"
    cp -a "${BS_PROJECT_ROOT}/bootstrap" "${BS_PROJECT_ROOT}/core" "${BS_PROJECT_ROOT}/lib" "${BS_PROJECT_ROOT}/bs" "${installed}/"
    (cd "${tmp_dir}" && env -u BS_ROOT -u BS_HOME BS_UPDATE_REPO="file://${repo}" "${TEST_BASH}" "${installed}/bs" update --lib "${installed}" >/dev/null 2>&1)
    testframework::assert_equal "0" "$?" "bs update from installed copy exits 0"
    testframework::assert_command "test -f '${installed}/core/remote.sh'" "installed copy updates from remote repo"

    # Конфликт: локальный клон отстаёт от удалённого репозитория
    # Conflict: the local clone is behind the remote repository
    local clone="${tmp_dir}/clone" out
    git clone --quiet "file://${repo}" "${clone}"
    printf 'newer_func() { :; }\n' > "${repo}/core/newer.sh"
    git -C "${repo}" add -A
    git -C "${repo}" -c user.name=test -c user.email=test@example.com commit --quiet -m newer
    rm -rf "${target}" && make_fake_target "${target}" 4.0.0
    out="$(BS_UPDATE_REPO="file://${repo}" ${TEST_BASH} "${BS_PROJECT_ROOT}/bs" update --lib "${target}" --from "${clone}" 2>&1 </dev/null)"
    testframework::assert_equal "0" "$?" "bs update from a stale clone exits 0"
    testframework::assert_command "grep -q 'is behind' <<< '${out//\'/}'" "bs update warns when local repo is behind"
    testframework::assert_command "test ! -e '${target}/core/newer.sh'" "stale clone installs local code when non-interactive"

    "${TEST_BASH}" "${BS_PROJECT_ROOT}/bs" update --lib "${target}" --repo "file://${repo}" >/dev/null 2>&1
    testframework::assert_command "test -f '${target}/core/newer.sh'" "bs update --repo installs the newer remote code"

    rm -rf "${tmp_dir}"
}

main() {
    print_header "Update Unit Tests / Модульные тесты sync"

    testframework::init

    testframework::section "Update / Обновление"
    test_update_basic

    testframework::section "GitHub source / Источник GitHub"
    test_update_github

    testframework::section "Autodetect / Автодетект"
    test_update_autodetect

    testframework::section "Uninstall / Удаление"
    test_uninstall_self

    testframework::section "Errors / Ошибки"
    test_update_errors

    testframework::summary
}

main "$@"