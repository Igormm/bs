#!/usr/bin/env bash
#
# BAD: 2>&1 before the file redirection copies the OLD stdout (the terminal), so
# stderr keeps going to the terminal while only stdout reaches the file.
# expect-shellcheck: SC2069
run_step() {
  some_command 2>&1 > output.log
}
run_step
