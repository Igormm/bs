#!/bin/sh
# docker_test.sh - Test shell scripts across multiple shells in Docker
# Usage:
#   docker_test.sh [-q | --quiet | --verbose] <script.sh>
#   docker_test.sh [-q | --quiet | --verbose] <dir>
#   docker_test.sh [-q | --quiet | --verbose] <dir> <entrypoint.sh>
#
# Environment:
#   DOCKER_TEST_IMAGE  - Docker image (default: alpine:3.21)
#   DOCKER_TEST_QUIET  - Set to 0 for verbose, 1 for quiet (default: 1)

set -eu

# Parse flags
quiet="${DOCKER_TEST_QUIET:-1}"
while [ $# -gt 0 ]; do
  case "$1" in
    -q|--quiet) quiet=1; shift ;;
    --verbose)  quiet=0; shift ;;
    --)  shift; break ;;
    -*) echo "Error: unknown option: $1" >&2; exit 1 ;;
    *)  break ;;
  esac
done

[ $# -ge 1 ] || { echo "Usage: $0 [-q|--quiet|--verbose] <target> [entrypoint]" >&2; exit 1; }

target="$1"
entrypoint="${2:-}"
image="${DOCKER_TEST_IMAGE:-alpine:3.21}"

abs_path() {
  cd "$1" 2>/dev/null && {
    if command -v cygpath >/dev/null 2>&1; then
      cygpath -m "$(pwd)"
    else
      pwd
    fi
  }
}

run_docker() {
  if command -v cygpath >/dev/null 2>&1; then
    MSYS2_ARG_CONV_EXCL="*" docker "$@"
  else
    docker "$@"
  fi
}

# Install command: quiet mode sends output to /dev/null, verbose shows it
install_cmd() {
  _redir="2>&1"
  [ "$quiet" -eq 1 ] && _redir=">/dev/null 2>&1"
  case "$1" in
    *alpine*)
      echo "apk add -q dash bash zsh ksh mksh yash posh busybox ${_redir}"
      ;;
    *debian*|*ubuntu*)
      echo "apt-get update -qq ${_redir} && apt-get install -y -qq dash bash zsh ksh mksh ${_redir}"
      ;;
    *fedora*)
      echo "dnf install -y -q dash bash zsh ksh mksh ${_redir}"
      ;;
    *)
      echo 'echo "WARNING: unknown image, shells may not be available" >&2'
      ;;
  esac
}

warn_missing_shells() {
  echo 'for sh in dash bash zsh ksh mksh yash posh; do'
  echo '  if ! command -v "$sh" >/dev/null 2>&1; then'
  echo '    echo "WARNING: $sh not available after install" >&2'
  echo '  fi'
  echo 'done'
}

# Ensure image is cached
docker image inspect "$image" >/dev/null 2>&1 || docker pull "$image" -q >/dev/null 2>&1

_install_cmd=$(install_cmd "$image")
_warn_cmd=$(warn_missing_shells)

# The shell test loop. In quiet mode, compact output; in verbose, detailed.
_shell_test() {
  _file="$1"
  _prefix="${2:-}"
  if [ "$quiet" -eq 1 ]; then
    echo 'n=0'
    echo 'for sh in dash bash ash zsh ksh mksh yash posh; do'
    echo '  n=$((n + 1))'
    echo '  if command -v "$sh" >/dev/null 2>&1; then'
    echo '    if "$sh" '"$_file"'; then printf "T%s: %s... PASS\\n" "$n" "$sh"'
    echo '    else printf "T%s: %s... FAIL (%s)\\n" "$n" "$sh" "$?"; fi'
    echo '  fi'
    echo 'done'
  else
    echo 'for sh in dash bash ash zsh ksh mksh yash posh; do'
    echo '  printf "'"${_prefix}"'Testing %s... " "$sh"'
    echo '  if command -v "$sh" >/dev/null 2>&1; then'
    echo '    if "$sh" '"$_file"'; then echo PASS; else echo "FAIL ($?)"; fi'
    echo '  else echo SKIP; fi'
    echo 'done'
  fi
}

if [ -n "$entrypoint" ]; then
  mount_path=$(abs_path "$target")
  shell_test=$(_shell_test "\"$entrypoint\"" "")
  run_docker run --rm -v "${mount_path}:/mnt" "$image" sh -c "
    cd /mnt
    ${_install_cmd}
    ${_warn_cmd}
    ${shell_test}
  "
elif [ -f "$target" ]; then
  file_dir=$(abs_path "$(dirname "$target")")
  file_name=$(basename "$target")
  shell_test=$(_shell_test "/mnt/${file_name}")
  run_docker run --rm -v "${file_dir}:/mnt" "$image" sh -c "
    ${_install_cmd}
    ${_warn_cmd}
    ${shell_test}
  "
else
  mount_path=$(abs_path "$target")
  if [ "$quiet" -eq 1 ]; then
    # Quiet directory mode: test each file, emit compact T-format output
    run_docker run --rm -v "${mount_path}:/mnt" "$image" sh -c "
      cd /mnt
      ${_install_cmd}
      ${_warn_cmd}
      for f in *.sh; do
        [ -f \"\$f\" ] || continue
        n=0
        for sh in dash bash ash zsh ksh mksh yash posh; do
          n=\$((n + 1))
          if command -v \"\$sh\" >/dev/null 2>&1; then
            if \"\$sh\" \"\$f\"; then printf \"T%s: %s... PASS\\\n\" \"\$n\" \"\$sh\"
            else printf \"T%s: %s... FAIL (%s)\\\n\" \"\$n\" \"\$sh\" \"\$?\"; fi
          fi
        done
      done
    "
  else
    # Verbose directory mode: show section headers
    run_docker run --rm -v "${mount_path}:/mnt" "$image" sh -c "
      cd /mnt
      ${_install_cmd}
      ${_warn_cmd}
      for f in *.sh; do
        [ -f \"\$f\" ] || continue
        echo \"=== Testing: \$f ===\"
        for sh in dash bash ash zsh ksh mksh yash posh; do
          printf '  %s... ' \"\$sh\"
          if command -v \"\$sh\" >/dev/null 2>&1; then
            if \"\$sh\" \"\$f\"; then echo PASS; else echo \"FAIL (\$?)\"; fi
          else echo SKIP; fi
        done
      done
    "
  fi
fi
