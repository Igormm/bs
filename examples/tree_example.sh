#!/usr/bin/env bs
# shellcheck shell=bash
# examples/tree_example.sh — project tree from yaml/txt/ini/csv
# examples/tree_example.sh — дерево проекта из yaml/txt/ini/csv
#
#   ./bs run examples/tree_example.sh

set -euo pipefail

load "lib/io/tree"
load "lib/io/streams"

main() {
  local dest
  dest="$(mktemp -d)"
  io::streams::print "dest: ${dest}"

  io::tree::parse_text "$(cat <<'YAML'
src:
  hello.sh: "#!/usr/bin/env bs"
  lib/:
docs:
  README.md: |
    # demo
    created by io::tree
empty/:
YAML
)" yaml

  io::tree::apply "${dest}"
  io::streams::print "created:"
  io::tree::dump
  io::streams::print ""
  io::streams::print "try: find ${dest} | sort"
}

main "$@"
