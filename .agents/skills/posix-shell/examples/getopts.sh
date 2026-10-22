#!/bin/sh
# getopts.sh - POSIX argument parsing with getopts
# Usage: getopts.sh [-o output] [-v] [-n count] file
set -eu

usage() {
  cat <<EOF
Usage: $0 [-o output] [-v] [-n count] file

Arguments:
  file         Input file (required)

Options:
  -o output    Output file (default: stdout)
  -v           Verbose mode
  -n count     Number of iterations (default: 1)
  --help       Show this help
EOF
  exit 0
}

output=""
verbose=0
count=1

for arg; do
  case "$arg" in
    --help) usage ;;
  esac
done

while getopts "o:vn:" opt 2>/dev/null; do
  case "$opt" in
    o) output="$OPTARG" ;;
    v) verbose=1 ;;
    n) count="$OPTARG"
       case "$count" in
         *[!0-9]*) echo "Error: -n requires a number" >&2; exit 1 ;;
       esac ;;
    ?) echo "Error: unknown option" >&2; usage ;;
  esac
done

shift $((OPTIND - 1))

[ $# -ge 1 ] || { echo "Error: input file required" >&2; usage; }
input_file="$1"
[ -f "$input_file" ] || { echo "Error: file not found: $input_file" >&2; exit 1; }

i=0
while [ "$i" -lt "$count" ]; do
  if [ -n "$output" ]; then
    cat "$input_file" > "$output"
  else
    cat "$input_file"
  fi
  [ "$verbose" -eq 1 ] && printf '%s\n' "Verbose: processed $input_file (iteration $((i + 1)))" >&2
  i=$((i + 1))
done
