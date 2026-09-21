#!/usr/bin/env bs
# shellcheck shell=bash
# lib/ts/stack.sh — local mini TS stack orchestrator (thriller)
# lib/ts/stack.sh — оркестратор локального мини-стека TS (thriller)
#
# BS holds the stage; TypeScript sings. Default stack name is thriller —
# a private local floor (you and MJ).
# BS держит сцену, TypeScript поёт. Имя стека по умолчанию — thriller.
#
# @depends core/const, core/logger, core/utils, core/lang, core/errorhandler, lib/ts/toolchain, lib/io/files
# @tier core

bs::guard "TS_STACK" || return 0

bs::source_relative "../../core/const.sh" "../../core/logger.sh" \
  "../../core/utils.sh" "../../core/lang.sh" \
  "../../core/errorhandler.sh" "toolchain.sh" "../io/files.sh"

# shellcheck disable=SC2034
declare -g TS_STACK_VERSION="1.0.0"
# shellcheck disable=SC2034
declare -g TS_STACK_LOADED="1"

: "${TS_STACK_NAME:=thriller}"
: "${TS_STACK_STATE:=${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/bs-ts}"
: "${TS_STACK_API_PORT:=8787}"
: "${TS_STACK_WEB_PORT:=5173}"

# ==========================================
# Paths / Пути
# ==========================================

# @private
ts::stack::__state_root() {
  printf '%s/%s\n' "${TS_STACK_STATE%/}" "${TS_STACK_NAME}"
}

# @private
ts::stack::__alive() {
  local -r pid="${1-}"
  is::number "${pid}" || return 1
  (( pid > 1 )) || return 1
  kill -0 "${pid}" 2>/dev/null
}

# @private
ts::stack::__cfg() {
  local -r file="${1-}"
  local -r want="${2-}"
  local -r key="${3-}"
  local -r def="${4-}"
  if ! is::file "${file}"; then
    printf '%s\n' "${def}"
    return 0
  fi
  local line section="" k v
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="$(str::trim "${line}")"
    [[ "${line}" == \#* ]] && continue
    is::not_empty "${line}" || continue
    if [[ "${line}" =~ ^\[(.*)\]$ ]]; then
      section="$(str::trim "${BASH_REMATCH[1]}")"
      continue
    fi
    k="$(str::trim "${line%%=*}")"
    v="$(str::trim "${line#*=}")"
    if [[ "${section}" == "${want}" && "${k}" == "${key}" ]]; then
      printf '%s\n' "${v}"
      return 0
    fi
  done < "${file}"
  printf '%s\n' "${def}"
  return 0
}

# @private
ts::stack::__pick_port() {
  local -r start="${1:?}"
  local -i p n
  for (( n = 0; n < 20; n++ )); do
    p=$(( start + n ))
    if ts::toolchain::port_free "${p}"; then
      printf '%s\n' "${p}"
      return "${E_SUCCESS}"
    fi
  done
  error::throw "no free port near ${start}" "${E_ERROR}"
  return "${E_ERROR}"
}

# @private
ts::stack::__spawn() {
  local -r log_file="${1:?}"
  local -r workdir="${2:?}"
  local -r port="${3:?}"
  local -r cmdline="${4:?}"
  (
    cd "${workdir}" || exit 1
    export PORT="${port}"
    bash -c "${cmdline}"
  ) >> "${log_file}" 2>&1 &
  printf '%s\n' "$!"
  return 0
}

# @private
ts::stack::__api_cmd() {
  local -r dir="${1:?}"
  if is::not_empty "${TS_STACK_API_CMD:-}"; then
    printf '%s\n' "${TS_STACK_API_CMD}"
    return 0
  fi
  if is::file "${dir}/apps/api/index.ts" && \
     ts::toolchain::__local_bin "${dir}" tsx >/dev/null 2>&1; then
    printf '%s\n' "tsx apps/api/index.ts"
    return 0
  fi
  if is::file "${dir}/apps/api/index.ts" && utils::has node; then
    printf '%s\n' "node --experimental-strip-types apps/api/index.ts"
    return 0
  fi
  if is::dir "${dir}/fixtures" && utils::has python3; then
    printf '%s\n' \
      "python3 -m http.server \"\${PORT}\" --bind 127.0.0.1 --directory fixtures"
    return 0
  fi
  return "${LIB_ERROR_DEPENDENCY_MISSING}"
}

# @private
ts::stack::__web_cmd() {
  local -r dir="${1:?}"
  if is::not_empty "${TS_STACK_WEB_CMD:-}"; then
    printf '%s\n' "${TS_STACK_WEB_CMD}"
    return 0
  fi
  if is::dir "${dir}/public" && utils::has python3; then
    printf '%s\n' \
      "python3 -m http.server \"\${PORT}\" --bind 127.0.0.1 --directory public"
    return 0
  fi
  return 1
}

# ==========================================
# Public API
# ==========================================

# @description Scaffold a thriller mini-app (ini + api + fixtures).
# @description Каркас мини-приложения thriller (ini + api + fixtures).
# @param $1 [dir] Project directory / Каталог проекта
ts::stack::init() {
  local -r dir="${1:-.}"
  io::files::ensure_dir "${dir}/apps/api" || return $?
  io::files::ensure_dir "${dir}/fixtures" || return $?
  io::files::ensure_dir "${dir}/public" || return $?

  if ! is::file "${dir}/bs-stack.ini"; then
    printf '%s\n' \
      "[stack]" \
      "name=${TS_STACK_NAME}" \
      "[api]" \
      "port=${TS_STACK_API_PORT}" \
      "[web]" \
      "port=${TS_STACK_WEB_PORT}" \
      > "${dir}/bs-stack.ini"
  fi
  if ! is::file "${dir}/fixtures/health.json"; then
    printf '%s\n' \
      '{"ok":true,"stack":"thriller","floor":"private"}' \
      > "${dir}/fixtures/health.json"
  fi
  if ! is::file "${dir}/apps/api/index.ts"; then
    cat > "${dir}/apps/api/index.ts" <<'TS'
import { createServer } from "node:http";

const port = Number(process.env.PORT || 8787);
createServer((req, res) => {
  const url = req.url || "/";
  if (url === "/health" || url === "/") {
    res.setHeader("content-type", "application/json");
    res.end(JSON.stringify({
      ok: true,
      stack: "thriller",
      floor: "private",
    }));
    return;
  }
  res.statusCode = 404;
  res.end("not found");
}).listen(port, "127.0.0.1");
TS
  fi
  if ! is::file "${dir}/public/index.html"; then
    cat > "${dir}/public/index.html" <<'HTML'
<!doctype html>
<meta charset="utf-8">
<title>thriller</title>
<pre id="out">loading…</pre>
<script>
fetch("/health.json").then(r => r.text()).then(t => {
  document.getElementById("out").textContent = t;
}).catch(e => { document.getElementById("out").textContent = String(e); });
</script>
HTML
  fi
  log::info "thriller scaffolded in ${dir}"
  return "${E_SUCCESS}"
}

# @description Start the local stack (api, optional web).
# @description Поднять локальный стек (api, опционально web).
# @param $1 [dir] Project directory / Каталог проекта
ts::stack::up() {
  local -r dir="${1:-.}"
  local -r root="$(ts::stack::__state_root)"
  local -r ini="${dir}/bs-stack.ini"
  io::files::ensure_dir "${dir}" || return $?
  io::files::ensure_dir "${root}" || return $?

  local api_pid
  api_pid="$(cat "${root}/api.pid" 2>/dev/null || true)"
  if ts::stack::__alive "${api_pid}"; then
    log::warn "stack already up (pid ${api_pid})"
    ts::stack::status
    return "${E_SUCCESS}"
  fi

  local api_cmd web_cmd api_port web_port
  api_cmd="$(ts::stack::__api_cmd "${dir}")" || {
    error::throw "no api command (set TS_STACK_API_CMD or run init)" \
      "${LIB_ERROR_DEPENDENCY_MISSING}"
    return "${LIB_ERROR_DEPENDENCY_MISSING}"
  }
  api_port="$(ts::stack::__cfg "${ini}" api port "${TS_STACK_API_PORT}")"
  api_port="$(ts::stack::__pick_port "${api_port}")" || return $?

  api_pid="$(ts::stack::__spawn "${root}/api.log" "${dir}" \
    "${api_port}" "${api_cmd}")"
  printf '%s\n' "${api_pid}" > "${root}/api.pid"
  printf '%s\n' "${api_port}" > "${root}/api.port"
  printf '%s\n' "${dir}" > "${root}/project"

  web_cmd="$(ts::stack::__web_cmd "${dir}")" || web_cmd=""
  if is::not_empty "${web_cmd}"; then
    web_port="$(ts::stack::__cfg "${ini}" web port "${TS_STACK_WEB_PORT}")"
    web_port="$(ts::stack::__pick_port "${web_port}")" || return $?
    local web_pid
    web_pid="$(ts::stack::__spawn "${root}/web.log" "${dir}" \
      "${web_port}" "${web_cmd}")"
    printf '%s\n' "${web_pid}" > "${root}/web.pid"
    printf '%s\n' "${web_port}" > "${root}/web.port"
  fi

  log::info "thriller up  api=:${api_port}  pid=${api_pid}"
  ts::stack::status
  return "${E_SUCCESS}"
}

# @description Stop the local stack.
# @description Остановить локальный стек.
ts::stack::down() {
  local -r root="$(ts::stack::__state_root)"
  local pid
  for pid in "${root}/api.pid" "${root}/web.pid"; do
    is::file "${pid}" || continue
    local p
    p="$(cat "${pid}" 2>/dev/null || true)"
    if ts::stack::__alive "${p}"; then
      kill "${p}" 2>/dev/null || true
    fi
    rm -f -- "${pid}"
  done
  log::info "thriller down"
  return "${E_SUCCESS}"
}

# @description Print stack status (pid/port/alive).
# @description Печать статуса стека (pid/port/alive).
# @stdout label=value lines
ts::stack::status() {
  local -r root="$(ts::stack::__state_root)"
  printf 'name=%s\n' "${TS_STACK_NAME}"
  printf 'state=%s\n' "${root}"
  local role pid port
  for role in api web; do
    pid="$(cat "${root}/${role}.pid" 2>/dev/null || true)"
    port="$(cat "${root}/${role}.port" 2>/dev/null || true)"
    if ts::stack::__alive "${pid}"; then
      printf '%s.alive=yes\n' "${role}"
    else
      printf '%s.alive=no\n' "${role}"
    fi
    is::not_empty "${pid}" && printf '%s.pid=%s\n' "${role}" "${pid}"
    is::not_empty "${port}" && printf '%s.port=%s\n' "${role}" "${port}"
  done
  return 0
}

# @description Print last log lines (api or web).
# @description Последние строки лога (api или web).
# @param $1 [api|web] Role / Роль
# @stdout log tail
ts::stack::logs() {
  local -r role="${1:-api}"
  local -r root="$(ts::stack::__state_root)"
  local -r file="${root}/${role}.log"
  if ! is::file "${file}"; then
    error::throw "no log for ${role}" "${LIB_ERROR_FILE_NOT_FOUND}"
    return "${LIB_ERROR_FILE_NOT_FOUND}"
  fi
  if utils::has tail; then
    tail -n 40 "${file}"
  else
    cat "${file}"
  fi
  return 0
}
