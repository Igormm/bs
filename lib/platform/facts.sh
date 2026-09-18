#!/usr/bin/env bs
# shellcheck shell=bash
# lib/platform/facts.sh — capability vector with cache
# lib/platform/facts.sh — вектор возможностей с кэшем

# @depends core/lang, core/utils, core/const

# Source Guard
bs::guard "LIB_PLATFORM_FACTS" || return 0

# Dependencies
bs::source_relative "../../core/lang.sh" "../../core/utils.sh" "../../core/const.sh"

# ==========================================
# Capability vector / Вектор возможностей
#
# Collects platform facts (kernel, arch, distro, family, repo, userland,
# libc, bash, /proc, /sys, tool probes) and caches them in
# ${XDG_CACHE_HOME:-$HOME/.cache}/bs/facts. The cache is rebuilt when the
# environment hash changes (uname + os-release + bash version).
# Собирает факты платформы (kernel, arch, distro, family, repo, userland,
# libc, bash, /proc, /sys, пробы инструментов) и кэширует их в
# ${XDG_CACHE_HOME:-$HOME/.cache}/bs/facts. Кэш пересобирается при
# изменении хеша окружения (uname + os-release + версия bash).
#
# Test hooks / Тестовые хуки: PLATFORM_CACHE_FILE (путь к кэшу)
# ==========================================

# Cache file / Файл кэша
: "${PLATFORM_CACHE_FILE:=${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}/bs/facts}"

declare -gA PF_FACTS=()
declare -g PF_BUILT=0

# @private
# @description Environment hash for cache invalidation.
# @description Хеш окружения для инвалидации кэша.
# @stdout hash / хеш
platform::__env_hash() {
  local sig
  sig="$(uname -s 2>/dev/null | tr '\n' '|')$(uname -m 2>/dev/null | tr '\n' '|')${BASH_VERSION}|$(cat /etc/os-release 2>/dev/null | tr '\n' '|')"
  printf '%s' "${sig}" | __platform::sha
}

# @private
# @description Content hash (GNU/BSD/cksum chain).
# @description Хеш содержимого (цепочка GNU/BSD/cksum).
# @stdin data / данные
# @stdout hash / хеш
__platform::sha() {
  if utils::has sha256sum; then
    sha256sum | awk '{print $1}'
  elif utils::has shasum; then
    shasum -a 256 | awk '{print $1}'
  else
    cksum | awk '{print $1}'
  fi
}

# @private
# @description Read a value from the cache file / Прочитать из кэша.
# @param $1 key / ключ
# @stdout value or empty / значение или пусто
__platform::cache_get() {
  local k="${1}"
  while IFS= read -r line; do
    [[ "${line}" == "${k}="* ]] && printf '%s\n' "${line#*=}"
  done < "${PLATFORM_CACHE_FILE}"
}

# @private
# @description Probe a tool / Проба инструмента.
# @param $1 command name / имя команды
# @return 0 works, 1 not
__platform::probe_tool() {
  local -r cmd="${1}"
  case "${cmd}" in
    sed_z)   printf 'a\nb' | sed -z 's/a/X/' >/dev/null 2>&1 ;;
    grep_p)  printf 'x' | grep -Pq 'x' 2>/dev/null ;;
    stat_c)  [[ "$(stat -c %s /dev/null 2>/dev/null)" == "0" ]] ;;
    date_n)  [[ "$(date +%N 2>/dev/null)" =~ ^[0-9]+$ ]] ;;
    readlink_f) readlink -f / 2>/dev/null | grep -q '^/' ;;
    *)       utils::has "${cmd}" ;;
  esac
}

# @private
# @description Build the facts map / Собрать карту фактов.
platform::__build() {
  local kernel arch distro family repo userland libc
  kernel="$(uname -s 2>/dev/null | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m 2>/dev/null)"
  PF_FACTS[kernel]="${kernel:-unknown}"
  PF_FACTS[arch]="${arch:-unknown}"
  PF_FACTS[bash]="${BASH_VERSION}"

  # distro / family из os-release
  distro="$(awk -F= '/^ID=/{print $2}' /etc/os-release 2>/dev/null | tr -d '"')"
  family="$(awk -F= '/^ID_LIKE=/{print $2}' /etc/os-release 2>/dev/null | tr -d '"' | awk '{print $1}')"
  family="${family:-${distro:-unknown}}"
  PF_FACTS[distro]="${distro:-unknown}"
  PF_FACTS[family]="${family}"

  # repo — производное от family / derived from family
  case "${family}" in
    debian)  repo="apt" ;;
    fedora|rhel) repo="dnf" ;;
    suse)    repo="zypper" ;;
    arch)    repo="pacman" ;;
    alpine)  repo="apk" ;;
    *)       case "${kernel}" in
               darwin)  repo="brew" ;;
               freebsd) repo="pkg" ;;
               *)       repo="unknown" ;;
             esac ;;
  esac
  PF_FACTS[repo]="${repo}"

  # userland / libc
  if __platform::probe_tool sed_z && __platform::probe_tool sha256sum; then
    userland="gnu"
  elif [[ "${kernel}" == "darwin" || "${kernel}" == "freebsd" ]]; then
    userland="bsd"
  elif utils::has busybox; then
    userland="busybox"
  else
    userland="unknown"
  fi
  PF_FACTS[userland]="${userland}"

  local musl_found=0
  local musl_path
  for musl_path in /lib/ld-musl-*; do
    [[ -e "${musl_path}" ]] && musl_found=1
  done
  if (( musl_found == 1 )); then
    libc="musl"
  elif ldd --version 2>&1 | head -n1 | grep -q glibc; then
    libc="glibc"
  else
    libc="unknown"
  fi
  PF_FACTS[libc]="${libc}"

  # Файловые системы / Filesystems
  PF_FACTS[procfs]="$( [[ -d /proc ]] && printf 1 || printf 0 )"
  PF_FACTS[sysfs]="$( [[ -d /sys ]] && printf 1 || printf 0 )"
  PF_FACTS[dmi]="$( [[ -d /sys/class/dmi/id ]] && printf 1 || printf 0 )"

  # Пробы инструментов / Tool probes
  PF_FACTS[tool_sha256]="$( __platform::probe_tool sha256sum && printf 1 || printf 0 )"
  PF_FACTS[tool_shasum]="$( utils::has shasum && printf 1 || printf 0 )"
  PF_FACTS[tool_grep_p]="$( __platform::probe_tool grep_p && printf 1 || printf 0 )"
  PF_FACTS[tool_sed_z]="$( __platform::probe_tool sed_z && printf 1 || printf 0 )"
  PF_FACTS[tool_stat_c]="$( __platform::probe_tool stat_c && printf 1 || printf 0 )"
  PF_FACTS[tool_date_n]="$( __platform::probe_tool date_n && printf 1 || printf 0 )"
  PF_FACTS[tool_jq]="$( utils::has jq && printf 1 || printf 0 )"
  PF_FACTS[tool_cc]="$( utils::has cc && printf 1 || printf 0 )"

  PF_FACTS[tier]="$(platform::tier_from "${kernel}" "${userland}" "${PF_FACTS[tool_sed_z]}" "${PF_FACTS[tool_sha256]}")"
  PF_BUILT=1
}

# @private
# @description Tier from kernel + userland / Тир из ядра и userland.
# @param $1 kernel, $2 userland, $3 tool_sed_z, $4 tool_sha256
# @stdout tier / тир
platform::tier_from() {
  local -r k="${1}" u="${2}" sedz="${3}" sha="${4}"
  if [[ "${k}" == "darwin" || "${k}" == "freebsd" ]]; then
    printf 'bsd\n'
  elif [[ "${u}" == "gnu" ]] || [[ "${sedz}" == "1" && "${sha}" == "1" ]]; then
    printf 'gnu-linux\n'
  else
    printf 'core\n'
  fi
}

# @private
# @description Ensure facts are loaded (cache or build).
# @description Убедиться, что факты загружены (кэш или сборка).
platform::__ensure() {
  (( PF_BUILT == 1 )) && return 0
  local cached_hash=""
  cached_hash="$(head -n1 "${PLATFORM_CACHE_FILE}" 2>/dev/null | sed 's/^# env_hash=//' || true)"
  local env_hash
  env_hash="$(platform::__env_hash)"
  if is::not_empty "${cached_hash}" && [[ "${cached_hash}" == "${env_hash}" ]]; then
    # загрузка из кэша / load from cache
    local line key value
    while IFS= read -r line; do
      [[ "${line}" == "#"* ]] && continue
      key="${line%%=*}"
      value="${line#*=}"
      is::not_empty "${key}" && PF_FACTS["${key}"]="${value}"
    done < "${PLATFORM_CACHE_FILE}"
    PF_BUILT=1
    return 0
  fi
  platform::__build
  # запись кэша / write cache
  mkdir -p "$(dirname "${PLATFORM_CACHE_FILE}")"
  printf '# env_hash=%s\n' "${env_hash}" > "${PLATFORM_CACHE_FILE}"
  local k
  for k in "${!PF_FACTS[@]}"; do
    printf '%s=%s\n' "${k}" "${PF_FACTS[${k}]}"
  done | sort >> "${PLATFORM_CACHE_FILE}"
}

# @description Get one fact (capability vector entry).
# @description Получить один факт (запись вектора возможностей).
# @param $1 Key: kernel/arch/distro/family/repo/userland/libc/bash/tier/
#        procfs/sysfs/dmi/tool_* / Ключ
# @param $2 [optional] Default / Значение по умолчанию
# @stdout the fact / факт
# @return 0 found, 1 not
# @example
#   platform::get repo        # dnf
#   platform::get tool_grep_p # 1
platform::get() {
  platform::__ensure
  local -r key="${1:?key required}"
  if [[ -v PF_FACTS["${key}"] ]]; then
    printf '%s\n' "${PF_FACTS[${key}]}"
    return 0
  fi
  if (( $# >= 2 )); then
    printf '%s\n' "${2}"
    return 0
  fi
  return 1
}

# @description Print all facts / Вывести все факты.
# @stdout "key = value" lines / строки «ключ = значение»
platform::dump() {
  platform::__ensure
  local k
  for k in "${!PF_FACTS[@]}"; do
    printf '%s = %s\n' "${k}" "${PF_FACTS[${k}]}"
  done | sort
}

# @description First available command (probe chain).
# @description Первая доступная команда (цепочка проб).
# @param $@ Command names / Имена команд
# @stdout the command or nothing / команда или ничего
# @return 0 found, 1 none
# @example
#   sha_cmd="$(platform::probe sha256sum shasum cksum)"
platform::probe() {
  local cmd
  for cmd in "$@"; do
    if utils::has "${cmd}"; then
      printf '%s\n' "${cmd}"
      return 0
    fi
  done
  return 1
}

# @description Current compatibility tier.
# @description Текущий тир совместимости.
# @stdout core | gnu-linux | bsd
platform::tier() {
  platform::__ensure
  printf '%s\n' "${PF_FACTS[tier]}"
}

# @description Drop the cache / Сбросить кэш.
platform::reset() {
  PF_FACTS=()
  PF_BUILT=0
  rm -f "${PLATFORM_CACHE_FILE}"
}