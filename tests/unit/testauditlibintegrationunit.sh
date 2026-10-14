#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testauditlibintegrationunit.sh — regressions from the lib audit (agent C)
# tests/unit/testauditlibintegrationunit.sh — регрессии аудита lib (агент C)
#
# Everything runs in a temp dir with fake curl/wg; no network, no real configs.
# Всё выполняется во временном каталоге с подставными curl/wg; без сети и боевых конфигов.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

TEST_TMP="$(mktemp -d)"
trap 'rm -rf "${TEST_TMP:?}"' EXIT
export BS_WIREGUARD_CONFIG_DIR="${TEST_TMP}/etc"
export BS_WIREGUARD_BACKUP_DIR="${TEST_TMP}/backup"
mkdir -p "${TEST_TMP}/etc" "${TEST_TMP}/bin"

# Fake curl: records argv and stdin, answers with a canned body.
# Подставной curl: пишет argv и stdin, отвечает готовым телом.
cat > "${TEST_TMP}/bin/curl" <<'FAKE'
#!/bin/sh
printf '%s\n' "$@" > "${FAKE_CURL_DIR}/argv"
cat > "${FAKE_CURL_DIR}/stdin" 2>/dev/null || true
case "$*" in
  *http_code*) printf '{"response":1}\n200' ;;
  *) printf '{"choices":[{"message":{"content":"ok"}}]}' ;;
esac
FAKE
chmod +x "${TEST_TMP}/bin/curl"
export FAKE_CURL_DIR="${TEST_TMP}"
export PATH="${TEST_TMP}/bin:${PATH}"

load "lib/integration/wireguard"
load "lib/integration/llm"
load "lib/integration/vkapi"
load "lib/integration/osagent"
load "lib/api/openapi"
load "lib/integration/vkmusic"
load "lib/integration/k8s"
load "lib/integration/result"
load "lib/network/sshnetwork"
load "lib/io/process"

test_remove_peer_keeps_other_headers() {
  printf '[Interface]\nPrivateKey = X\n\n[Peer]\n# a\nPublicKey = AAA=\nAllowedIPs = 10.0.0.2/32\n\n[Peer]\n# b\nPublicKey = BBB=\nAllowedIPs = 10.0.0.3/32\n' > "${TEST_TMP}/etc/wg0.conf"
  wireguard::remove_peer wg0 AAA= >/dev/null 2>&1
  local conf
  conf="$(cat "${TEST_TMP}/etc/wg0.conf")"
  testframework::assert_command "[[ \"\$(grep -c '^\[Peer\]' '${TEST_TMP}/etc/wg0.conf')\" == 1 ]]" "surviving peer keeps its [Peer] header"
  testframework::assert_command "! grep -q AAA= '${TEST_TMP}/etc/wg0.conf'" "removed peer is gone"
  testframework::assert_command "grep -q BBB= '${TEST_TMP}/etc/wg0.conf'" "other peer is kept"
  testframework::assert_command "awk '/^\[Interface\]/{i=1;next} /^\[/{i=0} i&&/PublicKey/{bad=1} END{exit bad}' '${TEST_TMP}/etc/wg0.conf'" "no PublicKey leaked into [Interface]"
  : "${conf}"
}

test_remove_peer_unknown_key() {
  printf '[Interface]\nPrivateKey = X\n\n[Peer]\nPublicKey = BBB=\nAllowedIPs = 10.0.0.3/32\n' > "${TEST_TMP}/etc/wg1.conf"
  local before after rc=0
  before="$(sha256sum < "${TEST_TMP}/etc/wg1.conf")"
  rm -rf "${TEST_TMP:?}/backup"
  wireguard::remove_peer wg1 NOPE= >/dev/null 2>&1 || rc=$?
  after="$(sha256sum < "${TEST_TMP}/etc/wg1.conf")"
  testframework::assert_equal "1" "${rc}" "remove_peer returns 1 for an unknown key"
  testframework::assert_equal "${before}" "${after}" "config untouched for an unknown key"
  testframework::assert_false "ls '${TEST_TMP}/backup'/*wg1* >/dev/null 2>&1" "no backup made when nothing is removed"
}

test_peer_backups_unique_and_private() {
  printf '[Interface]\nPrivateKey = X\n\n[Peer]\nPublicKey = CCC=\nAllowedIPs = 10.0.0.4/32\n' > "${TEST_TMP}/etc/wg2.conf"
  rm -rf "${TEST_TMP:?}/backup"
  wireguard::add_peer wg2 DDD= 10.0.0.5/32 >/dev/null 2>&1 || true
  wireguard::add_peer wg2 EEE= 10.0.0.6/32 >/dev/null 2>&1 || true
  local n
  n="$(find "${TEST_TMP}/backup" -name 'wg2_*' | wc -l)"
  testframework::assert_equal "2" "${n}" "two edits in the same second keep two backups in the backup dir"
  testframework::assert_command "[[ -z \"\$(find '${TEST_TMP}/backup' -name 'wg2_*' ! -perm 600)\" ]]" "backups are mode 600"
  testframework::assert_false "ls '${TEST_TMP}/etc'/wg2.conf.backup.* >/dev/null 2>&1" "no stray backups next to the config"
}

# vkapi::api_call stub: records calls, answers an upload server
# Заглушка vkapi::api_call: пишет вызовы, отдаёт сервер загрузки
vkapi::api_call() {
  printf '%s %s\n' "$1" "${2:-}" >> "${TEST_TMP}/calls"
  case "$1" in
    audio.getUploadServer) printf '{"upload_url":"https://up.test/u"}' ;;
    *) printf '{}' ;;
  esac
}

# Fake curl variant for vkmusic: FAKE_CURL_MODE=garbage|good
test_vkmusic_upload_validates_response() {
  printf x > "${TEST_TMP}/a.mp3"
  : > "${TEST_TMP}/calls"
  cat > "${TEST_TMP}/bin/curl" <<'FAKE'
#!/bin/sh
out=""; while [ $# -gt 0 ]; do [ "$1" = "-o" ] && out="$2"; shift; done
[ -n "$out" ] && printf 'MP3' > "$out"
if [ "$FAKE_CURL_MODE" = good ]; then printf '{"server":"7","audio":"A B","hash":"h"}'; else printf '<html>502</html>'; fi
FAKE
  local rc=0
  ( export FAKE_CURL_MODE=garbage; vkmusic::upload_audio "${TEST_TMP}/a.mp3" t a >/dev/null 2>&1 ) || rc=$?
  testframework::assert_false "[[ ${rc} -eq 0 ]]" "upload with a garbage server reply fails"
  testframework::assert_false "grep -q audio.save '${TEST_TMP}/calls'" "audio.save is not called with empty fields"
  ( export FAKE_CURL_MODE=good; vkmusic::upload_audio "${TEST_TMP}/a.mp3" "Tom & Jerry" "Кино" >/dev/null 2>&1 ) || true
  testframework::assert_command "grep -q 'audio.save server=7&audio=A%20B&hash=h&title=Tom%20%26%20Jerry&artist=%D0' '${TEST_TMP}/calls'" "title/artist/fields are URL-encoded"
}

test_vkmusic_download_names() {
  local info='{"artist":"Кино","title":"Группа крови","url":"https://x.test/a.mp3","duration":1,"owner_id":1,"id":2}'
  local out="${TEST_TMP}/dl"
  mkdir -p "${out}"
  FAKE_CURL_MODE=good vkmusic::download "${info}" "${out}" >/dev/null 2>&1 || true
  testframework::assert_command "ls '${out}' | grep -q 'Кино'" "non-ASCII artist survives in the file name"
  FAKE_CURL_MODE=good vkmusic::download "${info}" "${out}" >/dev/null 2>&1 || true
  testframework::assert_equal "2" "$(find "${out}" -type f | wc -l)" "second download does not overwrite the first"
  FAKE_CURL_MODE=good vkmusic::download "${info}" "${out}" "../escaped.mp3" >/dev/null 2>&1 || true
  testframework::assert_false "test -e '${TEST_TMP}/escaped.mp3'" "explicit name cannot leave output_dir"
}

test_k8s_namespace_current_default() {
  cat > "${TEST_TMP}/bin/kubectl" <<'FAKE'
#!/bin/sh
case "$FAKE_KUBECTL_NS" in
  none) exit 0 ;;
  fail) exit 1 ;;
  *) printf '%s' "$FAKE_KUBECTL_NS" ;;
esac
FAKE
  chmod +x "${TEST_TMP}/bin/kubectl"
  local ns
  ns="$(FAKE_KUBECTL_NS=none k8s::namespace::current)"
  testframework::assert_equal "default" "${ns}" "empty kubectl namespace means K8S_NAMESPACE (default)"
  ns="$(FAKE_KUBECTL_NS=prod k8s::namespace::current)"
  testframework::assert_equal "prod" "${ns}" "namespace from kubectl is used"
  ns="$(FAKE_KUBECTL_NS=fail k8s::namespace::current)"
  testframework::assert_equal "default" "${ns}" "kubectl failure falls back to K8S_NAMESPACE"
  ns="$(FRAMEWORK_DRY_RUN=true k8s::namespace::current)"
  testframework::assert_equal "default" "${ns}" "dry-run prints only the namespace"
}

test_result_json_edges() {
  testframework::assert_equal '\u001b[31mx\u001b[0m' "$(__integration_result::json_escape $'\033[31mx\033[0m')" "no-jq escape handles control characters"
  testframework::assert_equal 'a\nb	' "$(__integration_result::json_escape $'a\nb\t' | sed 's/\\t/	/')" "no-jq escape still handles newline and tab"
  local out rc=0
  out="$(result::run -- printf '%s' $'a\nb')"
  testframework::assert_equal '["printf","%s","a\nb"]' "$(printf '%s' "${out}" | jq -c .args)" "an argument with a newline stays one array item"
  out="$(result::error 0 "boom")" || rc=$?
  testframework::assert_command "[[ ${rc} -ne 0 ]]" "result::error 0 does not return success"
  testframework::assert_command "printf '%s' '${out}' | jq -e '.success == false and .exit_code != 0'" "result::error 0 reports a non-zero exit_code"
}

# Run code in a fresh `set -euo pipefail` shell (set -e is NOT inherited into `||`/`$()` contexts of this shell)
# Выполнить код в новой оболочке `set -euo pipefail` (set -e не работает внутри `||`/`$()` этой оболочки)
audit::strict_child() {
  local script="${TEST_TMP}/child.sh"
  {
    printf 'set -euo pipefail\nexport BS_SILENT=1 BS_HOME=%q\n' "${BS_PROJECT_ROOT}"
    printf 'source %q/bootstrap/init.sh\n' "${BS_PROJECT_ROOT}"
    printf '%s\n' "$1"
  } > "${script}"
  env -i HOME="${TEST_TMP}" PATH="${PATH}" "${TEST_BASH}" "${script}" 2>&1 || true
}

test_ps1status_monitoring_idempotent() {
  # HOME is the temp dir in the child shell: the PID file never touches the real ~/.config
  # HOME — временный каталог в дочерней оболочке: PID-файл не попадает в настоящий ~/.config
  local out
  out="$(audit::strict_child 'load "lib/status/ps1status"
mkdir -p "${PS1_STATUS_CONFIG_DIR}"
PS1_STATUS_ENABLED_COMPONENTS=()
ps1status::start_monitoring >/dev/null
ps1status::start_monitoring >/dev/null
echo "LOOPS:$(jobs -p | wc -l)"
ps1status::stop_monitoring >/dev/null
sleep 0.2
echo "AFTERSTOP:$(jobs -r | wc -l)"
printf "abc" > "${PS1_STATUS_CONFIG_DIR}/monitor.pid"
ps1status::stop_monitoring >/dev/null 2>&1
echo "BADPID:$([[ -e ${PS1_STATUS_CONFIG_DIR}/monitor.pid ]] && echo kept || echo removed)"
')"
  testframework::assert_command "printf '%s' '${out}' | grep -q '^LOOPS:1$'" "start_monitoring twice starts one loop"
  testframework::assert_command "printf '%s' '${out}' | grep -q '^AFTERSTOP:0$'" "stop_monitoring leaves no loop behind"
  testframework::assert_command "printf '%s' '${out}' | grep -q '^BADPID:removed$'" "a garbage PID file is dropped, not passed to kill"
}

test_dataprocessor_stream_process() {
  local out
  out="$(audit::strict_child 'load "lib/data/dataprocessor"
d="$(mktemp -d)"; : > "${d}/empty"; printf "1\n2\n3\n4\n5\n" > "${d}/five"
ok() { echo "CHUNK:$(wc -l < "$1")" >> "${d}/log"; }
bad() { return 7; }
dataprocessor::stream::process "${d}/empty" ok 2; echo "EMPTY:rc=$?:calls=$(wc -l < "${d}/log" 2>/dev/null || echo 0)"
dataprocessor::stream::process "${d}/five" ok 2; echo "FIVE:rc=$? $(tr "\n" " " < "${d}/log")"
rc=0; dataprocessor::stream::process "${d}/five" bad 2 || rc=$?; echo "BAD:rc=${rc}"
rc=0; dataprocessor::stream::process "${d}/five" ok x 2>/dev/null || rc=$?; echo "SIZE:rc=${rc}"
echo "LEFT:$(ls /tmp/tmp.*.chunk.* 2>/dev/null | wc -l)"
rm -rf "${d:?}"
')"
  testframework::assert_command "printf '%s' '${out}' | grep -q '^EMPTY:rc=0:calls=0$'" "empty file: processor is never called with a literal glob"
  testframework::assert_command "printf '%s' '${out}' | grep -q '^FIVE:rc=0 CHUNK:2 CHUNK:2 CHUNK:1 $'" "chunks are split by lines"
  testframework::assert_command "printf '%s' '${out}' | grep -q '^BAD:rc=7$'" "a failing processor makes stream::process fail"
  testframework::assert_command "printf '%s' '${out}' | grep -q '^SIZE:rc=[1-9]'" "non-numeric chunk size is rejected"
}

test_mbfl_dir_remove_guard() {
  local out
  out="$(audit::strict_child 'load "lib/frameworks/frameworksintegration"
rc=0; frameworks::mbfl::dir::remove "" 2>/dev/null || rc=$?; echo "EMPTY:${rc}"
rc=0; frameworks::mbfl::dir::remove "/" 2>/dev/null || rc=$?; echo "ROOT:${rc}"
d="$(mktemp -d)"; mkdir -p "${d}/x"; frameworks::mbfl::dir::remove "${d}"; echo "DIR:$([[ -e ${d} ]] && echo still || echo gone)"')"
  testframework::assert_command "printf '%s' '${out}' | grep -q '^EMPTY:[1-9]'" "dir::remove refuses an empty path"
  testframework::assert_command "printf '%s' '${out}' | grep -q '^ROOT:[1-9]'" "dir::remove refuses /"
  testframework::assert_command "printf '%s' '${out}' | grep -q '^DIR:gone$'" "dir::remove still removes a real directory"
}

test_tui_init_keeps_exit_trap() {
  local out
  out="$(audit::strict_child 'load "lib/tui/tui"
trap "echo USER_EXIT_TRAP_RAN" EXIT
tui::init >/dev/null
tui::init >/dev/null
exit 0')"
  testframework::assert_command "printf '%s' '${out}' | grep -q USER_EXIT_TRAP_RAN" "tui::init keeps the caller's EXIT trap"
}

test_ssh_test_connection_no_injection() {
  local rc=0
  sshnetwork::test_connection "x/1; touch ${TEST_TMP}/PWNED; #" 22 >/dev/null 2>&1 || rc=$?
  testframework::assert_false "test -e '${TEST_TMP}/PWNED'" "host string is not executed as code"
  testframework::assert_command "[[ ${rc} -ne 0 ]]" "a malformed host is reported as a failed connection"
  rc=0
  sshnetwork::test_connection 127.0.0.1 "22;touch ${TEST_TMP}/PWNED2" >/dev/null 2>&1 || rc=$?
  testframework::assert_false "test -e '${TEST_TMP}/PWNED2'" "port string is not executed as code"
}

test_ssh_close_tunnel_exact_port() {
  local a b
  ( exec -a "ssh -L 59187:h:80" sleep 60 ) & a=$!
  ( exec -a "ssh -L 127.0.0.1:59188:h:80" sleep 60 ) & b=$!
  sleep 0.3
  sshnetwork::close_tunnel 187 >/dev/null 2>&1 || true
  testframework::assert_command "kill -0 ${a} && kill -0 ${b}" "close_tunnel 187 does not kill tunnels on 59187/59188 (substring)"
  sshnetwork::close_tunnel 59187 >/dev/null 2>&1 || true
  sshnetwork::close_tunnel 59188 >/dev/null 2>&1 || true
  sleep 0.3
  testframework::assert_command "! kill -0 ${a} 2>/dev/null" "close_tunnel 59187 kills that tunnel"
  testframework::assert_command "! kill -0 ${b} 2>/dev/null" "close_tunnel 59188 handles an explicit bind address"
  utils::ignore kill "${a}" "${b}"
  wait 2>/dev/null || true
}

test_ssh_execute_remote_under_set_e() {
  printf '#!/bin/sh\necho "denied" >&2\nexit 255\n' > "${TEST_TMP}/bin/ssh"
  chmod +x "${TEST_TMP}/bin/ssh"
  local out
  out="$(audit::strict_child 'load "lib/network/sshnetwork"; sshnetwork::execute_remote 10.0.0.1 uptime bob 22')"
  testframework::assert_command "printf '%s' '${out}' | grep -q 'Command failed on 10.0.0.1'" "execute_remote logs the failure under set -e"
}

test_ssh_monitor_interval() {
  printf '#!/bin/sh\nexit 0\n' > "${TEST_TMP}/bin/ping"
  chmod +x "${TEST_TMP}/bin/ping"
  local out
  # sleep stub ends the endless loop after the first pass and reports its argument
  # Заглушка sleep прерывает бесконечный цикл после первого прохода и сообщает свой аргумент
  out="$( sleep() { printf 'SLEEP:%s\n' "$1"; exit 0; }; sshnetwork::monitor_network 10.0.0.1 2>&1 )"
  testframework::assert_command "printf '%s' '${out}' | grep -q '^SLEEP:60$'" "a host as first argument is not used as the sleep interval"
  out="$( sleep() { printf 'SLEEP:%s\n' "$1"; exit 0; }; sshnetwork::monitor_network 5 10.0.0.1 2>&1 )"
  testframework::assert_command "printf '%s' '${out}' | grep -q '^SLEEP:5$'" "a leading integer is the interval"
}

test_process_guard_under_set_e() {
  local out
  out="$(audit::strict_child 'load "lib/io/process"; io::process::guard --timeout 5 -- sh -c "echo out2; exit 4"')"
  testframework::assert_command "printf '%s' '${out}' | grep -q '^out2$'" "guard replays output of a failing command under set -e"
  testframework::assert_command "! printf '%s' '${out}' | grep -q 'ok in'" "guard does not claim ok for a failing command"
}

test_llm_key_not_in_argv() {
  export LLM_MOCK_RESPONSE=""
  unset LLM_MOCK_RESPONSE
  __llm::request openai '{"a":1}' "sk-SECRET-123" >/dev/null 2>&1 || true
  testframework::assert_command "! grep -q 'sk-SECRET-123' '${TEST_TMP}/argv'" "LLM key absent from curl argv"
  testframework::assert_command "grep -q 'sk-SECRET-123' '${TEST_TMP}/stdin'" "LLM key delivered via stdin"
}

test_vk_token_not_in_argv() {
  # shellcheck disable=SC2034
  VK_API_ACCESS_TOKEN="vk1.SECRETTOKEN"
  vkapi::api_request "users.get" "user_ids=1" false >/dev/null 2>&1 || true
  testframework::assert_command "! grep -q 'SECRETTOKEN' '${TEST_TMP}/argv'" "VK token absent from curl argv"
  testframework::assert_command "grep -q 'SECRETTOKEN' '${TEST_TMP}/stdin'" "VK token delivered via stdin"
}

test_osagent_plain_text_reply() {
  export OPENAI_API_KEY=x
  export LLM_MOCK_RESPONSE='{"choices":[{"message":{"content":"Just a plain answer"}}]}'
  local out
  out="$(osagent::ask "hi" 2>/dev/null)"
  testframework::assert_equal "Just a plain answer" "${out}" "plain-text model reply becomes the answer"
  out="$(osagent::ask "hi" --json 2>/dev/null)"
  testframework::assert_command "printf '%s' '${out}' | jq -e '.answer == \"Just a plain answer\"'" "--json output is valid JSON"
  unset LLM_MOCK_RESPONSE
}

test_api_registry_literal_names() {
  API_SPEC_REGISTRY="${TEST_TMP}/registry.tsv"
  printf 'axb\t/x/axb.json\na.b\t/x/ab.json\npets\t/x/p.json\n' > "${API_SPEC_REGISTRY}"
  API_SPECS["a.b"]="/x/ab.json"
  api::spec::drop 'a.b' >/dev/null 2>&1 || true
  testframework::assert_command "grep -q '^axb' '${API_SPEC_REGISTRY}'" "drop a.b does not remove axb (name is not a regex)"
  printf 'axb\t/x/axb.json\n' > "${API_SPEC_REGISTRY}"
  # shellcheck disable=SC2034
  API_SPECS["a["]="/x/y.json"
  api::spec::drop 'a[' >/dev/null 2>&1 || true
  testframework::assert_command "grep -q '^axb' '${API_SPEC_REGISTRY}'" "invalid-regex name does not wipe the registry"
}

main() {
  print_header "Audit lib regressions / Регрессии аудита lib"
  testframework::init
  test_remove_peer_keeps_other_headers
  test_remove_peer_unknown_key
  test_peer_backups_unique_and_private
  test_llm_key_not_in_argv
  test_vk_token_not_in_argv
  test_osagent_plain_text_reply
  test_api_registry_literal_names
  test_k8s_namespace_current_default
  test_result_json_edges
  test_ps1status_monitoring_idempotent
  test_ssh_test_connection_no_injection
  test_tui_init_keeps_exit_trap
  test_dataprocessor_stream_process
  test_mbfl_dir_remove_guard
  test_ssh_close_tunnel_exact_port
  test_ssh_execute_remote_under_set_e
  test_ssh_monitor_interval
  test_process_guard_under_set_e
  test_vkmusic_upload_validates_response
  test_vkmusic_download_names
  testframework::summary
}

main "$@"
