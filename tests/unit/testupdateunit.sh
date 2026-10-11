#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testupdateunit.sh — Unit tests for `bs update` (CLI command)
# tests/unit/testupdateunit.sh — Модульные тесты для `bs update` (команда CLI)

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

test_update_basic() {
    local tmp_dir src target
    tmp_dir="$(mktemp -d)"
    src="${tmp_dir}/repo"
    target="${tmp_dir}/installed"

    # Минимальный фейковый репозиторий и установка / Fake repo and install
    mkdir -p "${src}/core" "${src}/lib/data" "${src}/bootstrap" "${target}/lib/data"
    printf '#!/usr/bin/env bash\necho fake-bs\n' > "${src}/bs"
    printf '#!/usr/bin/env bash\n' > "${src}/bootstrap/init.sh"
    printf 'old_core() { :; }\n' > "${target}/old.sh"
    printf 'new_func() { :; }\n' > "${src}/core/new.sh"
    printf 'mod_func() { :; }\n' > "${src}/lib/data/mod.sh"
    printf 'old_lib() { :; }\n' > "${target}/lib/data/old_lib.sh"

    bash "${BS_PROJECT_ROOT}/bs" update --lib "${target}" --from "${src}" >/dev/null 2>&1
    testframework::assert_equal "0" "$?" "bs update exits 0"
    testframework::assert_command "test -f '${target}/core/new.sh'" "bs update copies new core files"
    testframework::assert_command "test -f '${target}/lib/data/mod.sh'" "bs update copies lib modules"
    testframework::assert_command "test -f '${target}/bs'" "bs update copies launcher"
    testframework::assert_command "test -f '${target}/bootstrap/init.sh'" "bs update copies bootstrap"
    testframework::assert_equal "new_func() { :; }" "$(cat "${target}/core/new.sh")" "bs update copies content"

    # Повторный update — идемпотентность / Second update is idempotent
    bash "${BS_PROJECT_ROOT}/bs" update --lib "${target}" --from "${src}" >/dev/null 2>&1
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

    mkdir -p "${src}/core" "${src}/lib" "${src}/bootstrap" "${target}/core" "${tmp_dir}/bin" "${tmp_dir}/home"
    printf '#!/usr/bin/env bash\necho fake-bs\n' > "${src}/bs"
    printf '#!/usr/bin/env bash\n' > "${src}/bootstrap/init.sh"
    printf 'new_func() { :; }\n' > "${src}/core/new.sh"
    printf '#!/usr/bin/env bash\nexport BS_ROOT="%s"\nexec "${BS_ROOT}/bs" "$@"\n' "${target}" > "${tmp_dir}/bin/bs"
    chmod +x "${tmp_dir}/bin/bs"

    # Без терминала (stdin не TTY) sudo не вызывается; системная установка
    # на машине разработчика может дать ненулевой код — проверяем файлы.
    # No terminal (stdin is not a TTY) means no sudo; a system install on the
    # developer machine may yield a non-zero code — so check the files.
    HOME="${tmp_dir}/home" PATH="${tmp_dir}/bin:${PATH}" \
        bash "${BS_PROJECT_ROOT}/bs" update --from "${src}" >/dev/null 2>&1 </dev/null || true
    testframework::assert_command "test -f '${target}/core/new.sh'" "bs update detects the install behind the PATH wrapper"

    rm -rf "${tmp_dir}"
}

test_update_errors() {
    local tmp_dir src missing
    tmp_dir="$(mktemp -d)"
    src="${tmp_dir}/repo"
    missing="${tmp_dir}/missing"

    mkdir -p "${src}/core" "${src}/bootstrap"
    printf 'x\n' > "${src}/core/a.sh"

    testframework::assert_false "bash '${BS_PROJECT_ROOT}/bs' sync --lib '${missing}' --from '${src}'" "bs update fails when target missing"
    testframework::assert_false "bash '${BS_PROJECT_ROOT}/bs' sync --lib '${tmp_dir}/x' --from '${tmp_dir}/not-a-repo'" "bs update fails when source is not a repo"

    rm -rf "${tmp_dir}"
}

# Фейковый git-репозиторий BS с веткой main / Fake BS git repo on branch main
make_git_repo() {
    local -r repo="$1"
    mkdir -p "${repo}/core" "${repo}/lib" "${repo}/bootstrap"
    printf '#!/usr/bin/env bash\necho remote-bs\n' > "${repo}/bs"
    printf '#!/usr/bin/env bash\n' > "${repo}/bootstrap/init.sh"
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
    mkdir -p "${target}"

    # Явный источник: --repo подразумевает --github / --repo implies --github
    bash "${BS_PROJECT_ROOT}/bs" update --lib "${target}" --repo "file://${repo}" >/dev/null 2>&1
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
    (cd "${tmp_dir}" && env -u BS_ROOT -u BS_HOME BS_UPDATE_REPO="file://${repo}" bash "${installed}/bs" update --lib "${installed}" >/dev/null 2>&1)
    testframework::assert_equal "0" "$?" "bs update from installed copy exits 0"
    testframework::assert_command "test -f '${installed}/core/remote.sh'" "installed copy updates from remote repo"

    # Конфликт: локальный клон отстаёт от удалённого репозитория
    # Conflict: the local clone is behind the remote repository
    local clone="${tmp_dir}/clone" out
    git clone --quiet "file://${repo}" "${clone}"
    printf 'newer_func() { :; }\n' > "${repo}/core/newer.sh"
    git -C "${repo}" add -A
    git -C "${repo}" -c user.name=test -c user.email=test@example.com commit --quiet -m newer
    rm -rf "${target}" && mkdir -p "${target}"
    out="$(BS_UPDATE_REPO="file://${repo}" bash "${BS_PROJECT_ROOT}/bs" update --lib "${target}" --from "${clone}" 2>&1 </dev/null)"
    testframework::assert_equal "0" "$?" "bs update from a stale clone exits 0"
    testframework::assert_command "grep -q 'is behind' <<< '${out//\'/}'" "bs update warns when local repo is behind"
    testframework::assert_command "test ! -e '${target}/core/newer.sh'" "stale clone installs local code when non-interactive"

    bash "${BS_PROJECT_ROOT}/bs" update --lib "${target}" --repo "file://${repo}" >/dev/null 2>&1
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

    testframework::section "Errors / Ошибки"
    test_update_errors

    testframework::summary
}

main "$@"