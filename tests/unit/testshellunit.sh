#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testshellunit.sh — Unit tests for bootstrap/shell.sh (the shell registry)
# tests/unit/testshellunit.sh — Модульные тесты bootstrap/shell.sh (реестр оболочек)
#
# The registry is POSIX code: it is sourced and run by every shell found on the
# machine (bash, zsh, dash, ...), each in a temporary HOME under env -i.
# Реестр — POSIX-код: его подключает и исполняет каждая найденная на машине
# оболочка (bash, zsh, dash, ...), каждая во временном HOME под env -i.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly SHELL_SH="${BS_PROJECT_ROOT}/bootstrap/shell.sh"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"

T=""

# probe <shell> <snippet> — snippet выполняется после подключения shell.sh
probe() {
    local -r sh_bin="$1" snippet="$2"
    printf '. "%s"\n%s\n' "${SHELL_SH}" "${snippet}" > "${T}/probe.sh"
    env -i HOME="${T}/h" PATH="/usr/bin:/bin" ${PROBE_ENV:-} "${sh_bin}" "${T}/probe.sh" 2>&1
}

eq() { testframework::assert_equal "$1" "$2" "$3" || true; }
ok() { testframework::assert_true "$1" "$2" || true; }

test_parses_everywhere() {
    local sh_name sh_bin
    for sh_name in bash zsh dash; do
        sh_bin="$(command -v "${sh_name}" || true)"
        [[ -n "${sh_bin}" ]] || { printf '  skip: %s is not installed / не установлен\n' "${sh_name}"; continue; }
        testframework::assert_command "'${sh_bin}' -n '${SHELL_SH}'" "shell.sh parses in ${sh_name}" || true
        testframework::assert_command "'${sh_bin}' -n '${BS_PROJECT_ROOT}/bootstrap/trampoline.sh'" "trampoline.sh parses in ${sh_name}" || true
    done
    if utils::has shellcheck; then
        testframework::assert_command "shellcheck -s sh '${SHELL_SH}' '${BS_PROJECT_ROOT}/bootstrap/trampoline.sh'" "shellcheck -s sh is clean for the POSIX files" || true
    fi
}

test_family_per_shell() {
    local sh_name sh_bin
    for sh_name in bash zsh dash; do
        sh_bin="$(command -v "${sh_name}" || true)"
        [[ -n "${sh_bin}" ]] || continue
        eq "${sh_name}" "$(probe "${sh_bin}" 'bs_shell_family')" "family detected by ${sh_name} itself"
    done
    eq "yes" "$(probe bash 'bs_shell_host_ok && echo yes || echo no' 2>/dev/null || probe "$(command -v bash)" 'bs_shell_host_ok && echo yes || echo no')" "bash 4.2+ is a capable host"
    sh_bin="$(command -v zsh || true)"
    [[ -z "${sh_bin}" ]] || eq "no" "$(probe "${sh_bin}" 'bs_shell_host_ok && echo yes || echo no')" "zsh is not a host"
    sh_bin="$(command -v dash || true)"
    [[ -z "${sh_bin}" ]] || eq "no" "$(probe "${sh_bin}" 'bs_shell_host_ok && echo yes || echo no')" "dash is not a host"
}

test_of_name() {
    local bash_bin; bash_bin="$(command -v bash)"
    eq "bash dash ash ash zsh ksh mksh oksh osh osh fish nu nu sh unknown unknown" \
       "$(probe "${bash_bin}" 'for n in -bash /bin/dash ash busybox /usr/bin/zsh ksh93 mksh oksh osh ysh fish nu nushell sh pwsh ""; do printf "%s " "$(bs_shell_of_name "$n")"; done' | sed 's/ $//' | sed 's/bash dash ash ash zsh/bash dash ash ash zsh/')" \
       "bs_shell_of_name maps names and paths to families"
}

test_registry_lines() {
    local bash_bin; bash_bin="$(command -v bash)"
    local line
    line() { probe "${bash_bin}" "$1"; }
    eq "${T}/h/.bashrc"                         "$(line 'bs_shell_rc_file bash')" "rc file: bash"
    eq "${T}/h/.zshrc"                          "$(line 'bs_shell_rc_file zsh')"  "rc file: zsh"
    eq "${T}/h/.profile"                        "$(line 'bs_shell_rc_file dash')" "rc file: dash"
    eq "${T}/h/.profile"                        "$(line 'bs_shell_rc_file ash')"  "rc file: ash"
    eq "${T}/h/.profile"                        "$(line 'bs_shell_rc_file ksh')"  "rc file: ksh"
    eq "${T}/h/.config/oils/oshrc"              "$(line 'bs_shell_rc_file osh')"  "rc file: osh"
    eq "${T}/h/.config/fish/conf.d/bs.fish"     "$(line 'bs_shell_rc_file fish')" "rc file: fish"
    eq "${T}/h/.config/nushell/env.nu"          "$(line 'bs_shell_rc_file nu')"   "rc file: nushell"
    eq "1" "$(line 'bs_shell_rc_file pwsh >/dev/null 2>&1; echo $?')" "rc file: an unknown shell has none (exit 1)"

    # Строка PATH: одинаковый текст для установщика и удаления (точное совпадение)
    eq 'export PATH="$HOME/.local/bin:$PATH"' "$(line "bs_shell_path_line bash '\$HOME/.local/bin'")" "PATH line: bash (the historic text)"
    eq 'export PATH="$HOME/.local/bin:$PATH"' "$(line "bs_shell_path_line dash '\$HOME/.local/bin'")" "PATH line: dash"
    eq 'contains -- "$HOME/.local/bin" $PATH; or set -gx PATH "$HOME/.local/bin" $PATH' \
       "$(line "bs_shell_path_line fish '\$HOME/.local/bin'")" "PATH line: fish syntax"
    eq '$env.PATH = ($env.PATH | prepend ($env.HOME | path join ".local" "bin") | uniq)' \
       "$(line "bs_shell_path_line nu '\$HOME/.local/bin'")" "PATH line: nushell syntax for \$HOME/..."
    eq '$env.PATH = ($env.PATH | prepend "/opt/bs/bin" | uniq)' \
       "$(line "bs_shell_path_line nu /opt/bs/bin")" "PATH line: nushell syntax for an absolute dir"

    eq "source ~/.bashrc" "$(line 'bs_shell_reload_hint bash')" "reload: bash"
    eq "source ~/.zshrc"  "$(line 'bs_shell_reload_hint zsh')"  "reload: zsh"
    eq ". ~/.profile"     "$(line 'bs_shell_reload_hint ash')"  "reload: ash"
    eq "exec nu"          "$(line 'bs_shell_reload_hint nu')"   "reload: nushell"
    eq "-l" "$(line 'bs_shell_fresh_flags dash')" "fresh shell flags: dash reads .profile with -l"
    eq ""   "$(line 'bs_shell_fresh_flags bash')" "fresh shell flags: bash needs none"
    eq "known unknown" "$(line 'bs_shell_known nu && printf known; bs_shell_known pwsh || printf " unknown"')" "bs_shell_known"
    ok "$(line 'bs_shell_all_rc_files' | grep -c .) -ge 12" "all rc files: the union of every family is not empty"
    eq "0" "$(line 'bs_shell_all_rc_files | sort | uniq -d | wc -l')" "all rc files: no duplicates"
}

test_user_shell() {
    local bash_bin; bash_bin="$(command -v bash)"
    PROBE_ENV="BS_USER_SHELL=zsh" eq "zsh" "$(PROBE_ENV='BS_USER_SHELL=zsh' probe "${bash_bin}" 'bs_shell_user')" "BS_USER_SHELL overrides the detection"
    eq "bash" "$(PROBE_ENV='BS_USER_SHELL=/usr/bin/bash' probe "${bash_bin}" 'bs_shell_user')" "BS_USER_SHELL accepts a path"

    # Родитель — не оболочка (python): остаётся логин-оболочка из $SHELL
    # The parent is not a shell (python): the login shell from $SHELL remains
    if utils::has python3; then
        local out
        printf '. "%s"\nbs_shell_user\n' "${SHELL_SH}" > "${T}/probe.sh"
        out="$(env -i HOME="${T}/h" PATH="/usr/bin:/bin" SHELL=/usr/bin/fish python3 -c "
import subprocess
r = subprocess.run(['${bash_bin}', '${T}/probe.sh'], capture_output=True, text=True)
print(r.stdout.strip())" 2>&1)" || true
        eq "fish" "${out}" "no shell parent: the login shell of \$SHELL (fish) is used"
        # bash сам выставляет SHELL из passwd, если он не задан — это учитывается
        # bash sets SHELL from passwd itself when it is unset — accounted for here
        local passwd_shell
        passwd_shell="$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f7)"
        out="$(env -i HOME="${T}/h" PATH="/usr/bin:/bin" python3 -c "
import subprocess
r = subprocess.run(['${bash_bin}', '${T}/probe.sh'], capture_output=True, text=True)
print(r.stdout.strip())" 2>&1)" || true
        eq "$(probe "${bash_bin}" "bs_shell_of_name '${passwd_shell:-bash}'")" "${out}" "no shell parent and no \$SHELL: the passwd login shell"
    fi
}

test_host_and_tier() {
    local bash_bin dash_bin zsh_bin
    bash_bin="$(command -v bash)"; dash_bin="$(command -v dash || true)"; zsh_bin="$(command -v zsh || true)"
    eq "${bash_bin}" "$(PROBE_ENV="BS_HOST_BASH=${bash_bin}" probe "${bash_bin}" 'bs_shell_host_find')" "BS_HOST_BASH is honoured when it is a bash 4.2+"
    eq "1" "$(PROBE_ENV='BS_HOST_BASH=/nonexistent' probe "${bash_bin}" 'bs_shell_host_find >/dev/null 2>&1; echo $?')" "BS_HOST_BASH that is not a bash 4.2+ is an error, not a silent fallback"
    eq "1" "$(PROBE_ENV="BS_HOST_BASH=${dash_bin:-/bin/dash}" probe "${bash_bin}" 'bs_shell_host_find >/dev/null 2>&1; echo $?')" "a dash given as BS_HOST_BASH is rejected"
    ok "'$(probe "${bash_bin}" 'bs_shell_host_find')' == /*" "a bash 4.2+ is found by itself"

    eq "native"      "$(PROBE_ENV='BS_USER_SHELL=bash' probe "${bash_bin}" 'bs_shell_tier')" "tier: bash under bash is native"
    eq "hosted"      "$(PROBE_ENV='BS_USER_SHELL=zsh'  probe "${bash_bin}" 'bs_shell_tier')" "tier: zsh user with a bash around is hosted"
    eq "hosted"      "$(PROBE_ENV='BS_USER_SHELL=nu'   probe "${bash_bin}" 'bs_shell_tier')" "tier: nushell user is hosted"
    eq "hosted"      "$(PROBE_ENV='BS_USER_SHELL=ash'  probe "${bash_bin}" 'bs_shell_tier')" "tier: ash user is hosted"
    [[ -z "${dash_bin}" ]] || eq "unsupported" "$(PROBE_ENV='BS_HOST_BASH=/nonexistent BS_USER_SHELL=dash' probe "${dash_bin}" 'bs_shell_tier')" "tier: no bash 4.2+ at all is unsupported"
    [[ -z "${zsh_bin}" ]] || eq "hosted" "$(PROBE_ENV='BS_USER_SHELL=zsh' probe "${zsh_bin}" 'bs_shell_tier')" "tier: seen from zsh itself it is hosted"

    local d
    d="$(probe "${bash_bin}" 'bs_shell_tier_desc native')"
    ok "'${d}' == *bash*library* && '${d}' == *'/'* " "tier description (native) is bilingual"
    d="$(probe "${bash_bin}" 'bs_shell_tier_desc unsupported')"
    ok "'${d}' == *'apk add bash'* && '${d}' == *BS_HOST_BASH* " "tier description (unsupported) says what to install"
    d="$(probe "${bash_bin}" 'bs_shell_tier_desc hosted')"
    ok "'${d}' == *'bs command'* " "tier description (hosted) names the bs command"
}

test_bs_init_shell() {
    local out
    run_init() { env -i HOME="${T}/h" PATH="/usr/bin:/bin" "$@" bash "${BS_PROJECT_ROOT}/bs" init-shell ${INIT_ARGS:-} 2>&1; }
    out="$(INIT_ARGS=bash run_init)"
    ok "'${out}' == *'tier: native'* && '${out}' == *'source \"\${BS_ROOT}/bootstrap/init.sh\"'* " "init-shell bash: the library snippet"
    out="$(INIT_ARGS=zsh run_init)"
    ok "'${out}' == *'tier: hosted'* && '${out}' == *'.zshrc'* && '${out}' != *'init.sh'* " "init-shell zsh: PATH only, no source of init.sh"
    out="$(INIT_ARGS=fish run_init)"
    ok "'${out}' == *'conf.d/bs.fish'* && '${out}' == *'set -gx PATH'* " "init-shell fish: its file and syntax"
    out="$(INIT_ARGS=nu run_init)"
    ok "'${out}' == *'env.nu'* && '${out}' == *'\$env.PATH'* && '${out}' == *'exec nu'* " "init-shell nu: env.nu, nushell syntax, exec nu"
    out="$(INIT_ARGS=--list run_init)"
    eq "12" "$(printf '%s\n' "${out}" | grep -c .)" "init-shell --list: header plus eleven shells"
    out="$(INIT_ARGS=pwsh run_init || true)"
    ok "'${out}' == *'unknown shell'* " "init-shell pwsh: unknown shell is explained"
    eq "1" "$(INIT_ARGS=pwsh run_init >/dev/null 2>&1; echo $?)" "init-shell pwsh: non-zero exit"
}

main() {
    print_header "Shell Registry Unit Tests / Модульные тесты реестра оболочек"

    testframework::init
    T="$(mktemp -d)"
    mkdir -p "${T}/h"

    testframework::section "Parsing / Разбор"
    test_parses_everywhere

    testframework::section "Detection / Определение"
    test_family_per_shell
    test_of_name
    test_user_shell

    testframework::section "Registry / Реестр"
    test_registry_lines

    testframework::section "Host and tier / Хозяин и tier"
    test_host_and_tier

    testframework::section "bs init-shell"
    test_bs_init_shell

    rm -rf "${T:?}"
    testframework::summary
}

main "$@"
