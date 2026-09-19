#!/usr/bin/env bs
# shellcheck shell=bash
# examples/pulse.sh — capability pulse of this host
# examples/pulse.sh — пульс возможностей этой машины
#
# Probe, don't guess: tier, userland, tool chain, hardware if /proc exists.
# Пробы вместо догадок: тир, userland, цепочка утилит, железо при /proc.
#
#   ./bs run examples/pulse.sh

set -euo pipefail

load "lib/io/streams"
load "lib/platform/facts"
load "lib/ui/presentation"
load "lib/rfc/uuid"
load "lib/system/hw"

pulse::fact() {
  local -r key="${1:?}"
  local value=""
  value="$(platform::get "${key}" "?")"
  printf '%s\n' "${value//:/ }"
}

pulse::on() {
  local -r bit="${1:?}"
  if [[ "${bit}" == "1" ]]; then
    printf 'yes\n'
  else
    printf 'no\n'
  fi
}

main() {
  local id sha_cmd procfs
  id="$(uuid::gen_v7)"
  sha_cmd="$(platform::probe sha256sum shasum cksum || printf none)"
  procfs="$(pulse::fact procfs)"

  presentation::header "BS pulse"
  io::streams::print "id  ${id}"
  io::streams::print ""

  local -a rows
  rows=(
    "Fact:Value"
    "tier:$(platform::tier)"
    "bash:$(pulse::fact bash)"
    "kernel:$(pulse::fact kernel)"
    "arch:$(pulse::fact arch)"
    "distro:$(pulse::fact distro)"
    "userland:$(pulse::fact userland)"
    "libc:$(pulse::fact libc)"
    "repo:$(pulse::fact repo)"
    "procfs:$(pulse::on "${procfs}")"
    "sysfs:$(pulse::on "$(pulse::fact sysfs)")"
    "grep -P:$(pulse::on "$(pulse::fact tool_grep_p)")"
    "sed -z:$(pulse::on "$(pulse::fact tool_sed_z)")"
    "sha:$(printf '%s' "${sha_cmd}")"
  )

  if [[ "${procfs}" == "1" ]]; then
    rows+=(
      "cpu:$(system::hw::cpu_model)"
      "cores:$(system::hw::cpu_cores) / $(system::hw::cpu_threads)"
      "ram MiB:$(system::hw::mem_total)"
    )
  fi

  presentation::table "${rows[@]}"
  io::streams::print ""
  io::streams::print "tier is a probe result, not uname. / тир — проба, не uname."
}

main "$@"
