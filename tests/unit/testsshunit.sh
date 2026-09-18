#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testsshunit.sh — Unit tests for lib/network/ssh (mocked ssh/rsync)
# tests/unit/testsshunit.sh — Модульные тесты для lib/network/ssh (мок ssh/rsync)

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

load "lib/network/ssh"

test_ssh_run() {
    local tmp_dir mock log
    tmp_dir="$(mktemp -d)"
    log="${tmp_dir}/ssh.log"
    mock="${tmp_dir}/mock-ssh"

    # Мок: логирует аргументы, печатает SSH_MOCK_OUTPUT, коды из SSH_MOCK_RC
    cat > "${mock}" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${log}"
printf '%s\n' "\${SSH_MOCK_OUTPUT:-mock-ok}"
exit "\${SSH_MOCK_RC:-0}"
EOF
    chmod +x "${mock}"
    export SSH_MOCK="${mock}"
    export SSH_MOCK_LOG="${log}"

    # Обычный прогон / Plain run
    local out=""
    out="$(ssh::run -- user@host uptime)" || true
    testframework::assert_equal "mock-ok" "${out}" "ssh::run passes output through"
    testframework::assert_command "grep -q 'user@host uptime' '${log}'" "ssh::run invokes host and command"

    # Код возврата пробрасывается / Exit code propagates
    local rc=0
    export SSH_MOCK_RC=3
    ssh::run -- host "exit 3" || rc=$?
    testframework::assert_equal "3" "${rc}" "ssh::run propagates remote exit code"

    # Флаги / Flags
    export SSH_MOCK_RC=0
    touch "${tmp_dir}/id_rsa"
    ssh::run --user root --port 2222 --key "${tmp_dir}/id_rsa" -- host "id" >/dev/null 2>&1 || true
    testframework::assert_command "grep -q -- '-p 2222' '${log}'" "ssh::run passes port"
    testframework::assert_command "grep -q 'root@host' '${log}'" "ssh::run builds user@host"

    # Команда с флагами после -- / Command with flags after --
    ssh::run -- host "ls --color" >/dev/null 2>&1 || true
    testframework::assert_command "grep -q 'ls --color' '${log}'" "ssh::run keeps command flags after --"

    # Ошибки / Errors
    testframework::assert_false "ssh::run" "ssh::run rejects missing host"
    testframework::assert_false "ssh::run --bogus host cmd" "ssh::run rejects unknown flag"

    unset SSH_MOCK SSH_MOCK_LOG SSH_MOCK_RC SSH_MOCK_OUTPUT
    rm -rf "${tmp_dir}"
}

test_ssh_transfer() {
    local tmp_dir mock log
    tmp_dir="$(mktemp -d)"
    log="${tmp_dir}/rsync.log"
    mock="${tmp_dir}/mock-rsync"
    cat > "${mock}" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${log}"
exit 0
EOF
    chmod +x "${mock}"
    export RSYNC_MOCK="${mock}"
    export RSYNC_MOCK_LOG="${log}"

    ssh::push ./app.sh root@server:/opt/app/
    testframework::assert_command "grep -q 'app.sh root@server:/opt/app/' '${log}'" "ssh::push passes local and remote"
    testframework::assert_command "grep -q '--delete' '${log}' || true; grep -q 'app.sh' '${log}'" "ssh::push no delete by default"

    ssh::push ./conf root@server:/etc/app/ --delete --port 2222
    testframework::assert_command "grep -q -- '--delete' '${log}'" "ssh::push --delete flag"
    testframework::assert_command "grep -q -- '-p 2222' '${log}'" "ssh::push port flag"

    ssh::pull root@server:/var/log/app.log ./logs/
    testframework::assert_command "grep -q 'root@server:/var/log/app.log ./logs/' '${log}'" "ssh::pull passes remote and local"

    unset RSYNC_MOCK RSYNC_MOCK_LOG
    rm -rf "${tmp_dir}"
}

test_ssh_security() {
    local tmp_dir rc err
    tmp_dir="$(mktemp -d)"

    # Инъекция через --port в rsync -e: значение с пробелом отклоняется
    # Injection via --port into rsync -e: a value with a space is rejected
    rc=0
    err="$(ssh::push ./app.sh root@server:/opt/ --port '2222 -oProxyCommand=touch /tmp/pwned' 2>&1 >/dev/null)" || rc=$?
    testframework::assert_equal "1" "${rc}" "ssh::push rejects malicious --port (rc 1)"
    testframework::assert_command "printf '%s' '${err}' | grep -q 'invalid --port'" "ssh::push reports invalid --port error"

    # --key с пробелами отклоняется / --key with spaces is rejected
    rc=0
    err="$(ssh::push ./app.sh root@server:/opt/ --key '/tmp/my key' 2>&1 >/dev/null)" || rc=$?
    testframework::assert_equal "1" "${rc}" "ssh::push rejects --key with spaces (rc 1)"
    testframework::assert_command "printf '%s' '${err}' | grep -q 'invalid --key'" "ssh::push reports invalid --key error"

    # Несуществующий --key отклоняется / Nonexistent --key is rejected
    rc=0
    err="$(ssh::pull root@server:/x ./y --key "${tmp_dir}/no-such-key" 2>&1 >/dev/null)" || rc=$?
    testframework::assert_equal "1" "${rc}" "ssh::pull rejects missing --key (rc 1)"
    testframework::assert_command "printf '%s' '${err}' | grep -q 'file not found'" "ssh::pull reports missing --key error"

    # Инъекция опций: --user с ведущим '-' отклоняется
    # Option injection: --user with a leading '-' is rejected
    rc=0
    err="$(ssh::run --user '-oProxyCommand=touch /tmp/pwned' -- host id 2>&1 >/dev/null)" || rc=$?
    testframework::assert_equal "1" "${rc}" "ssh::run rejects --user with leading dash (rc 1)"
    testframework::assert_command "printf '%s' '${err}' | grep -q 'must not start with'" "ssh::run reports option-injection guard error"

    # Хост с ведущим '-' после '--' не становится опцией: ssh получает '--'
    # A host with a leading '-' after '--' is not an option: ssh gets its own '--'
    local mock log
    log="${tmp_dir}/ssh.log"
    mock="${tmp_dir}/mock-ssh"
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\nexit 0\n' "${log}" > "${mock}"
    chmod +x "${mock}"
    export SSH_MOCK="${mock}"
    export SSH_MOCK_LOG="${log}"
    ssh::run -- '-oProxyCommand=evil' host id >/dev/null 2>&1 || true
    testframework::assert_command "grep -q -- '-- -oProxyCommand=evil host id' '${log}'" "ssh::run passes -- to ssh for dash host after --"
    unset SSH_MOCK SSH_MOCK_LOG

    rm -rf "${tmp_dir}"
}

test_ssh_multiplex() {
    local tmp_dir mock log sockdir
    tmp_dir="$(mktemp -d)"
    sockdir="${tmp_dir}/socks"
    log="${tmp_dir}/ssh.log"
    mock="${tmp_dir}/mock-ssh"
    cat > "${mock}" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${log}"
exit 0
EOF
    chmod +x "${mock}"
    export SSH_MOCK="${mock}"
    export SSH_MOCK_LOG="${log}"
    export BS_SSH_SOCKET_DIR="${sockdir}"

    ssh::multiplex root@build01
    testframework::assert_command "grep -q -- '-M' '${log}'" "ssh::multiplex opens master (-M)"
    testframework::assert_command "grep -q 'ControlMaster=yes' '${log}'" "ssh::multiplex sets ControlMaster"
    testframework::assert_command "test -d '${sockdir}'" "ssh::multiplex creates socket dir"

    # Настоящий сокет на пути: -O exit отправляется / Real socket: -O exit is sent
    python3 - "${sockdir}/root@build01.sock" <<'PYEOF'
import socket, sys
s = socket.socket(socket.AF_UNIX)
s.bind(sys.argv[1])
PYEOF

    ssh::multiplex_close root@build01
    testframework::assert_command "grep -q -- '-O exit' '${log}'" "ssh::multiplex_close sends exit"

    # Регрессия: обычный файл на пути сокета — rc 0, ssh не вызывается.
    # Прямой вызов без '||' доказывает: set -e вызывающего не срабатывает.
    # Regression: a regular file at the socket path — rc 0, ssh not invoked.
    # A bare call (no '||') proves a set -e caller is not killed.
    printf 'leftover\n' > "${sockdir}/leftover.sock"
    local before after
    before="$(grep -c -- '-O exit' "${log}" || true)"
    ssh::multiplex_close leftover
    after="$(grep -c -- '-O exit' "${log}" || true)"
    testframework::assert_equal "${before}" "${after}" "multiplex_close does not invoke ssh for a regular file"

    unset SSH_MOCK SSH_MOCK_LOG BS_SSH_SOCKET_DIR
    rm -rf "${tmp_dir}"
}

test_ssh_check() {
    local tmp_dir mock log
    tmp_dir="$(mktemp -d)"
    log="${tmp_dir}/ssh.log"
    mock="${tmp_dir}/mock-ssh"
    cat > "${mock}" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${log}"
last="\${@: -1}"
case "\${last}" in
  *bs-check-ok*) printf 'bs-check-ok\n' ;;
  *uname*)       printf 'Linux x86_64 6.12.0\n' ;;
  *df*)          printf '/dev/root 100G 50G 50G 50%% /\n' ;;
  *sudo*)        printf 'sudo-ok\n' ;;
  *)             printf 'ok\n' ;;
esac
exit 0
EOF
    chmod +x "${mock}"
    export SSH_MOCK="${mock}"
    export SSH_MOCK_LOG="${log}"

    local out=""
    out="$(ssh::check --user root -- db01 2>/dev/null)" || true

    testframework::assert_command "printf '%s' '${out}' | grep -q '\[OK\] os: Linux x86_64'" "ssh::check probes OS"
    testframework::assert_command "printf '%s' '${out}' | grep -q '\[OK\] disk /: 50% used'" "ssh::check parses disk"
    testframework::assert_command "printf '%s' '${out}' | grep -q '\[OK\] sudo: passwordless'" "ssh::check detects sudo"
    testframework::assert_command "printf '%s' '${out}' | grep -q 'db01: healthy'" "ssh::check reports healthy"

    # Сломанная связь → unhealthy / Broken connectivity → unhealthy
    cat > "${mock}" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${log}"
exit 255
EOF
    chmod +x "${mock}"
    testframework::assert_false "ssh::check -- host db02" "ssh::check fails on dead host"

    unset SSH_MOCK SSH_MOCK_LOG
    rm -rf "${tmp_dir}"
}

main() {
    print_header "SSH Unit Tests / Модульные тесты SSH"

    testframework::init

    testframework::section "ssh::run / Выполнение"
    test_ssh_run

    testframework::section "push/pull / Передача"
    test_ssh_transfer

    testframework::section "Security / Безопасность"
    test_ssh_security

    testframework::section "multiplex / Соединения"
    test_ssh_multiplex

    testframework::section "ssh::check / Проверки"
    test_ssh_check

    # Регрессия: unset дефолтной переменной не должен ломать ssh::run
    # (модульный дефолт : ${VAR:=...} срабатывает только при загрузке)
    testframework::section "Regression / Регрессия"
    unset BS_SSH_SOCKET_DIR
    local tmp_dir mock log
    tmp_dir="$(mktemp -d)"
    log="${tmp_dir}/ssh.log"
    mock="${tmp_dir}/mock-ssh"
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\nexit 0\n' "${log}" > "${mock}"
    chmod +x "${mock}"
    export SSH_MOCK="${mock}"
    local rc=0
    ssh::run -- host "echo ok" >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "0" "${rc}" "ssh::run works after BS_SSH_SOCKET_DIR was unset"
    unset SSH_MOCK
    rm -rf "${tmp_dir}"

    testframework::summary
}

main "$@"