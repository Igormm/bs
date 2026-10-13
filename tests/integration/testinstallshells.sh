#!/usr/bin/env bs
# shellcheck shell=bash
# tests/integration/testinstallshells.sh — the installer sets PATH up for the USER's shell
# tests/integration/testinstallshells.sh — установщик настраивает PATH под оболочку ПОЛЬЗОВАТЕЛЯ
#
# bash, zsh, dash/ash, fish and nushell: the right rc file, the right syntax,
# the right reload command, and an uninstall that leaves nothing behind. Every
# case runs in a temporary HOME under env -i; the real install is never seen.
# bash, zsh, dash/ash, fish и nushell: нужный rc-файл, нужный синтаксис, нужная
# команда перезагрузки, а удаление не оставляет следов. Каждый случай — во
# временном HOME под env -i; настоящая установка не видна.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"

E=""
OUT=""
RC=0

new_env() {
    E="$(mktemp -d)"
    mkdir -p "${E}/home" "${E}/sys"
}

# inst [VAR=val ...] -- args...
inst() {
    local -a envs=()
    while [[ "$1" != "--" ]]; do envs+=("$1"); shift; done
    shift
    RC=0
    OUT="$(cd "${BS_PROJECT_ROOT}" && env -i HOME="${E}/home" PATH="/usr/bin:/bin" \
        BS_SYSTEM_PREFIX="${E}/sys" "${envs[@]}" bash ./install.sh "$@" </dev/null 2>&1)" || RC=$?
}

eq() { testframework::assert_equal "$1" "$2" "$3" || true; }
has() {
    if [[ "${OUT}" == *"$1"* ]]; then testframework::assert_true "true" "$2" || true
    else testframework::assert_true "false" "$2" || true; printf '    not found / не найдено: %s\n' "$1"; fi
}
last_line() { tail -n 1 "$1"; }
mentions() { (cd "${E}/home" && grep -rl "local/bin" . 2>/dev/null | sort | tr '\n' ' ' | sed 's/ $//'); }

readonly POSIX_LINE='export PATH="$HOME/.local/bin:$PATH"'

test_each_shell() {
    local sh rc line reload
    for sh in bash zsh dash ash; do
        new_env
        inst -- --local --shell "${sh}"
        rc="${E}/home/.bashrc"; reload="source ~/.bashrc"
        case "${sh}" in
            zsh) rc="${E}/home/.zshrc"; reload="source ~/.zshrc" ;;
            dash|ash) rc="${E}/home/.profile"; reload=". ~/.profile" ;;
        esac
        eq "0" "${RC}" "--shell ${sh}: exit 0"
        testframework::assert_command "test -f '${rc}'" "--shell ${sh}: ${rc##*/} is created" || true
        eq "${POSIX_LINE}" "$(last_line "${rc}")" "--shell ${sh}: the POSIX PATH line"
        has "${reload}" "--shell ${sh}: the reload command is ${reload}"
        inst -- --local uninstall
        eq "" "$(mentions)" "--shell ${sh}: uninstall leaves no PATH line behind"
        rm -rf "${E:?}"
    done
}

test_fish() {
    new_env
    inst -- --local --shell fish
    local f="${E}/home/.config/fish/conf.d/bs.fish"
    eq "0" "${RC}" "--shell fish: exit 0"
    testframework::assert_command "test -f '${f}'" "--shell fish: conf.d/bs.fish is created" || true
    eq 'contains -- "$HOME/.local/bin" $PATH; or set -gx PATH "$HOME/.local/bin" $PATH' "$(last_line "${f}")" "--shell fish: the fish PATH line"
    has "source ~/.config/fish/conf.d/bs.fish" "--shell fish: the fish reload command"
    testframework::assert_command "test ! -e '${E}/home/.bashrc'" "--shell fish: ~/.bashrc is not touched" || true
    inst -- --local uninstall
    testframework::assert_command "test ! -e '${f}'" "uninstall removes the fish file the installer created" || true
    rm -rf "${E:?}"
}

test_nushell() {
    new_env
    inst -- --local --shell nu
    eq "0" "${RC}" "--shell nu without env.nu: exit 0"
    testframework::assert_command "test ! -e '${E}/home/.config/nushell/env.nu'" "nushell: env.nu is NOT created from scratch" || true
    has '$env.PATH = ($env.PATH | prepend ($env.HOME | path join ".local" "bin") | uniq)' "nushell: the exact line is printed for the user"
    has "does not exist" "nushell: the reason is explained"
    inst -- --local uninstall
    rm -rf "${E:?}"

    new_env
    mkdir -p "${E}/home/.config/nushell"
    printf '# my nushell env\n$env.FOO = 1\n' > "${E}/home/.config/nushell/env.nu"
    inst -- --local --shell nu
    local f="${E}/home/.config/nushell/env.nu"
    eq '$env.PATH = ($env.PATH | prepend ($env.HOME | path join ".local" "bin") | uniq)' "$(last_line "${f}")" "nushell with env.nu: the line is appended"
    eq "2" "$(grep -c -e '# my nushell env' -e 'FOO = 1' "${f}")" "nushell: the user's lines are untouched"
    has "exec nu" "nushell: the reload command is exec nu"
    inst -- --local uninstall
    eq '# my nushell env
$env.FOO = 1' "$(grep -v '^$' "${f}")" "uninstall removes only the installer's nushell line"
    rm -rf "${E:?}"
}

test_user_shell_sources() {
    new_env
    inst BS_USER_SHELL=zsh -- --local
    testframework::assert_command "test -f '${E}/home/.zshrc'" "BS_USER_SHELL=zsh selects ~/.zshrc" || true
    inst -- --local uninstall
    rm -rf "${E:?}"

    new_env
    inst -- --local --shell pwsh
    eq "1" "${RC}" "--shell with an unknown name: exit 1"
    has "bash zsh ash dash sh ksh mksh oksh osh fish nu" "--shell with an unknown name: lists the known shells"
    inst -- --local --shell
    eq "1" "${RC}" "--shell without a name: exit 1"
    rm -rf "${E:?}"
}

test_compat_existing_rc() {
    # Как всегда было: уже существующие .bashrc и .zshrc получают строку тоже
    # As it always was: existing .bashrc and .zshrc get the line too
    new_env
    printf '# bashrc\n' > "${E}/home/.bashrc"
    printf '# zshrc\n' > "${E}/home/.zshrc"
    inst -- --local --shell zsh
    eq "${POSIX_LINE}" "$(last_line "${E}/home/.zshrc")" "zsh user: .zshrc gets the line"
    eq "${POSIX_LINE}" "$(last_line "${E}/home/.bashrc")" "an existing .bashrc gets the line too (compatibility)"
    inst -- --local --update-path --shell zsh
    eq "1" "$(grep -c -F "${POSIX_LINE}" "${E}/home/.zshrc")" "--update-path is idempotent"
    inst -- --local uninstall
    eq "" "$(mentions)" "uninstall cleans every shell's file"
    rm -rf "${E:?}"

    # dash и ash делят ~/.profile — строка одна
    new_env
    inst -- --local --shell dash
    inst -- --local --update-path --shell ash
    eq "1" "$(grep -c -F "${POSIX_LINE}" "${E}/home/.profile")" "dash and ash share ~/.profile: the line is written once"
    rm -rf "${E:?}"
}

test_path_hint() {
    new_env
    inst -- --local --path --shell zsh
    has "shell: zsh" "--path --shell zsh: names the shell"
    has "${E}/home/.zshrc" "--path --shell zsh: names the rc file"
    has "source ~/.zshrc" "--path --shell zsh: the reload command"
    inst -- --local --path --shell fish
    has 'set -gx PATH' "--path --shell fish: the fish syntax"
    inst -- --local --path --shell nu
    has '$env.PATH' "--path --shell nu: the nushell syntax"
    rm -rf "${E:?}"
}

main() {
    print_header "Installer Shell Tests / Тесты установщика по оболочкам"

    testframework::init

    testframework::section "bash, zsh, dash, ash / POSIX-подобные"
    test_each_shell
    testframework::section "fish"
    test_fish
    testframework::section "nushell"
    test_nushell
    testframework::section "Selecting the shell / Выбор оболочки"
    test_user_shell_sources
    test_compat_existing_rc
    test_path_hint

    testframework::summary
}

main "$@"
