#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testupdatesafetyunit.sh — negative scenarios of `bs update`
# tests/unit/testupdatesafetyunit.sh — негативные сценарии `bs update`
#
# Everything runs in mktemp -d with its own HOME, PATH and BS_SYSTEM_PREFIX:
# a real install of the user (~/.local, /usr/local) is never visible or touched.
# Всё выполняется в mktemp -d со своими HOME, PATH и BS_SYSTEM_PREFIX:
# настоящая установка пользователя (~/.local, /usr/local) не видна и не трогается.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly BS_CLI="${BS_UPDATE_TEST_CLI:-${BS_PROJECT_ROOT}/bs}"
REAL_HOME="${HOME}"
readonly REAL_HOME

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

T=""
OUT=""
RC=0
RAW=""

# Песочница: HOME, PATH (только bin песочницы + системные), префикс system.
# Sandbox: HOME, PATH (sandbox bin + system dirs only), system prefix.
sandbox() {
    T="$(mktemp -d)"
    mkdir -p "${T}/home" "${T}/bin" "${T}/sys" "${T}/tmpd"
}

make_src() {
    local -r dir="$1" ver="${2:-9.9.9}"
    mkdir -p "${dir}/core" "${dir}/lib" "${dir}/bootstrap"
    printf '#!/usr/bin/env bash\ncase "${1:-}" in version) echo "BS Framework version: %s";; esac\n' "${ver}" > "${dir}/bs"
    printf '#!/usr/bin/env bash\n' > "${dir}/bootstrap/init.sh"
    printf '#!/usr/bin/env bash\n' > "${dir}/bootstrap/loader.sh"
    printf 'export BS_VERSION="%s"\n' "${ver}" > "${dir}/core/version.sh"
    printf 'mod_%s\n' "${ver}" > "${dir}/lib/mod.sh"
}

make_inst() {
    make_src "$@"
    printf 'mode=custom\n' > "$1/.install"
}

# Обёртка bs, как у install.sh / a bs wrapper like install.sh writes
make_wrapper() {
    printf '#!/usr/bin/env bash\nexport BS_ROOT="%s"\nexec "${BS_ROOT}/bs" "$@"\n' "$2" > "$1"
    chmod +x "$1"
}

# Контрольная сумма дерева (имена + содержимое) / tree checksum (names + content)
tree_sum() {
    (cd "$1" && find . -type f -o -type l | LC_ALL=C sort | while IFS= read -r f; do
        printf '%s %s\n' "${f}" "$(cksum < "${f}" 2>/dev/null || echo L)"
    done | cksum)
}

# Запуск bs в песочнице: OUT = stdout+stderr, RC = код выхода.
# Run bs in the sandbox: OUT = stdout+stderr, RC = exit code.
run_bs() {
    OUT="$(cd "${T}" && env -u BS_ROOT -u BS_HOME -u BS_INITIALIZED -u SUDO_USER \
        HOME="${T}/home" PATH="${T}/bin:/usr/bin:/bin" BS_SYSTEM_PREFIX="${T}/sys" TMPDIR="${T}/tmpd" \
        bash "${BS_CLI}" "$@" 2>&1 </dev/null)" && RC=0 || RC=$?
    RAW="${OUT}"
    OUT="$(flatten_boxes "${OUT}")"
}

# Склеить строки, перенесённые рамкой по 58 символов, и снять бордюры: тесты
# ищут фразы, а не позиции переноса. RAW хранит вывод как есть.
# Re-join lines the box wrapped at 58 characters and strip the borders: tests
# look for phrases, not wrap positions. RAW keeps the output as printed.
flatten_boxes() {
    local line content res=""
    while IFS= read -r line; do
        if [[ "${line}" == '│'* ]]; then
            content="${line#│}"
            content="${content%│}"
            if (( ${#content} >= 58 )); then
                res+="${content}"
            else
                content="${content%"${content##*[! ]}"}"
                res+="${content}"$'\n'
            fi
        else
            res+="${line}"$'\n'
        fi
    done <<< "$1"
    printf '%s' "${res}"
}

# y/n: содержит ли текст фразу (без grep-метасимволов) / does text contain the phrase
has() { if [[ "$1" == *"$2"* ]]; then printf 'y'; else printf 'n'; fi; }
eq()  { testframework::assert_equal "$1" "$2" "$3" || true; }
chk_cmd()  { testframework::assert_command "$1" "$2" || true; }
chk_true() { testframework::assert_true "$1" "$2" || true; }
leftovers() { find "$1" -maxdepth 1 \( -name '.update.*' -o -name '.update-old.*' -o -name '.update-lock' \) | wc -l | tr -d ' '; }

test_isolation() {
    sandbox
    # Самая первая проверка: настоящий ~/.local/bin/bs не виден из PATH теста
    # The very first check: the real ~/.local/bin/bs is not visible from the test PATH
    local path_seen
    path_seen="$(env HOME="${T}/home" PATH="${T}/bin:/usr/bin:/bin" bash -c 'command -v bs || true')"
    eq "" "${path_seen}" "isolation: no bs in the test PATH"
    eq "n" "$(has ":${T}/bin:/usr/bin:/bin:" "${REAL_HOME}/.local/bin")" "isolation: real ~/.local/bin is not in the test PATH"
    eq "n" "$(has "${T}/sys" "/usr/local")" "isolation: system prefix is inside the sandbox"
    rm -rf "${T}"
}

# 1. --local при только system, и наоборот, и ни там ни там
test_missing_kind() {
    sandbox
    local src="${T}/src"
    make_src "${src}" 0.8.0
    make_inst "${T}/sys/lib/bs" 0.6.0
    local before; before="$(tree_sum "${T}/sys/lib/bs")"
    run_bs update --local --from "${src}"
    eq "1" "${RC}" "1: --local with a system-only install exits 1"
    eq "y" "$(has "${OUT}" "локальной установки нет")" "1: says there is no local install (RU)"
    eq "y" "$(has "${OUT}" "no local install")" "1: says there is no local install (EN)"
    eq "y" "$(has "${OUT}" "${T}/sys/lib/bs (версия/version 0.6.0)")" "1: names the system install and its version"
    eq "y" "$(has "${OUT}" "bs update --system")" "1: suggests bs update --system"
    eq "${before}" "$(tree_sum "${T}/sys/lib/bs")" "1: system install untouched"
    rm -rf "${T}/sys/lib/bs"

    make_inst "${T}/home/.local/lib/bs" 0.7.0
    before="$(tree_sum "${T}/home/.local/lib/bs")"
    run_bs update --system --from "${src}"
    eq "1" "${RC}" "1: --system with a local-only install exits 1"
    eq "y" "$(has "${OUT}" "системной установки нет")" "1: says there is no system install"
    eq "y" "$(has "${OUT}" "bs update --local")" "1: suggests bs update --local"
    eq "${before}" "$(tree_sum "${T}/home/.local/lib/bs")" "1: local install untouched"
    rm -rf "${T}/home/.local"

    run_bs update --local --from "${src}"
    eq "1" "${RC}" "1: --local with no install at all exits 1"
    eq "y" "$(has "${OUT}" "BS не установлена")" "1: not installed (RU)"
    eq "y" "$(has "${OUT}" "./install.sh --local")" "1: suggests ./install.sh --local"
    run_bs update --from "${src}"
    eq "1" "${RC}" "1: autodetect with no install exits 1"
    eq "y" "$(has "${OUT}" "BS НЕ УСТАНОВЛЕНА / BS NOT INSTALLED")" "1: box title for no installs"
    eq "n" "$(has "${OUT}" "see messages above")" "1: no raw 'see messages above'"
    rm -rf "${T}"
}

test_system_not_writable() {
    if (( EUID == 0 )); then
        chk_true "true" "skipped: running as root"
        return 0
    fi
    sandbox
    make_src "${T}/src" 0.8.0
    make_inst "${T}/sys/lib/bs" 0.6.0
    chmod 555 "${T}/sys/lib/bs"
    local before; before="$(tree_sum "${T}/sys/lib/bs")"
    run_bs update --system --from "${T}/src"
    chmod 755 "${T}/sys/lib/bs"
    eq "1" "${RC}" "1: read-only system install without a terminal exits 1"
    eq "y" "$(has "${OUT}" "sudo bs update --system")" "1: keeps the sudo hint"
    eq "${before}" "$(tree_sum "${T}/sys/lib/bs")" "1: read-only install untouched"
    rm -rf "${T}"
}

# 2. --lib на чужой каталог / на репозиторий
test_foreign_target() {
    sandbox
    make_src "${T}/src" 0.8.0
    mkdir -p "${T}/foreign/lib" "${T}/foreign/core" "${T}/foreign/bootstrap"
    printf 'mine\n' > "${T}/foreign/lib/mine.txt"
    printf 'mine\n' > "${T}/foreign/core/mine.txt"
    local before; before="$(tree_sum "${T}/foreign")"
    run_bs update --lib "${T}/foreign" --from "${T}/src"
    eq "1" "${RC}" "2: foreign directory as --lib exits 1"
    eq "y" "$(has "${OUT}" "не установка BS")" "2: explains the target is not a BS install"
    eq "${before}" "$(tree_sum "${T}/foreign")" "2: foreign directory untouched"

    make_inst "${T}/repo" 0.8.0
    mkdir -p "${T}/repo/tests"
    before="$(tree_sum "${T}/repo")"
    run_bs update --lib "${T}/repo" --from "${T}/src"
    eq "1" "${RC}" "2: repository (tests/) as --lib exits 1"
    eq "y" "$(has "${OUT}" "исходный репозиторий")" "2: explains the target is a source checkout"
    eq "${before}" "$(tree_sum "${T}/repo")" "2: repository untouched"

    mkdir -p "${T}/gitrepo/.git"
    run_bs update --lib "${T}/gitrepo" --from "${T}/src"
    eq "1" "${RC}" "2: a .git directory as --lib exits 1"
    rm -rf "${T}"
}

# 3. Негодный источник: отказ ДО записей
test_bad_source() {
    sandbox
    make_inst "${T}/target" 0.5.0
    local before; before="$(tree_sum "${T}/target")"
    mkdir -p "${T}/fake/core"
    run_bs update --lib "${T}/target" --from "${T}/fake"
    eq "1" "${RC}" "3: incomplete source exits 1"
    eq "y" "$(has "${OUT}" "bootstrap/loader.sh")" "3: lists bootstrap/loader.sh as missing"
    eq "y" "$(has "${OUT}" "core/version.sh")" "3: lists core/version.sh as missing"
    eq "y" "$(has "${OUT}" "ИСТОЧНИК НЕ ПОДХОДИТ")" "3: box title"
    eq "${before}" "$(tree_sum "${T}/target")" "3: target checksum unchanged"

    make_src "${T}/nover" 1.0.0
    printf '# nothing\n' > "${T}/nover/core/version.sh"
    run_bs update --lib "${T}/target" --from "${T}/nover"
    eq "1" "${RC}" "3: source without a readable version exits 1"
    eq "y" "$(has "${OUT}" "версия не читается")" "3: names the unreadable version"

    run_bs update --lib "${T}/target" --from "${T}/does-not-exist"
    eq "1" "${RC}" "3: missing source exits 1"
    eq "y" "$(has "${OUT}" "каталог не найден")" "3: missing source explained"
    eq "${before}" "$(tree_sum "${T}/target")" "3: target unchanged after all refusals"
    eq "0" "$(leftovers "${T}/target")" "3: no .update leftovers"
    rm -rf "${T}"
}

# 4. smoke-test и откат; прерывание; устаревшие хвосты
test_smoke_rollback() {
    sandbox
    make_inst "${T}/target" 0.5.0
    make_src "${T}/bad" 9.0.0
    printf '#!/usr/bin/env bash\necho broken >&2\nexit 3\n' > "${T}/bad/bs"
    local before; before="$(tree_sum "${T}/target")"
    run_bs update --lib "${T}/target" --from "${T}/bad"
    eq "1" "${RC}" "4: failing smoke test exits 1"
    eq "y" "$(has "${OUT}" "самопроверка не прошла")" "4: says the smoke test failed"
    eq "y" "$(has "${OUT}" "восстановлена")" "4: says the previous version was restored"
    eq "${before}" "$(tree_sum "${T}/target")" "4: target rolled back (checksum equal)"
    eq "0" "$(leftovers "${T}/target")" "4: no .update leftovers after rollback"

    # Прерывание посреди замены: поддельный mv задерживается на 4-м вызове
    # Interrupt in the middle of the swap: a fake mv stalls on its 4th call
    mkdir -p "${T}/fb"
    printf '#!/bin/bash\nn=$(cat "%s/cnt" 2>/dev/null || echo 0); n=$((n+1)); echo $n > "%s/cnt"\nif [ $n -eq 4 ]; then sleep 3; fi\nexec /usr/bin/mv "$@"\n' "${T}/fb" "${T}/fb" > "${T}/fb/mv"
    chmod +x "${T}/fb/mv"
    make_src "${T}/good" 9.1.0
    (cd "${T}" && exec env -u BS_ROOT -u BS_HOME HOME="${T}/home" PATH="${T}/fb:/usr/bin:/bin" BS_SYSTEM_PREFIX="${T}/sys" \
        bash "${BS_CLI}" update --lib "${T}/target" --from "${T}/good" >"${T}/o.txt" 2>&1 </dev/null) &
    local pid=$!
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        [[ "$(cat "${T}/fb/cnt" 2>/dev/null || echo 0)" == "4" ]] && break
        sleep 0.5
    done
    kill -TERM "${pid}" 2>/dev/null || true
    wait "${pid}" 2>/dev/null || true
    eq "${before}" "$(tree_sum "${T}/target")" "4: interrupted update leaves the old version (no old/new mix)"
    eq "0" "$(leftovers "${T}/target")" "4: interrupted update leaves no .update dirs and no lock"

    # Хвосты мёртвого процесса убираются, прерванная замена откатывается
    # Leftovers of a dead process are removed, an interrupted swap is rolled back
    mkdir -p "${T}/target/.update.999999" "${T}/target/.update-old.999999"
    mv "${T}/target/core" "${T}/target/.update-old.999999/core"
    run_bs update --lib "${T}/target" --from "${T}/good"
    eq "0" "${RC}" "4: update after a crashed run succeeds"
    eq "0" "$(leftovers "${T}/target")" "4: stale .update.PID dirs are cleaned at start"
    eq "y" "$(has "${OUT}" "восстановлена установка")" "4: announces the restore of an interrupted run"
    chk_cmd "test -f '${T}/target/core/version.sh'" "4: core restored/updated"
    rm -rf "${T}"
}

# 5. Сбой копирования
test_copy_failure() {
    if (( EUID == 0 )); then
        chk_true "true" "skipped: running as root"
        return 0
    fi
    sandbox
    make_inst "${T}/target" 0.5.0
    make_src "${T}/src" 9.2.0
    printf 'x\n' > "${T}/src/lib/unreadable"
    chmod 000 "${T}/src/lib/unreadable"
    local before; before="$(tree_sum "${T}/target")"
    run_bs update --lib "${T}/target" --from "${T}/src"
    chmod 644 "${T}/src/lib/unreadable"
    eq "1" "${RC}" "5: copy failure exits 1 (not 0)"
    eq "y" "$(has "${OUT}" "копирование не удалось")" "5: says the copy failed"
    eq "n" "$(has "${OUT}" "ОБНОВЛЕНИЙ НЕТ")" "5: not reported as 'no updates'"
    eq "${before}" "$(tree_sum "${T}/target")" "5: target unchanged"
    eq "0" "$(leftovers "${T}/target")" "5: no leftovers"
    rm -rf "${T}"
}

# 6. --github: сообщения об ошибках (только file:// репозитории)
test_github_errors() {
    if ! utils::has git; then
        chk_true "true" "skipped: no git"
        return 0
    fi
    sandbox
    make_inst "${T}/target" 0.5.0
    make_src "${T}/remote" 5.0.0
    git -C "${T}/remote" init --quiet --initial-branch=main
    git -C "${T}/remote" add -A
    git -C "${T}/remote" -c user.name=t -c user.email=t@example.com commit --quiet -m init
    local before; before="$(tree_sum "${T}/target")"
    run_bs update --lib "${T}/target" --repo "file://${T}/remote" --ref no-such-branch
    eq "1" "${RC}" "6: missing ref exits 1"
    eq "y" "$(has "${OUT}" "'no-such-branch' не найден в file://${T}/remote")" "6: names the missing branch/tag and the repo"
    eq "0" "$(ls -A "${T}/tmpd" | wc -l | tr -d ' ')" "6: temporary download directory removed"

    run_bs update --lib "${T}/target" --repo "file://${T}/not-a-repo"
    eq "1" "${RC}" "6: unreachable repository exits 1"
    eq "y" "$(has "${OUT}" "репозиторий не найден")" "6: explains no network / no repository"
    eq "0" "$(ls -A "${T}/tmpd" | wc -l | tr -d ' ')" "6: temporary directory removed after a failed fetch"

    # Репозиторий есть, но это не BS: отказ источника, цель цела
    # A repository that is not BS: the source is refused, the target is intact
    mkdir -p "${T}/other"
    printf 'hi\n' > "${T}/other/README"
    git -C "${T}/other" init --quiet --initial-branch=main
    git -C "${T}/other" add -A
    git -C "${T}/other" -c user.name=t -c user.email=t@example.com commit --quiet -m init
    run_bs update --lib "${T}/target" --repo "file://${T}/other"
    eq "1" "${RC}" "6: a repository that is not BS exits 1"
    eq "y" "$(has "${OUT}" "ИСТОЧНИК НЕ ПОДХОДИТ")" "6: not-BS repository is an invalid source"

    # Нет git и curl/wget / no git and no curl/wget
    mkdir -p "${T}/tools"
    local f n
    for f in /usr/bin/*; do
        n="${f##*/}"
        case "${n}" in git|curl|wget) ;; *) ln -sf "${f}" "${T}/tools/${n}" ;; esac
    done
    OUT="$(cd "${T}" && env -u BS_ROOT -u BS_HOME -u BS_INITIALIZED HOME="${T}/home" PATH="${T}/tools" \
        BS_SYSTEM_PREFIX="${T}/sys" TMPDIR="${T}/tmpd" "$(command -v bash)" "${BS_CLI}" update --lib "${T}/target" --github 2>&1 </dev/null)" && RC=0 || RC=$?
    eq "1" "${RC}" "6: no git and no curl/wget exits 1"
    eq "y" "$(has "${OUT}" "нужен git или curl/wget")" "6: says git or curl/wget is needed"
    eq "${before}" "$(tree_sum "${T}/target")" "6: target unchanged after all fetch errors"
    rm -rf "${T}"
}

# 7. root/sudo и ~
test_sudo_hint() {
    sandbox
    make_src "${T}/src" 0.8.0
    OUT="$(cd "${T}" && env -u BS_ROOT -u BS_HOME -u BS_INITIALIZED SUDO_USER="$(id -un)" \
        HOME="${T}/home" PATH="${T}/bin:/usr/bin:/bin" BS_SYSTEM_PREFIX="${T}/sys" \
        bash "${BS_CLI}" update --local --from "${T}/src" 2>&1 </dev/null)" && RC=0 || RC=$?
    eq "1" "${RC}" "7: --local under sudo with no install exits 1"
    eq "y" "$(has "${OUT}" "вы root/sudo")" "7: explains that ~ is root's home"
    eq "y" "$(has "${OUT}" "установка пользователя $(id -un)")" "7: points at the sudo user's own install"
    eq "n" "$(has "${OUT}" "${REAL_HOME}/.local/lib/bs/.install")" "7: nothing of the real home is read or written"
    rm -rf "${T}"
}

# 8. Сломанная обёртка / lib без обёртки
test_wrappers() {
    sandbox
    make_src "${T}/src" 0.8.0
    make_wrapper "${T}/bin/bs" "${T}/gone/lib/bs"
    make_inst "${T}/sys/lib/bs" 0.6.0
    run_bs update --from "${T}/src"
    eq "0" "${RC}" "8: the valid install is still updated"
    eq "y" "$(has "${OUT}" "указывает на несуществующий ${T}/gone/lib/bs")" "8: warns about the broken wrapper"
    eq "y" "$(has "${OUT}" "нет обёртки ${T}/sys/bin/bs")" "8: warns that the lib has no wrapper"
    rm -rf "${T}"
}

# 9. Несколько установок, сводка, DOWNGRADE
test_multi_and_downgrade() {
    sandbox
    make_src "${T}/src" 0.8.0
    make_inst "${T}/sys/lib/bs" 0.6.0
    make_inst "${T}/home/.local/lib/bs" 0.7.0
    make_wrapper "${T}/bin/bs" "${T}/home/.local/lib/bs"
    run_bs update --from "${T}/src"
    eq "0" "${RC}" "9: two installs updated, exit 0"
    eq "y" "$(has "${OUT}" "${T}/sys/lib/bs: 0.6.0 → 0.8.0")" "9: summary system 0.6.0 → 0.8.0"
    eq "y" "$(has "${OUT}" "${T}/home/.local/lib/bs: 0.7.0 → 0.8.0")" "9: summary local 0.7.0 → 0.8.0"
    eq "y" "$(has "${OUT}" "1. ${T}/bin/bs → ${T}/home/.local/lib/bs")" "9: PATH order: who runs what"

    make_src "${T}/old" 0.1.0
    run_bs update --lib "${T}/sys/lib/bs" --from "${T}/old"
    eq "y" "$(has "${OUT}" "DOWNGRADE 0.8.0 → 0.1.0")" "9: DOWNGRADE warning for explicit --lib"
    run_bs update --system --from "${T}/src"
    run_bs update --system --from "${T}/old"
    eq "y" "$(has "${OUT}" "DOWNGRADE")" "9: DOWNGRADE warning for --system"
    rm -rf "${T}"
}

# 10. Манифест: битый / нет / симлинк
test_manifest_and_symlink() {
    sandbox
    make_src "${T}/src" 0.8.0
    make_inst "${T}/real/lib/bs" 0.5.0
    ln -s "${T}/real/lib/bs" "${T}/link"
    head -c 200 /dev/urandom > "${T}/real/lib/bs/.install"
    run_bs update --lib "${T}/link" --from "${T}/src"
    eq "0" "${RC}" "10: update through a symlink with a corrupt manifest exits 0"
    eq "y" "$(has "${OUT}" "манифест повреждён")" "10: warns about the corrupt manifest"
    eq "y" "$(has "${OUT}" "символическая ссылка")" "10: announces the symlink"
    chk_cmd "test -f '${T}/real/lib/bs/.install.bad'" "10: corrupt manifest kept as .install.bad"
    chk_cmd "grep -qx 'version=0.8.0' '${T}/real/lib/bs/.install'" "10: new manifest written"
    chk_cmd "test -L '${T}/link'" "10: the symlink itself is intact"

    rm -f "${T}/real/lib/bs/.install"
    make_src "${T}/src2" 0.9.0
    run_bs update --lib "${T}/real/lib/bs" --from "${T}/src2"
    eq "0" "${RC}" "10: install without a manifest is updated"
    chk_cmd "grep -q '^mode=custom' '${T}/real/lib/bs/.install'" "10: missing manifest is created"
    rm -rf "${T}"
}

# 11. Одновременный запуск
test_lock() {
    sandbox
    make_src "${T}/src" 0.8.0
    make_inst "${T}/target" 0.5.0
    mkdir "${T}/target/.update-lock"
    printf '%s\n' "$$" > "${T}/target/.update-lock/pid"
    local before; before="$(tree_sum "${T}/target")"
    run_bs update --lib "${T}/target" --from "${T}/src"
    eq "1" "${RC}" "11: a target locked by a live update exits 1"
    eq "y" "$(has "${OUT}" "уже идёт другое обновление")" "11: explains another update is running"
    eq "${before}" "$(tree_sum "${T}/target")" "11: locked target unchanged"
    printf '999999\n' > "${T}/target/.update-lock/pid"
    run_bs update --lib "${T}/target" --from "${T}/src"
    eq "0" "${RC}" "11: a stale lock (dead pid) is taken over"
    eq "0" "$(leftovers "${T}/target")" "11: lock released after the run"
    rm -rf "${T}"
}

# 12. Совмещения флагов
test_flag_combinations() {
    sandbox
    make_src "${T}/src" 0.8.0
    make_inst "${T}/target" 0.5.0
    run_bs update --ref
    eq "1" "${RC}" "12: --ref without a value exits 1"
    eq "y" "$(has "${OUT}" "--ref требует значение")" "12: --ref without a value explained"
    run_bs update --ref --github
    eq "1" "${RC}" "12: --ref swallowing the next flag exits 1"
    run_bs update --repo "a b"
    eq "1" "${RC}" "12: --repo with a space exits 1"
    eq "y" "$(has "${OUT}" "пробелы")" "12: --repo with a space explained"
    run_bs update --ref a --ref b
    eq "1" "${RC}" "12: conflicting repeated --ref exits 1"
    run_bs update --from "${T}/src" --from "${T}/target"
    eq "1" "${RC}" "12: conflicting repeated --from exits 1"
    run_bs update --github --from "${T}/src"
    eq "1" "${RC}" "12: --github with --from exits 1"

    run_bs update --lib "${T}/target" --lib "${T}/target/" --from "${T}/src"
    eq "0" "${RC}" "12: a repeated --lib is merged"
    eq "1" "$(grep -c '✓' <<< "${OUT}" | tr -d ' ')" "12: the repeated target is updated once"

    local before; before="$(tree_sum "${T}/target")"
    run_bs update --lib "${T}/target" --from "${T}/target"
    eq "0" "${RC}" "12: --from the target itself is a harmless no-op"
    eq "y" "$(has "${OUT}" "источник совпадает с целью")" "12: source == target explained"

    mkdir -p "${T}/target/inner"
    make_src "${T}/target/inner/src" 0.9.0
    run_bs update --lib "${T}/target" --from "${T}/target/inner/src"
    eq "1" "${RC}" "12: source inside the target exits 1"
    eq "y" "$(has "${OUT}" "внутри цели")" "12: source inside the target explained"
    rm -rf "${T}/target/inner"

    make_inst "${T}/srcwithin" 0.9.0
    mkdir -p "${T}/srcwithin/lib/nested"
    make_inst "${T}/srcwithin/lib/nested/bs" 0.1.0
    run_bs update --lib "${T}/srcwithin/lib/nested/bs" --from "${T}/srcwithin"
    eq "1" "${RC}" "12: target inside the source's lib exits 1"
    eq "y" "$(has "${OUT}" "цель внутри копируемых каталогов")" "12: target inside the source explained"
    eq "${before}" "$(tree_sum "${T}/target")" "12: target unchanged by all refusals"

    make_inst "${T}/sys/lib/bs" 0.5.0
    make_inst "${T}/home/.local/lib/bs" 0.5.0
    make_src "${T}/src3" 0.9.5
    run_bs update --local --system --lib "${T}/target" --from "${T}/src3"
    eq "0" "${RC}" "12: --local --system --lib together update three targets"
    eq "3" "$(grep -c '✓' <<< "${OUT}" | tr -d ' ')" "12: three targets in the summary"
    rm -rf "${T}"
}

# Сводка запущенной копии: начало вывода, рамки, ERROR/WARN, --help без неё
test_running_info() {
    sandbox
    make_src "${T}/src" 0.8.0
    make_inst "${T}/target" 0.5.0
    local first
    run_bs update --lib "${T}/target" --from "${T}/src"
    first="${OUT%%$'\n'*}"
    eq "y" "$(has "${first}" "Запущен / Running: bs ")" "info: first line of a run names the running bs"
    # Ниже первой строки — те же сведения, что печатает `bs version --full`
    # Below the first line: the same details `bs version --full` prints
    local full
    full="$(bash "${BS_PROJECT_ROOT}/bs" version --full | tail -n +2)"
    eq "y" "$(has "${OUT}" "  root:      ${BS_PROJECT_ROOT}")" "info: the run header has the root row of version --full"
    eq "y" "$(has "${OUT}" "  install:")" "info: the run header has the install row of version --full"
    eq "y" "$(has "${OUT}" "${full%%$'\n'*}")" "info: the first detail line equals the one of version --full"

    run_bs update --lib "${T}/target" --from "${T}/src"
    eq "y" "$(has "${OUT}" "уже актуально")" "info: the up-to-date box appears"
    eq "y" "$(has "${OUT}" "  install:")" "info: the box carries the install row of version --full"
    eq "y" "$(has "${OUT}" "Запущен / Running: bs ")" "info: the box carries the running copy as its first body line"

    run_bs update --lib "${T}/target" --from "${T}/nope"
    eq "y" "$(has "${OUT}" "Запущен / Running: bs ")" "info: the invalid-source box carries it too"
    run_bs update --bogus
    eq "y" "$(has "${OUT}" "(Запущен / Running: bs ")" "info: ERROR lines end with the short running-copy summary"
    run_bs update --ref
    eq "y" "$(has "${OUT}" "(Запущен / Running: bs ")" "info: flag errors end with the summary"
    make_inst "${T}/ro/lib/bs" 0.1.0
    run_bs update --local --from "${T}/src"
    eq "y" "$(has "${OUT}" "Запущен / Running: bs ")" "info: the missing-target box carries it"
    run_bs update --help
    eq "0" "${RC}" "info: --help exits 0"
    eq "Использование" "${OUT:0:13}" "info: --help prints no banner (starts with the usage)"
    eq "y" "$(has "${OUT}" "BS_SYSTEM_PREFIX")" "info: --help documents BS_SYSTEM_PREFIX"

    # Рамка: все строки одной ширины (паддинг по символам)
    run_bs update --local --from "${T}/src"
    local line bad=0
    while IFS= read -r line; do
        [[ "${line}" == '│'* ]] && (( ${#line} != 60 )) && bad=1
    done <<< "${RAW}"
    eq "0" "${bad}" "info: every box row is 60 characters wide (Cyrillic padding)"
    rm -rf "${T}"
}

main() {
    print_header "Update Safety Unit Tests / Негативные сценарии bs update"
    testframework::init

    testframework::section "Isolation / Изоляция"
    test_isolation
    testframework::section "1. Missing install kind / Нет нужной установки"
    test_missing_kind
    test_system_not_writable
    testframework::section "2. Foreign target / Чужая цель"
    test_foreign_target
    testframework::section "3. Bad source / Негодный источник"
    test_bad_source
    testframework::section "4. Smoke test and rollback / Откат"
    test_smoke_rollback
    testframework::section "5. Copy failure / Сбой копирования"
    test_copy_failure
    testframework::section "6. GitHub errors / Ошибки GitHub"
    test_github_errors
    testframework::section "7. sudo / root"
    test_sudo_hint
    testframework::section "8. Wrappers / Обёртки"
    test_wrappers
    testframework::section "9. Several installs / Несколько установок"
    test_multi_and_downgrade
    testframework::section "10. Manifest and symlink / Манифест и симлинк"
    test_manifest_and_symlink
    testframework::section "11. Lock / Блокировка"
    test_lock
    testframework::section "12. Flags / Флаги"
    test_flag_combinations
    testframework::section "Running copy info / Сводка запущенной копии"
    test_running_info

    testframework::summary
}

main "$@"
