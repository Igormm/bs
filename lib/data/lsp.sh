#!/usr/bin/env bs
# shellcheck shell=bash
# lib/data/lsp.sh — Language Server Protocol server for BS
# lib/data/lsp.sh — LSP-сервер для BS

# @depends core/lang, core/const, core/logger, core/errorhandler, lib/data/langdoc

# Source Guard
bs::guard "LIB_DATA_LSP" || return 0

# Dependencies
bs::source_relative "../../core/lang.sh" "../../core/const.sh" "../../core/logger.sh" "../../core/errorhandler.sh" "../data/langdoc.sh"

# ==========================================
# Language Server Protocol / Протокол языкового сервера
#
# Implements a minimal LSP server on stdin/stdout (JSON-RPC 2.0 with
# Content-Length framing): initialize, hover, completion, document sync.
# Full text sync (textDocumentSync: 1). The function index over BS_ROOT
# is built lazily on the first hover/completion request (see bs lang-doc).
# Requires jq.
# Минимальный LSP-сервер на stdin/stdout (JSON-RPC 2.0 с фреймингом
# Content-Length): initialize, hover, completion, синхронизация документов.
# Полная синхронизация текста (textDocumentSync: 1). Индекс функций
# BS_ROOT строится лениво при первом запросе hover/completion
# (см. bs lang-doc). Требует jq.
# ==========================================

# Server state / Состояние сервера
declare -g LSP_INDEX="[]"
declare -g LSP_INDEX_BUILT=0
declare -g LSP_EXTRA="[]"
declare -gA LSP_DOCS=()

# @description Send a raw LSP message (Content-Length framing).
# @description Отправить сырое LSP-сообщение (фрейминг Content-Length).
# @param $1 Message body / Тело сообщения
lsp::__send() {
  local -r __lsp_msg="$1"
  local __lsp_len
  __lsp_len="$(printf '%s' "${__lsp_msg}" | LC_ALL=C wc -c)"
  printf 'Content-Length: %s\r\n\r\n%s' "${__lsp_len}" "${__lsp_msg}"
}

# @description Respond to a request (or send a notification-free message).
# @description Ответить на запрос.
# @param $1 Message id (JSON: number, string, or null) / id сообщения
# @param $2 Result (JSON) / Результат (JSON)
lsp::__respond() {
  local -r __lsp_id="$1" __lsp_result="$2"
  lsp::__send "{\"jsonrpc\":\"2.0\",\"id\":${__lsp_id},\"result\":${__lsp_result}}"
}

# @description Build the BS function index once (lazy).
# @description Построить индекс функций BS один раз (лениво).
lsp::__ensure_index() {
  if (( LSP_INDEX_BUILT == 0 )); then
    LSP_INDEX="$(langdoc::index "${BS_ROOT}" 2>/dev/null || printf '[]')"
    LSP_INDEX_BUILT=1
  fi
}

# @description Find a function by exact name in index + open-file extras.
# @description Найти функцию по точному имени в индексе + открытых файлах.
#   The index goes via stdin (a single argv entry is capped at ~128 KiB
#   by the kernel MAX_ARG_STRLEN — the full index is bigger).
# @param $1 Word / Слово
# @stdout JSON object or null / JSON-объект или null
lsp::__find_by_name() {
  local -r __lsp_word="$1"
  printf '%s' "${LSP_INDEX}" | jq -c --arg w "${__lsp_word}" --argjson extra "${LSP_EXTRA}" \
    '([.[], $extra[]] | map(select(.name == $w)) | .[0]) // null'
}

# @description Markdown tooltip for a function (hover).
# @description Markdown-tooltip для функции (hover).
# @param $1 Function JSON object / JSON-объект функции
# @stdout Hover result JSON / JSON-результат hover
lsp::__hover_result() {
  jq -c '{contents: {kind: "markdown", value: (
      "**" + .name + "**  `" + .file + "`\n\n" + .description + "\n\n" +
      ([.params[] | "- `" + .name + "` — " + .desc] | join("\n")) +
      "\n\n**Returns:** " + .returns +
      "\n\n**Example:**\n```bash\n" + .example + "\n```"
    )}}' <<< "${1}"
}

# @description Completion items matching a prefix.
# @description Элементы completion по префиксу.
# @param $1 Prefix (may be empty) / Префикс (может быть пустым)
# @stdout CompletionList JSON / JSON-список completion
lsp::__completion_items() {
  local -r __lsp_prefix="$1"
  if is::empty "${__lsp_prefix}"; then
    # No prefix: offer the framework namespaces / Без префикса — неймспейсы
    jq -nc '{isIncomplete: false, items: [
      {label: "arr::", kind: 3, detail: "arrays"},
      {label: "str::", kind: 3, detail: "strings"},
      {label: "map::", kind: 3, detail: "associative arrays"},
      {label: "bs::", kind: 3, detail: "framework core"},
      {label: "is::", kind: 3, detail: "predicates"}
    ]}'
    return 0
  fi
  printf '%s' "${LSP_INDEX}" | jq -c --arg p "${__lsp_prefix}" --argjson extra "${LSP_EXTRA}" '
    ([.[], $extra[]] | unique_by(.name) | map(select(.name | startswith($p))) | .[0:100] | map({
      label: .name,
      kind: 3,
      detail: (.file + ": " + (.description | split("\n")[0])),
      documentation: {kind: "markdown", value: (
        "**" + .name + "**\n\n" + .description + "\n\n" +
        ([.params[] | "- `" + .name + "` — " + .desc] | join("\n"))
      )}
    })) | {isIncomplete: false, items: .}'
}

# @description Line of text at a 0-based index.
# @description Строка текста по 0-индексу.
# @param $1 Multi-line text / Многострочный текст
# @param $2 Line index / Индекс строки
# @stdout the line / строка
lsp::__line_at() {
  printf '%s\n' "${1}" | sed -n "$(( ${2:-0} + 1 ))p"
}

# @description Word containing a character position (hover).
# @description Слово, содержащее позицию символа (hover).
# @param $1 Line text / Текст строки
# @param $2 Character index / Индекс символа
# @stdout the word, possibly empty / слово, возможно пустое
lsp::__word_at() {
  local -r __lsp_line="${1-}" __lsp_ch="${2:-0}"
  local __lsp_left="${__lsp_line:0:${__lsp_ch}}" __lsp_right="${__lsp_line:${__lsp_ch}}"
  local __lsp_w1="" __lsp_w2=""
  [[ "${__lsp_left}" =~ ([A-Za-z0-9_:]+)$ ]] && __lsp_w1="${BASH_REMATCH[1]}"
  [[ "${__lsp_right}" =~ ^([A-Za-z0-9_:]+) ]] && __lsp_w2="${BASH_REMATCH[1]}"
  printf '%s%s\n' "${__lsp_w1}" "${__lsp_w2}"
}

# @description Word prefix before a character position (completion).
# @description Префикс слова перед позицией символа (completion).
# @param $1 Line text / Текст строки
# @param $2 Character index / Индекс символа
# @stdout the prefix, possibly empty / префикс, возможно пустой
lsp::__prefix_at() {
  local -r __lsp_line="${1-}" __lsp_ch="${2:-0}"
  local __lsp_left="${__lsp_line:0:${__lsp_ch}}"
  if [[ "${__lsp_left}" =~ ([A-Za-z0-9_:]+)$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  fi
}

# @description Natural-language query before the cursor (description search).
# @description Естественно-языковый запрос перед курсором (поиск по описанию).
#   The text after the last `?` (spaces allowed), or the comment text when
#   the cursor is inside a comment line. Empty when in prefix mode.
#   Текст после последнего `?` (пробелы допустимы), либо текст комментария,
#   когда курсор внутри комментария. Пусто в режиме префикса.
# @param $1 Line text / Текст строки
# @param $2 Character index / Индекс символа
# @stdout the query, possibly empty / запрос, возможно пустой
lsp::__query_at() {
  local -r __lsp_line="${1-}" __lsp_ch="${2:-0}"
  local __lsp_left="${__lsp_line:0:${__lsp_ch}}"
  local __lsp_q=""
  if [[ "${__lsp_left}" == *"?"* ]]; then
    __lsp_q="${__lsp_left##*\?}"
  elif [[ "${__lsp_left}" =~ ^[[:space:]]*# ]]; then
    __lsp_q="${__lsp_left#*\#}"
    __lsp_q="${__lsp_q#"${__lsp_q%%[![:space:]]*}"}"
  fi
  printf '%s\n' "${__lsp_q}"
}

# @description Fuzzy search over names and descriptions (RU+EN).
# @description Нечёткий поиск по именам и описаниям (RU+EN).
#   Terms (>= 3 chars, lowercased) match the haystack (name + description +
#   param descriptions + example) by substring or by word common-prefix
#   (handles Russian inflection: "строку" ~ "строки"). Fallback: the first
#   term must be a subsequence of the name ("slc" -> arr::slice).
# @param $1 Query string / Строка запроса
# @stdout CompletionList JSON / JSON-список completion
lsp::__fuzzy_items() {
  local -r __lsp_query="$1"
  printf '%s' "${LSP_INDEX}" | jq -c --arg q "${__lsp_query}" --argjson extra "${LSP_EXTRA}" '
    def is_subseq($q):
      ($q | explode) as $qch
      | . as $s
      | reduce $qch[] as $c (0;
          if . < 0 then -1
          else (($s[.:] | index(([$c] | implode))) // null) as $i
               | if $i == null then -1 else . + $i + 1 end
          end)
      | . >= 0;
    def prefix_len($a; $b):
      ($a | explode) as $x
      | ($b | explode) as $y
      | ([$x | length, $y | length] | min) as $m
      | first((range(0; $m) | select($x[.] != $y[.])), $m);
    # jq ascii_downcase ignores Cyrillic; lowercase A-Z and А-Я (codepoints).
    # ascii_downcase в jq игнорирует кириллицу; приводим A-Z и А-Я (кодовые точки).
    def ru_downcase:
      explode | map(
        if . >= 65 and . <= 90 then . + 32          # A-Z
        elif . >= 1040 and . <= 1071 then . + 32    # А-Я
        elif . == 1025 then 1045                    # Ё -> Е
        elif . == 1105 then 1077                    # ё -> е
        else . end
      ) | implode;
    def word_prefix_ok($w; $t):
      (prefix_len($w; $t) as $p | $p >= 4 and ($p * 2) >= ([($w | length), ($t | length)] | min));
    # Term score: substring 2, word common-prefix 1.
    # Очки терма: подстрока 2, общий префикс слова 1.
    def term_score($t; $h):
      ($h | ru_downcase) as $hl
      | if ($hl | contains($t)) then 2
        elif any($hl | split(" ")[]; word_prefix_ok(.; $t)) then 1
        else 0 end;
    def term_hits($terms; $h):
      # jq binds function arguments lazily — a thunk like `.hay` would
      # re-evaluate against the term inside select. Bind values first.
      # jq связывает аргументы лениво — thunk `.hay` перевычислится
      # против терма внутри select. Сначала связываем значения.
      $h as $hh | $terms as $tt
      | [$tt[] | term_score(.; $hh)] | add // 0;
    # Name score: prefix 10, subsequence 5. Subsequence is checked on the
    # last `::`-segment only — a 3-char query is too noisy against full
    # names like `__integration_result::capture_run`.
    # Очки имени: префикс 10, подпоследовательность 5. Подпоследовательность
    # проверяется только по последнему сегменту после `::` — 3-символьный
    # запрос слишком шумит на полных именах вида `...::capture_run`.
    def name_score($name; $q):
      ($name | split("::") | last) as $seg
      | if ($seg | startswith($q)) then 10
        elif ($seg | is_subseq($q)) then 5
        else 0 end;
    def hay:
      [.name, .description, ([.params[].desc] | join(" ")), .example] | join(" ");
    def item_doc:
      {kind: "markdown", value: (
        "**" + .name + "**\n\n" + .description + "\n\n" +
        ([.params[] | "- `" + .name + "` — " + .desc] | join("\n"))
      )};
    ($q | ru_downcase | split(" ") | map(select(length >= 3))) as $terms
    | $terms[0] as $t0
    | if ($terms | length) == 0 then {isIncomplete: false, items: []}
      else
        [.[], $extra[]] as $items
        | ($items | unique_by(.name)) as $uniq
        | ($uniq | map(. + {hay: hay})) as $withhay
        | ($withhay | map(. as $item | (.hay) as $hh | $item + {tscore: term_hits($terms; $hh)})) as $tscored
        | ($tscored | map(. as $item | $item + {score: ($item.tscore + name_score($item.name | ru_downcase; $t0))})) as $scored
        | [$scored[] | select(.score > 0)] as $hits
        | ($hits | sort_by(-.score, .name)) as $sorted
        | [$sorted[0:20][] | {
             label: .name,
             kind: 3,
             detail: (.file + ": " + (.description | split("\n")[0])),
             documentation: item_doc
           }]
        | {isIncomplete: false, items: .}
      end'
}

# ==========================================
# Handlers / Обработчики
# ==========================================

lsp::__on_initialize() {
  lsp::__respond "${1}" \
    '{"capabilities":{"textDocumentSync":1,"hoverProvider":true,"completionProvider":{"triggerCharacters":[":","_","?","#"]}}}'
}

# @description didOpen: store the buffer and index its own functions.
# @description didOpen: сохранить буфер и проиндексировать его функции.
# @param $1 params JSON / JSON параметров
lsp::__on_did_open() {
  local -r __lsp_params="$1"
  local __lsp_uri __lsp_text __lsp_extra
  __lsp_uri="$(printf '%s' "${__lsp_params}" | jq -r '.textDocument.uri')"
  __lsp_text="$(printf '%s' "${__lsp_params}" | jq -r '.textDocument.text // empty')"
  LSP_DOCS["${__lsp_uri}"]="${__lsp_text}"
  __lsp_extra="$(langdoc::parse_text "${__lsp_text}" "${__lsp_uri}" 2>/dev/null || printf '')"
  if is::not_empty "${__lsp_extra}"; then
    LSP_EXTRA="$( { printf '%s' "${LSP_EXTRA}" | jq -c '.[]'; printf '%s\n' "${__lsp_extra}"; } | jq -sc . 2>/dev/null || printf '[]')"
  fi
}

# @description didChange (full sync): update buffer and re-index.
# @description didChange (полная синхронизация): обновить буфер и индекс.
# @param $1 params JSON / JSON параметров
lsp::__on_did_change() {
  local -r __lsp_params="$1"
  local __lsp_uri __lsp_text __lsp_extra
  __lsp_uri="$(printf '%s' "${__lsp_params}" | jq -r '.textDocument.uri')"
  __lsp_text="$(printf '%s' "${__lsp_params}" | jq -r '.contentChanges[0].text // empty')"
  LSP_DOCS["${__lsp_uri}"]="${__lsp_text}"
  __lsp_extra="$(langdoc::parse_text "${__lsp_text}" "${__lsp_uri}" 2>/dev/null || printf '')"
  if is::not_empty "${__lsp_extra}"; then
    LSP_EXTRA="$( { printf '%s' "${LSP_EXTRA}" | jq -c '.[]'; printf '%s\n' "${__lsp_extra}"; } | jq -sc . 2>/dev/null || printf '[]')"
  fi
}

# @description didClose: drop the buffer (extras stay, rebuilt on reopen).
# @description didClose: убрать буфер (extras остаются, перестроятся при повторном открытии).
# @param $1 params JSON / JSON параметров
lsp::__on_did_close() {
  local -r __lsp_params="$1"
  local __lsp_uri
  __lsp_uri="$(printf '%s' "${__lsp_params}" | jq -r '.textDocument.uri')"
  unset 'LSP_DOCS["${__lsp_uri}"]' 2>/dev/null || :
}

# @description hover: find the word, return the tooltip.
# @description hover: найти слово, вернуть tooltip.
# @param $1 Message id / id сообщения
# @param $2 params JSON / JSON параметров
lsp::__on_hover() {
  local -r __lsp_id="$1" __lsp_params="$2"
  local __lsp_uri __lsp_line __lsp_ch __lsp_text __lsp_line_text __lsp_word __lsp_fn
  __lsp_uri="$(printf '%s' "${__lsp_params}" | jq -r '.textDocument.uri')"
  __lsp_line="$(printf '%s' "${__lsp_params}" | jq -r '.position.line // 0')"
  __lsp_ch="$(printf '%s' "${__lsp_params}" | jq -r '.position.character // 0')"
  __lsp_text="${LSP_DOCS["${__lsp_uri}"]:-}"
  if is::empty "${__lsp_text}"; then
    lsp::__respond "${__lsp_id}" null
    return 0
  fi
  lsp::__ensure_index
  __lsp_line_text="$(lsp::__line_at "${__lsp_text}" "${__lsp_line}")"
  __lsp_word="$(lsp::__word_at "${__lsp_line_text}" "${__lsp_ch}")"
  if is::empty "${__lsp_word}"; then
    lsp::__respond "${__lsp_id}" null
    return 0
  fi
  __lsp_fn="$(lsp::__find_by_name "${__lsp_word}")"
  if [[ "${__lsp_fn}" == "null" ]]; then
    lsp::__respond "${__lsp_id}" null
    return 0
  fi
  lsp::__respond "${__lsp_id}" "$(lsp::__hover_result "${__lsp_fn}")"
}

# @description completion: prefix at cursor -> matching functions.
# @description completion: префикс у курсора -> подходящие функции.
# @param $1 Message id / id сообщения
# @param $2 params JSON / JSON параметров
lsp::__on_completion() {
  local -r __lsp_id="$1" __lsp_params="$2"
  local __lsp_uri __lsp_line __lsp_ch __lsp_text __lsp_line_text __lsp_query __lsp_prefix
  __lsp_uri="$(printf '%s' "${__lsp_params}" | jq -r '.textDocument.uri')"
  __lsp_line="$(printf '%s' "${__lsp_params}" | jq -r '.position.line // 0')"
  __lsp_ch="$(printf '%s' "${__lsp_params}" | jq -r '.position.character // 0')"
  __lsp_text="${LSP_DOCS["${__lsp_uri}"]:-}"
  lsp::__ensure_index
  __lsp_line_text="$(lsp::__line_at "${__lsp_text}" "${__lsp_line}")"
  __lsp_query="$(lsp::__query_at "${__lsp_line_text}" "${__lsp_ch}")"
  if is::not_empty "${__lsp_query}"; then
    # Поиск по описанию / Description search
    lsp::__respond "${__lsp_id}" "$(lsp::__fuzzy_items "${__lsp_query}")"
    return 0
  fi
  __lsp_prefix="$(lsp::__prefix_at "${__lsp_line_text}" "${__lsp_ch}")"
  lsp::__respond "${__lsp_id}" "$(lsp::__completion_items "${__lsp_prefix}")"
}

# @description Dispatch one message by method.
# @description Разобрать одно сообщение по методу.
# @param $1 Message body / Тело сообщения
# @return 0 continue loop, 1 stop (exit/EOF)
lsp::__dispatch() {
  local -r __lsp_body="$1"
  local __lsp_method __lsp_id __lsp_params
  __lsp_method="$(printf '%s' "${__lsp_body}" | jq -r '.method // empty')"
  __lsp_id="$(printf '%s' "${__lsp_body}" | jq -c '.id // null')"
  __lsp_params="$(printf '%s' "${__lsp_body}" | jq -c '.params // {}')"

  case "${__lsp_method}" in
    initialize)                    lsp::__on_initialize "${__lsp_id}" ;;
    initialized)                   : ;;
    shutdown)                      lsp::__respond "${__lsp_id}" null ;;
    exit)                          return 1 ;;
    textDocument/didOpen)          lsp::__on_did_open "${__lsp_params}" ;;
    textDocument/didChange)        lsp::__on_did_change "${__lsp_params}" ;;
    textDocument/didClose)         lsp::__on_did_close "${__lsp_params}" ;;
    textDocument/didSave)          : ;;
    textDocument/hover)            lsp::__on_hover "${__lsp_id}" "${__lsp_params}" ;;
    textDocument/completion)       lsp::__on_completion "${__lsp_id}" "${__lsp_params}" ;;
    *)
      if [[ "${__lsp_id}" != "null" ]]; then
        lsp::__respond "${__lsp_id}" null
      fi
      ;;
  esac
  return 0
}

# @description Main server loop: read framed messages from stdin.
# @description Основной цикл сервера: чтение сообщений со stdin.
#   All reads go through bash `read` (LC_ALL=C: byte == char), so the
#   internal input buffer stays consistent — never mix in head/dd here.
#   Все чтения идут через bash `read` (LC_ALL=C: байт == символ), чтобы
#   внутренний буфер ввода оставался согласованным — не подмешивайте head/dd.
# @return 0 on exit notification or EOF
# @example
#   lsp::server
lsp::server() {
  is::command jq || return 1
  local -i __lsp_len=0
  local __lsp_line __lsp_body
  while true; do
    __lsp_len=0
    while LC_ALL=C IFS= read -r __lsp_line; do
      __lsp_line="${__lsp_line%$'\r'}"
      if is::empty "${__lsp_line}"; then
        break
      fi
      if [[ "${__lsp_line}" == Content-Length:* ]]; then
        __lsp_len="${__lsp_line#Content-Length:}"
        __lsp_len="${__lsp_len// /}"
        [[ "${__lsp_len}" =~ ^[0-9]+$ ]] || __lsp_len=0
      fi
    done
    (( __lsp_len > 0 )) || break
    __lsp_body=""
    LC_ALL=C IFS= read -r -N "${__lsp_len}" __lsp_body || :
    lsp::__dispatch "${__lsp_body}" || break
  done
  return 0
}