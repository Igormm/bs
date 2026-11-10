#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testtextcleanunit.sh — unit tests for lib/data/textclean and `bs clean`
# tests/unit/testtextcleanunit.sh — юнит-тесты lib/data/textclean и `bs clean`

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

load "lib/tui/clean"

# @private Run exactly one rule over $1 and print the result
# @private Прогнать ровно одно правило над $1 и вывести результат
only() {
    local -r rule="$1" text="$2"
    textclean::only "${rule}"
    textclean::string "${text}"
}

main() {
    print_header "Textclean Unit Tests / Юнит-тесты textclean"
    testframework::init

    # Изолировать от настроек пользователя / isolate from the user's config
    TEXTCLEAN_CONFIG_DIR="$(mktemp -d)"
    local -r cfg="${TEXTCLEAN_CONFIG_DIR}"

    testframework::section "registry / реестр"
    textclean::reset
    testframework::assert_equal "13" "$(textclean::rules | wc -l | tr -d ' ')" "13 rules"
    testframework::assert_equal "ansi,entities,invisible,typography,noise,trailing,blank,danger" \
        "$(textclean::enabled)" "default set"
    textclean::disable typography
    testframework::assert_false 'textclean::is_enabled typography' "disable"
    textclean::toggle typography
    testframework::assert_command 'textclean::is_enabled typography' "toggle back on"
    local rc=0
    textclean::enable bogus || rc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_INPUT}" "${rc}" "unknown rule refused"
    textclean::only "trailing, blank"
    testframework::assert_equal "trailing,blank" "$(textclean::enabled)" "only: comma and space"
    textclean::set_all 0
    testframework::assert_equal "" "$(textclean::enabled)" "set_all 0"
    testframework::assert_equal "trailing spaces at line ends" "$(textclean::describe trailing)" "describe en"
    testframework::assert_equal "пробелы в конце строк" "$(textclean::describe trailing ru)" "describe ru"

    testframework::section "ansi / ANSI и управляющие"
    testframework::assert_equal "red text" "$(only ansi $'\e[1;31mred\e[0m text')" "CSI colours"
    testframework::assert_equal "x" "$(only ansi $'\e]0;title\ax')" "OSC with BEL"
    testframework::assert_equal "x" "$(only ansi $'\e]8;;http://a\e\\x')" "OSC with ST"
    testframework::assert_equal $'a\nb' "$(only ansi $'a\r\nb')" "CRLF to LF"
    testframework::assert_equal "100%" "$(only ansi $'10%\r100%')" "CR keeps the last overwrite"
    testframework::assert_equal "bold" "$(only ansi $'b\bbo\bold')" "backspace overstrike"
    testframework::assert_equal "ab" "$(only ansi $'a\x07\x01b')" "control chars"
    testframework::assert_equal $'a\tb' "$(only ansi $'a\tb')" "tab kept"

    testframework::section "tags / HTML-теги"
    testframework::assert_equal $'Hello world\nnext' "$(only tags '<p>Hello <b>world</b></p>next')" "tags and </p>"
    testframework::assert_equal $'a\nb' "$(only tags 'a<br/>b')" "<br/>"
    testframework::assert_equal "ab" "$(only tags 'a<!-- note -->b')" "comment"
    testframework::assert_equal "- one" "$(only tags '<li>one')" "<li> to dash"
    testframework::assert_equal "a < b > c" "$(only tags 'a < b > c')" "comparison stays"

    testframework::section "entities / HTML-сущности"
    testframework::assert_equal "&lt; <" "$(only entities '&amp;lt; &lt;')" "one pass, no double decode"
    testframework::assert_equal $'\xe2\x80\x94\xe2\x80\x94' "$(only entities '&#8212;&#x2014;')" "decimal and hex"
    testframework::assert_equal $'\xc2\xa0' "$(only entities '&nbsp;')" "nbsp is NBSP"
    testframework::assert_equal "&bogus; &#0;" "$(only entities '&bogus; &#0;')" "unknown and invalid stay"
    testframework::assert_equal "it's \"q\"" "$(only entities 'it&#39;s &quot;q&quot;')" "quotes"

    testframework::section "invisible / невидимые"
    testframework::assert_equal "ab" "$(only invisible $'a\xe2\x80\x8bb')" "zero-width space"
    testframework::assert_equal "ab" "$(only invisible $'\xef\xbb\xbfa\xc2\xadb')" "BOM and soft hyphen"
    testframework::assert_equal "a b c" "$(only invisible $'a\xc2\xa0b\xe2\x80\xafc')" "NBSP and NNBSP"
    testframework::assert_equal "admin" "$(only invisible $'ad\xe2\x80\xaem\xe2\x81\xa6in')" "bidi controls"

    testframework::section "markdown"
    testframework::assert_equal "my_var *x*" "$(only markdown 'my\_var \*x\*')" "escapes"
    testframework::assert_equal 'a\b' "$(only markdown 'a\\b')" "escaped backslash"
    testframework::assert_equal $'ls -la\npwd' "$(only markdown $'```bash\nls -la\n```\npwd')" "fences removed"
    testframework::assert_equal 'C:\path' "$(only markdown 'C:\path')" "plain backslash stays"

    testframework::section "typography / типографика"
    testframework::assert_equal "\"q\" 's'" "$(only typography $'\xe2\x80\x9cq\xe2\x80\x9d \xe2\x80\x98s\xe2\x80\x99')" "quotes"
    testframework::assert_equal "a-b-c --x" "$(only typography $'a\xe2\x80\x94b\xe2\x80\x93c \xe2\x88\x92\xe2\x80\x94x')" "dashes and minus"
    testframework::assert_equal "wait... - item" "$(only typography $'wait\xe2\x80\xa6 \xe2\x80\xa2 item')" "ellipsis and bullet"
    testframework::assert_equal $'\xc2\xabru\xc2\xbb' "$(only typography $'\xc2\xabru\xc2\xbb')" "guillemets kept by default"
    TEXTCLEAN_GUILLEMETS=1
    testframework::assert_equal '"ru"' "$(only typography $'\xc2\xabru\xc2\xbb')" "guillemets on request"
    TEXTCLEAN_GUILLEMETS=0

    testframework::section "tabs / табуляция"
    testframework::assert_equal "    x" "$(only tabs $'\tx')" "leading tab"
    testframework::assert_equal "ab  c" "$(only tabs $'ab\tc')" "tab to the next stop"
    TEXTCLEAN_TAB_WIDTH=8
    testframework::assert_equal "ab      c" "$(only tabs $'ab\tc')" "width 8"
    TEXTCLEAN_TAB_WIDTH=4

    testframework::section "noise / шум интерфейса"
    testframework::assert_equal $'ls\npwd' "$(only noise $'Copy\nls\n  Copy code  \npwd')" "Copy lines"
    testframework::assert_equal "ls" "$(only noise $'bash\nCopy code\nls')" "language label before Copy"
    testframework::assert_equal $'bash\nls' "$(only noise $'bash\nls')" "label alone stays"
    testframework::assert_equal "Copy the file" "$(only noise 'Copy the file')" "prose with Copy stays"
    testframework::assert_equal "x" "$(only noise $'Скопировать\nx\nПоказать ещё')" "Russian"
    printf '# mine\nAd: .*\n' > "${cfg}/noise"
    textclean::config::load
    testframework::assert_equal "x" "$(only noise $'Ad: buy\nx')" "pattern from the config file"

    testframework::section "trailing, dedent, blank"
    testframework::assert_equal $'a\nb' "$(only trailing $'a  \nb\t')" "trailing"
    testframework::assert_equal $'a\n  b\n\nc' "$(only dedent $'    a\n      b\n  \n    c')" "dedent"
    testframework::assert_equal $'a\n b' "$(only dedent $'a\n b')" "nothing common"
    testframework::assert_equal $'a\n\nb' "$(only blank $'\n\na\n  \n\n\nb\n\n')" "collapse and trim"

    testframework::section "unwrap / склейка абзацев"
    local long="This is a long line of prose that wraps around in the window"
    testframework::assert_equal "${long} and goes on." "$(only unwrap "${long}"$'\nand goes on.')" "prose joined"
    testframework::assert_equal $'sudo apt update\nsudo apt install x' \
        "$(only unwrap $'sudo apt update\nsudo apt install x')" "short command lines stay"
    testframework::assert_equal $'- '"${long}"$' more\n- two' \
        "$(only unwrap $'- '"${long}"$'\n  more\n- two')" "list item continuation"
    testframework::assert_equal $'```\n'"${long}"$'\nx\n```' \
        "$(only unwrap $'```\n'"${long}"$'\nx\n```')" "fenced code stays"
    testframework::assert_equal "${long}"$'\n\nnext' "$(only unwrap "${long}"$'\n\nnext')" "paragraph break stays"

    testframework::section "danger / опасные команды"
    __scan() { TEXTCLEAN_TEXT="$1"; textclean::danger::scan || true; local IFS=,; local -a r=(); local f; for f in "${TEXTCLEAN_DANGER[@]}"; do f="${f#*$'\t'}"; r+=("${f%%$'\t'*}"); done; printf '%s' "${r[*]}"; }
    testframework::assert_equal "sudo,recursive rm" "$(__scan 'sudo rm -rf /')" "sudo rm -rf"
    testframework::assert_equal "download piped to a shell" "$(__scan 'curl -fsSL https://x.sh | bash')" "curl | bash"
    testframework::assert_equal "fork bomb" "$(__scan ':(){ :|:& };:')" "fork bomb"
    testframework::assert_equal "dd to a device" "$(__scan 'dd if=x.iso of=/dev/sdb')" "dd"
    testframework::assert_equal "hidden Unicode characters" "$(__scan $'ls\xe2\x80\xae')" "bidi"
    testframework::assert_equal "" "$(__scan $'ls -la\necho pseudo sudoku\nrm file.txt')" "harmless lines"
    textclean::reset
    TEXTCLEAN_TEXT='sudo ls'
    textclean::process
    testframework::assert_equal "sudo ls" "${TEXTCLEAN_TEXT}" "danger never changes text"
    testframework::assert_equal "1" "${#TEXTCLEAN_DANGER[@]}" "process fills findings"

    testframework::section "pipeline / конвейер"
    textclean::reset
    local raw=$'\e[32m\xe2\x80\x9cHello\xe2\x80\x9d\e[0m &amp; world   \n\n\n\nbash\nCopy code\nls\xc2\xa0-la\n'
    testframework::assert_equal $'"Hello" & world\n\nls -la' "$(printf '%s' "${raw}" | textclean::filter)" "defaults together"
    testframework::assert_equal "" "$(textclean::filter </dev/null)" "empty input"

    testframework::section "config / настройки"
    printf 'unwrap=on\ntypography = off # c\n' > "${cfg}/rules"
    textclean::reset
    textclean::config::load
    testframework::assert_command 'textclean::is_enabled unwrap' "rules file: on"
    testframework::assert_false 'textclean::is_enabled typography' "rules file: off"
    textclean::reset
    textclean::config::save
    testframework::assert_command 'grep -qx "dedent=off" "${cfg}/rules"' "save writes states"

    testframework::section "osc52 / буфер обмена"
    local saved_tmux="${TMUX:-}" saved_term="${TERM:-}"
    TMUX="" TERM=xterm textclean::osc52 'hi'
    testframework::assert_equal $'\e]52;c;aGk=\a' "${REPLY}" "plain"
    TMUX=/tmp/x TERM=xterm textclean::osc52 'hi'
    testframework::assert_equal $'\ePtmux;\e\e]52;c;aGk=\a\e\\' "${REPLY}" "tmux passthrough"
    TMUX="${saved_tmux}" TERM="${saved_term}"
    textclean::copy 'hi' "${cfg}/tty"
    testframework::assert_equal $'\e]52;c;aGk=\a' "$(cat "${cfg}/tty")" "copy writes to the tty path"

    testframework::section "cli / bs clean"
    rm -f "${cfg}/rules" "${cfg}/noise"
    local out
    out="$(printf 'a  \n\n\nb\n' | textclean::cli::main 2>&1)"
    testframework::assert_equal $'a\n\nb' "${out}" "filter from stdin"
    out="$(printf 'a\tb  \n' | textclean::cli::main --rules tabs 2>&1)"
    testframework::assert_equal "a   b  " "${out}" "--rules"
    out="$(printf '\xe2\x80\x9cq\xe2\x80\x9d\n' | textclean::cli::main --no-typography 2>&1)"
    testframework::assert_equal $'\xe2\x80\x9cq\xe2\x80\x9d' "${out}" "--no-RULE"
    out="$(printf 'sudo ls\n' | textclean::cli::main 2>&1 >/dev/null)"
    testframework::assert_equal "bs clean: warning: line 1: sudo: sudo ls" "${out}" "warning on stderr"
    rc=0; printf 'sudo ls\n' | textclean::cli::main --strict -q >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "3" "${rc}" "--strict exit code"
    rc=0; textclean::cli::main --bogus </dev/null >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "2" "${rc}" "unknown option"
    printf 'x  \n' > "${cfg}/in.txt"
    testframework::assert_equal "x" "$(textclean::cli::main "${cfg}/in.txt")" "file argument"
    testframework::assert_command 'textclean::cli::main --list | grep "^unwrap *off"' "--list"
    testframework::assert_command 'textclean::cli::main --help | grep "Usage: bs clean"' "--help"

    rm -rf "${cfg}"
    testframework::summary
}

main "$@"
