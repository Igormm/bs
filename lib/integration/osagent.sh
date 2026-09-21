#!/usr/bin/env bs
# shellcheck shell=bash
# lib/integration/osagent.sh — OS agent: LLM talks to the machine via safe tools
# lib/integration/osagent.sh — ОС-агент: LLM общается с машиной через безопасные инструменты

# @depends core/lang, core/const, core/logger, core/utils, lib/platform/facts, lib/system/hw, lib/api/openapi, lib/integration/llm
# @tier gnu-linux

bs::guard "LIB_INTEGRATION_OSAGENT" || return 0

bs::source_relative "../../core/lang.sh" "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh" "../platform/facts.sh" "../system/hw.sh" "../api/openapi.sh" "llm.sh"

# ==========================================
# OS agent / ОС-агент
#
# Model-agnostic tool calling: the tool schema and platform context are put
# into the prompt, the model answers with JSON {"tool": ..., "args": ...}
# or {"answer": ...}; tools run behind a deny-by-default permission gate.
# Модель-агностичный вызов инструментов: схема инструментов и контекст
# платформы кладутся в промпт, модель отвечает JSON-ом {"tool": ...}
# или {"answer": ...}; инструменты выполняются за гейтом «запрещено по умолчанию».
#
#   osagent::ask "Какая модель процессора и сколько памяти?"
#   osagent::exec hw.get '{"key": "mb.cpu.model"}'
# ==========================================

# Allow policy: comma-separated tool patterns (tool or tool:args-substring).
# Политика доступа: список паттернов через запятую (tool или tool:подстрока-аргументов).
declare -g OSAGENT_ALLOW="${OSAGENT_ALLOW:-hw.*,platform.*,bs.list,files.read,api.call}"

# Allow arbitrary command execution (osagent.exec) / Разрешить произвольные команды
declare -g OSAGENT_EXEC_ALLOW="${OSAGENT_EXEC_ALLOW:-false}"

# @description Print the current permission policy.
# @description Показать текущую политику прав.
osagent::permissions() {
  printf 'allow:  %s\n' "${OSAGENT_ALLOW}"
  printf 'exec:   %s\n' "${OSAGENT_EXEC_ALLOW}"
  printf 'tools:  %s\n' "$(osagent::tools::names)"
  return 0
}

# @description Tool schema as a JSON array (for the prompt).
# @description Схема инструментов как JSON-массив (для промпта).
# @stdout JSON / JSON
osagent::tools::schema() {
  cat <<'EOF'
[
  {"name": "hw.get", "description": "Read a hardware DB key (e.g. mb.cpu.name, mb.cpu.cores, mb.system.vendor, mb.memory.total_bytes)", "args": {"key": "string"}},
  {"name": "hw.search", "description": "Search hardware DB by substring (e.g. cpu, mem)", "args": {"query": "string"}},
  {"name": "platform.facts", "description": "Platform facts: kernel, distro, libc, userland, tiers", "args": {}},
  {"name": "bs.list", "description": "List framework modules (core/ and lib/)", "args": {}},
  {"name": "files.read", "description": "Read a text file (max 4000 bytes)", "args": {"path": "string"}},
  {"name": "api.call", "description": "Call an OpenAPI operation (only GET/HEAD unless exec allowed)", "args": {"spec": "string", "method": "string", "path": "string"}},
  {"name": "osagent.exec", "description": "Run a shell command (disabled unless OSAGENT_EXEC_ALLOW=true)", "args": {"command": "string"}}
]
EOF
  return 0
}

# @description Tool names, space-separated.
# @description Имена инструментов через пробел.
osagent::tools::names() {
  osagent::tools::schema | jq -r '.[].name' | tr '\n' ' '
  printf '\n'
  return 0
}

# @description Assemble platform context as JSON.
# @description Собрать контекст платформы как JSON.
# @stdout JSON / JSON
osagent::context() {
  local facts tier
  facts="$(platform::dump 2>/dev/null | jq -Rs 'split("\n") | map(select(length > 0) | split(" = ") | { (.[0]): .[1] }) | add // {}')"
  tier="$(platform::tier 2>/dev/null || printf 'unknown')"
  jq -nc --argjson f "${facts}" --arg tier "${tier}" '{platform: $f, tier: $tier, specs: (env.API_SPECS // {})}'
  return 0
}

# @private
# @description Permission check: is the tool call allowed?
# @description Проверка прав: разрешён ли вызов инструмента?
# @param $1 tool name, $2 args JSON
osagent::__allowed() {
  local -r tool="$1" args="$2"
  if [[ "${tool}" == "osagent.exec" ]]; then
    [[ "${OSAGENT_EXEC_ALLOW}" == "true" ]] && return 0 || return 1
  fi
  local rule
  IFS=',' read -ra rules <<< "${OSAGENT_ALLOW}"
  for rule in "${rules[@]}"; do
    [[ -z "${rule}" ]] && continue
    local name="${rule%%:*}"
    local substr="${rule#*:}"
    if [[ "${tool}" == ${name} ]]; then
      if [[ "${substr}" == "${name}" ]]; then
        return 0
      fi
      [[ "${args}" == *"${substr}"* ]] && return 0
    fi
  done
  return 1
}

# @description Execute a tool call safely.
# @description Безопасно выполнить вызов инструмента.
# @param $1 tool name / имя инструмента
# @param $2 args JSON / аргументы JSON
# @stdout tool result / результат инструмента
# @return 0 ok, 1 denied, 2 tool error
osagent::exec() {
  local -r tool="${1:?tool name required}"
  local args="${2-}"
  [[ -n "${args}" ]] || args="{}"

  if ! osagent::__allowed "${tool}" "${args}"; then
    log::error "osagent::exec: ${tool} is not allowed (policy: ${OSAGENT_ALLOW}; exec=${OSAGENT_EXEC_ALLOW})"
    return 1
  fi

  if [[ "${FRAMEWORK_DRY_RUN:-false}" == "true" ]]; then
    log::info "osagent::exec: [DRY-RUN] ${tool} ${args}"
    return 0
  fi

  local key query path spec method
  case "${tool}" in
    hw.get)
      key="$(jq -r '.key // empty' <<< "${args}")"
      if is::empty "${key}"; then
        log::error "osagent::exec: hw.get requires .key"
        return 2
      fi
      hw::get "${key}" 2>/dev/null || { log::error "osagent::exec: no such hw key: ${key} (try hw.search)"; return 2; }
      ;;
    hw.search)
      query="$(jq -r '.query // empty' <<< "${args}")"
      hw::find "${query}" 2>/dev/null || return 2
      ;;
    platform.facts)
      platform::dump 2>/dev/null || return 2
      ;;
    bs.list)
      printf 'core:\n'
      find "${BS_ROOT}/core" -maxdepth 1 -name '*.sh' -printf '  %f\n' 2>/dev/null | sort
      printf 'lib:\n'
      find "${BS_ROOT}/lib" -maxdepth 2 -name '*.sh' -printf '  %P\n' 2>/dev/null | sort
      ;;
    files.read)
      path="$(jq -r '.path // empty' <<< "${args}")"
      if is::empty "${path}" || ! is::file "${path}"; then
        log::error "osagent::exec: files.read requires an existing file path"
        return 2
      fi
      head -c 4000 -- "${path}"
      # WRAPPER-CANDIDATE: utils::head_bytes — files.read caps output ad-hoc; a shared truncate-read helper would serve api/tui/agent / кандидат-обёртка: utils::head_bytes — ограниченное чтение повторяется в api/tui/agent
      ;;
    api.call)
      spec="$(jq -r '.spec // empty' <<< "${args}")"
      method="$(jq -r '.method // empty' <<< "${args}")"
      path="$(jq -r '.path // empty' <<< "${args}")"
      if is::empty "${spec}" || is::empty "${method}" || is::empty "${path}"; then
        log::error "osagent::exec: api.call requires .spec, .method, .path"
        return 2
      fi
      if [[ "${method}" != "GET" && "${method}" != "HEAD" && "${OSAGENT_EXEC_ALLOW}" != "true" ]]; then
        log::error "osagent::exec: api.call ${method} is not allowed (only GET/HEAD; set OSAGENT_EXEC_ALLOW=true to widen)"
        return 1
      fi
      api::call "${spec}" "${method}" "${path}" --json 2>/dev/null || return 2
      ;;
    osagent.exec)
      local cmd
      cmd="$(jq -r '.command // empty' <<< "${args}")"
      if is::empty "${cmd}"; then
        log::error "osagent::exec: osagent.exec requires .command"
        return 2
      fi
      timeout 10 bash -c "${cmd}" 2>&1 || { log::error "osagent::exec: command failed (timeout 10s)"; return 2; }
      ;;
    *)
      log::error "osagent::exec: unknown tool: ${tool} (available: $(osagent::tools::names))"
      return 2
      ;;
  esac
  return 0
}

# @private
# @description Build the system prompt: context + tools + protocol.
# @description Собрать системный промпт: контекст + инструменты + протокол.
osagent::__system_prompt() {
  local ctx
  ctx="$(osagent::context)"
  cat <<EOF
You are an OS agent running inside the BS Bash framework. Platform context:
${ctx}

Available tools:
$(osagent::tools::schema | jq -r '.[] | "- \(.name): \(.description) (args: \(.args))"')

Answer the user's question. If you need machine data, respond with EXACTLY one
JSON object: {"tool": "<name>", "args": {...}}. Otherwise respond with
{"answer": "<your answer>"}. No text outside the JSON.
EOF
}

# @private
# @description One tool round: ask the model, execute the requested tool.
# @description Один раунд инструментов: спросить модель, выполнить запрошенный инструмент.
# @stdout JSON {"tool":..., "result":...} or {"answer":...}
osagent::__round() {
  local -r provider="$1" model="$2" question="$3"
  local system="$4"
  local prompt
  prompt="$(jq -nc --arg q "${question}" --arg sys "${system}" '{system: $sys, user: $q}')"

  local reply
  reply="$(llm::chat "${provider}" "${model}" "$(jq -r '.system + "\n\nUser: " + .user' <<< "${prompt}")")" || return 4

  local parsed
  if ! parsed="$(printf '%s' "${reply}" | jq -c 'select(type == "object") // empty' 2>/dev/null)"; then
    printf '{"answer": "%s"}' "$(printf '%s' "${reply}" | jq -Rs .)"
    return 0
  fi

  if [[ -n "$(jq -r '.tool // empty' <<< "${parsed}")" ]]; then
    local tool args result rc=0
    tool="$(jq -r '.tool' <<< "${parsed}")"
    args="$(jq -c '.args // {}' <<< "${parsed}")"
    result="$(osagent::exec "${tool}" "${args}" 2>/dev/null)" || rc=$?
    jq -nc --arg tool "${tool}" --arg result "${result}" --argjson rc "${rc}" '{tool: $tool, result: $result, rc: $rc}'
    return 0
  fi

  printf '%s' "${parsed}"
  return 0
}

# @description Ask the agent a question (one tool round).
# @description Задать агенту вопрос (один раунд инструментов).
# @param $1 question / вопрос
# @param $2 [--provider P] [--model M] [--json]
# @stdout answer; with --json: full round JSON / ответ; с --json: полный JSON раунда
# @return 0 ok, 4 LLM error
osagent::ask() {
  local question="${1:?question required}"
  shift
  local provider="${LLM_PROVIDER:-openai}"
  local model="${LLM_MODEL:-gpt-4o-mini}"
  local json_mode=0
  while [[ $# -gt 0 ]]; do
    case "${1:-}" in
      --provider) provider="${2-}"; shift 2 ;;
      --model) model="${2-}"; shift 2 ;;
      --json) json_mode=1; shift ;;
      *) log::error "osagent::ask: unknown argument: ${1}"; return "${E_INVALID}" ;;
    esac
  done

  local system round
  system="$(osagent::__system_prompt)"
  round="$(osagent::__round "${provider}" "${model}" "${question}" "${system}")" || return 4

  if [[ -n "$(jq -r '.tool // empty' <<< "${round}")" ]]; then
    local tool_result final tool_name
    tool_result="$(jq -r '.result' <<< "${round}")"
    tool_name="$(jq -r '.tool' <<< "${round}")"
    local sys2
    sys2="${system}

Tool call ${tool_name} result (rc=$(jq -r '.rc' <<< "${round}")):
${tool_result}

If the data answers the question, respond with {"answer": "..."}; you may use one more tool call."
    final="$(osagent::__round "${provider}" "${model}" "${question}" "${sys2}")" || return 4
    round="${final}"
  fi

  if (( json_mode == 1 )); then
    printf '%s\n' "${round}"
    return 0
  fi

  jq -r '.answer // .tool // "no answer"' <<< "${round}"
  return 0
}