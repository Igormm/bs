#!/usr/bin/env bs
# shellcheck shell=bash
# lib/integration/chat.sh — interactive LLM chat REPL for BS
# lib/integration/chat.sh — интерактивный чат-REPL с LLM для BS

# @depends core/lang, core/utils, core/const, core/logger, core/errorhandler, lib/integration/llm
# @tier gnu-linux

# Source Guard
bs::guard "LIB_INTEGRATION_CHAT" || return 0

# Dependencies
bs::source_relative "../../core/lang.sh" "../../core/utils.sh" "../../core/const.sh" "../../core/logger.sh" "../../core/errorhandler.sh" "llm.sh"

# ==========================================
# LLM chat REPL / Чат-REPL
#
# Interactive multi-turn chat with any OpenAI-compatible or Ollama model.
# The history is kept as a JSON array of {role, content} objects and sent
# on every turn (last N turns, default 20). Configuration comes through
# the CLI (bs chat) or env vars (BS_CHAT_*). A custom local model such as
# Phi Pi plugs in as an OpenAI-compatible endpoint: bs chat --url http://...
# Интерактивный многоходовой чат с любой OpenAI-совместимой моделью или
# Ollama. История хранится JSON-массивом {role, content} и отправляется
# на каждом ходе (последние N ходов, по умолчанию 20). Конфигурация —
# через CLI (bs chat) или env (BS_CHAT_*). Своя локальная модель (Phi Pi)
# подключается как OpenAI-совместимый эндпоинт: bs chat --url http://...
# ==========================================

# @description Build a {role, content} JSON message.
# @description Собрать JSON-сообщение {role, content}.
# @param $1 role (system|user|assistant) / роль
# @param $2 content / содержимое
# @stdout one JSON object / один JSON-объект
chat::message() {
  local -r __ch_role="${1:?role required}" __ch_content="${2-}"
  jq -nc --arg r "${__ch_role}" --arg c "${__ch_content}" '{role: $r, content: $c}'
}

# @description Build the full messages array: system + history + last user.
# @description Собрать полный массив сообщений: system + история + последний user.
# @param $1 System prompt (may be empty) / Системный промпт (может быть пустым)
# @param $@ History JSON objects, then the final user message JSON
#        JSON-объекты истории, затем финальное user-сообщение
# @stdout one JSON array / один JSON-массив
chat::build_messages() {
  local -r __ch_system="${1-}"
  shift
  local -a __ch_parts=()
  if is::not_empty "${__ch_system}"; then
    __ch_parts+=("$(chat::message system "${__ch_system}")")
  fi
  local __ch_m
  for __ch_m in "$@"; do
    __ch_parts+=("${__ch_m}")
  done
  printf '%s\n' "${__ch_parts[@]}" | jq -s -c .
}

# @description One chat turn: send messages, print the model reply.
# @description Один ход чата: отправить сообщения, вывести ответ модели.
# @param $1 provider (openai|ollama)
# @param $2 model name
# @param $3 system prompt (may be empty)
# @param $4 user message
# @param $@ history JSON objects (user/assistant pairs)
# @stdout model reply / ответ модели
# @return 0 ok, error code otherwise
chat::turn() {
  local -r __ch_provider="${1:?provider required}" __ch_model="${2:?model required}"
  local -r __ch_system="${3-}" __ch_input="${4:?message required}"
  shift 4

  local -a __ch_msgs=("$@")
  local __ch_json
  __ch_json="$(chat::build_messages "${__ch_system}" "${__ch_msgs[@]}" "$(chat::message user "${__ch_input}")")"

  log::debug "chat: provider=${__ch_provider} model=${__ch_model} request=${__ch_json}"
  llm::chat_turn "${__ch_provider}" "${__ch_model}" "${__ch_json}"
}

# @description Chat REPL help text / Текст справки чата.
chat::help_text() {
  cat <<HELP
Commands / Команды:
  /quit, /exit      exit / выход
  /clear            clear history (keep system prompt) / очистить историю
  /system <text>    set system prompt / задать системный промпт
  /model <name>     switch model / сменить модель
  /provider <name>  switch provider (openai|ollama) / сменить провайдера
  /history          print history as JSON / показать историю
  /help             this help / эта справка
HELP
}

# @description Main chat REPL loop.
# @description Основной цикл чата.
# @param $1 provider (openai|ollama)
# @param $2 model name
# @param $3 [optional] system prompt / системный промпт
# @param $4 [optional] one-shot message (non-interactive) / разовое сообщение
# @param $5 [optional] history turns to keep, default 20 / ходов в контексте
# @param $6 [optional] 1 = show raw requests (stderr) / показывать сырые запросы
# @return 0 on /quit or EOF
# @example
#   chat::repl ollama llama3 "You are a BS assistant."
#   chat::repl openai gpt-3.5-turbo "" "explain bs" 10
chat::repl() {
  local __ch_provider="${1:?provider required}"
  local __ch_model="${2:?model required}"
  local __ch_system="${3-}"
  local __ch_one_shot="${4-}"
  local -i __ch_limit="${5:-20}"
  local -i __ch_show_raw="${6:-0}"

  local -a __ch_history=()
  local __ch_input __ch_reply __ch_rc=0 __ch_start __ch_elapsed

  if is::not_empty "${__ch_one_shot}"; then
    __ch_start="$(utils::now_ms)"
    __ch_reply="$(chat::turn "${__ch_provider}" "${__ch_model}" "${__ch_system}" "${__ch_one_shot}")" || __ch_rc=$?
    __ch_elapsed=$(( $(utils::now_ms) - __ch_start ))
    if (( __ch_rc != 0 )); then
      log::error "chat::turn: request failed (rc=${__ch_rc}; check provider/model/network) / сбой запроса (rc=${__ch_rc}; проверьте провайдера/модель/сеть)"
      return "${__ch_rc}"
    fi
    printf '%s\n' "${__ch_reply}"
    log::info "${__ch_model} replied in ${__ch_elapsed} ms"
    return 0
  fi

  log::info "BS chat: provider=${__ch_provider} model=${__ch_model}"
  log::info "Type /help for commands, /quit to exit."

  while true; do
    printf '\033[1m%s\033[0m> ' "${__ch_model}"
    if ! IFS= read -r __ch_input; then
      printf '\n'
      break
    fi

    case "${__ch_input}" in
      /quit|/exit)
        break ;;
      /clear)
        __ch_history=()
        log::info "history cleared"
        continue ;;
      /help)
        chat::help_text
        continue ;;
      /system\ *)
        __ch_system="${__ch_input#/system }"
        log::info "system prompt set (${#__ch_system} chars)"
        continue ;;
      /model\ *)
        __ch_model="${__ch_input#/model }"
        log::info "model: ${__ch_model}"
        continue ;;
      /provider\ *)
        __ch_provider="${__ch_input#/provider }"
        log::info "provider: ${__ch_provider}"
        continue ;;
      /history)
        printf '%s\n' "${__ch_history[@]}"
        continue ;;
      "")
        continue ;;
    esac

    # Контекст: последние (limit * 2) записей истории / Last limit*2 entries
    local -a __ch_window=()
    if (( ${#__ch_history[@]} > __ch_limit * 2 )); then
      __ch_window=("${__ch_history[@]:${#__ch_history[@]} - __ch_limit * 2}")
    else
      __ch_window=("${__ch_history[@]}")
    fi

    if (( __ch_show_raw == 1 )); then
      log::info "request messages: $(chat::build_messages "${__ch_system}" "${__ch_window[@]}" "$(chat::message user "${__ch_input}")")"
    fi

    __ch_start="$(utils::now_ms)"
    __ch_rc=0
    __ch_reply="$(chat::turn "${__ch_provider}" "${__ch_model}" "${__ch_system}" "${__ch_input}" "${__ch_window[@]}")" || __ch_rc=$?
    __ch_elapsed=$(( $(utils::now_ms) - __ch_start ))

    if (( __ch_rc != 0 )); then
      log::error "chat::turn: request failed (rc=${__ch_rc}; check provider/model/network) / сбой запроса (rc=${__ch_rc}; проверьте провайдера/модель/сеть)"
      continue
    fi

    printf '%s\n' "${__ch_reply}"
    log::info "${__ch_model} replied in ${__ch_elapsed} ms"
    __ch_history+=("$(chat::message user "${__ch_input}")" "$(chat::message assistant "${__ch_reply}")")
  done

  return 0
}