# safelib.sh - Reusable safety functions for POSIX shell scripts
# Source this file: . "$(dirname "$0")/safelib.sh"
#
# All functions use local-style scoping via subshells where possible.
# None use bash-specific features.

# die MSG [EXIT_CODE] -- print MSG to stderr and exit
die() {
  _msg="$1"
  _code="${2:-1}"
  printf '%s\n' "$_msg" >&2
  exit "$_code"
}

# warn MSG -- print MSG to stderr, continue
warn() {
  printf '%s\n' "$1" >&2
}

# mktemp_safe -- create temp file, register EXIT trap for cleanup
# Returns: path to temp file (empty on failure)
mktemp_safe() {
  _tmp=$(mktemp /tmp/safelib-XXXXXX) || return 1
  trap 'rm -f "$_tmp"' EXIT INT TERM
  printf '%s' "$_tmp"
}

# is_absolute PATH -- true if PATH starts with /
is_absolute() {
  case "$1" in
    /*) return 0 ;;
    *)  return 1 ;;
  esac
}

# contains STR SUB -- true if STR contains SUB
contains() {
  case "$1" in
    *"$2"*) return 0 ;;
    *)      return 1 ;;
  esac
}

# require_cmd CMD -- exit if CMD is not on PATH
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

# human_size BYTES -- print bytes in human-readable form
human_size() {
  _bytes=$1
  if [ "$_bytes" -ge 1048576 ]; then
    printf '%sM\n' "$((_bytes / 1048576))"
  elif [ "$_bytes" -ge 1024 ]; then
    printf '%sK\n' "$((_bytes / 1024))"
  else
    printf '%sB\n' "$_bytes"
  fi
}
