#!/usr/bin/env bs
# shellcheck shell=bash
# examples/hello.sh — shortest useful BS script
# examples/hello.sh — самый короткий полезный скрипт BS

set -euo pipefail

load "lib/io/streams"

io::streams::print "hello from BS ${BS_VERSION}"
