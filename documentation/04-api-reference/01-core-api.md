#!/usr/bin/env bs
# api.sh — Direct Telegram API integration for BS framework

# @description Initialize telegram API integration module
# @example
#   load "lib/telegramintegration/api"
telegram_api::init() {
    # Import presentation module for beautiful output
    load "lib/presentation"
}

# @description Set the Telegram API token for direct API calls
# @param $1 Telegram API token
# @example
#   telegram_api::set_token "123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11"
telegram_api::set_token() {
    local token="$1"
    export TELEGRAM_API_TOKEN="$token"
    presentation::success "Telegram API token set"
}

# @description Get the current API token
# @example
#   token=$(telegram_api::get_token)
telegram_api::get_token() {
    echo "${TELEGRAM_API_TOKEN:-}"
}

# @description Make a direct API call to Telegram
# @param $1 Method name (e.g., sendMessage, getMe, etc.)
# @param $2 JSON payload (optional)
# @example
#   response=$(telegram_api::api_call "getMe")
telegram_api::api_call() {
    local method="$1"
    local payload="${2:-}"
    
    if [[ -z "${TELEGRAM_API_TOKEN:-}" ]]; then
        presentation::error "Telegram API token not set. Use telegram_api::set_token first."
        return 1
    fi
    
    local url="https://api.telegram.org/bot${TELEGRAM_API_TOKEN}/$method"
    
    if command -v curl >/dev/null 2>&1; then
        if [[ -n "$payload" ]]; then
            response=$(curl -s -X POST "$url" \
                -H "Content-Type: application/json" \
                -d "$payload")
        else
            response=$(curl -s "$url")
        fi
        
        echo "$response"
    elif command -v wget >/dev/null 2>&1; then
        if [[ -n "$payload" ]]; then
            response=$(wget --post-data="$payload" \
                --header="Content-Type: application/json" \
                -qO- "$url")
        else
            response=$(wget -qO- "$url")
        fi
        
        echo "$response"
    else
        presentation::error "Neither curl nor wget is available to make API calls"
        return 1
    fi
}

# @description Send a message using direct API call
# @param $1 Chat ID
# @param $2 Message text
# @param $3 Optional reply markup (JSON)
# @example
#   telegram_api::send_message "123456789" "Hello from BS!"
telegram_api::send_message() {
    local chat_id="$1"
    local text="$2"
    local reply_markup="${3:-}"
    
    local payload="{\"chat_id\":\"$chat_id\",\"text\":\"$text\",\"parse_mode\":\"Markdown\""
    
    if [[ -n "$reply_markup" ]]; then
        payload="${payload},\"reply_markup\":$reply_markup"
    fi
    
    payload="${payload}}"
    
    response=$(telegram_api::api_call "sendMessage" "$payload")
    
    if echo "$response" | grep -q '"ok":true'; then
        presentation::success "Message sent successfully to chat ID: $chat_id"
        echo "$response"
    else
        presentation::error "Failed to send message: $response"
        return 1
    fi
}

# @description Edit a message using direct API call
# @param $1 Chat ID
# @param $2 Message ID
# @param $3 New text
# @example
#   telegram_api::edit_message "123456789" "123" "Updated message"
telegram_api::edit_message() {
    local chat_id="$1"
    local message_id="$2"
    local text="$3"
    
    local payload="{\"chat_id\":\"$chat_id\",\"message_id\":$message_id,\"text\":\"$text\",\"parse_mode\":\"Markdown\"}"
    
    response=$(telegram_api::api_call "editMessageText" "$payload")
    
    if echo "$response" | grep -q '"ok":true'; then
        presentation::success "Message edited successfully"
        echo "$response"
    else
        presentation::error "Failed to edit message: $response"
        return 1
    fi
}

# @description Delete a message using direct API call
# @param $1 Chat ID
# @param $2 Message ID
# @example
#   telegram_api::delete_message "123456789" "123"
telegram_api::delete_message() {
    local chat_id="$1"
    local message_id="$2"
    
    local payload="{\"chat_id\":\"$chat_id\",\"message_id\":$message_id}"
    
    response=$(telegram_api::api_call "deleteMessage" "$payload")
    
    if echo "$response" | grep -q '"ok":true'; then
        presentation::success "Message deleted successfully"
        echo "$response"
    else
        presentation::error "Failed to delete message: $response"
        return 1
    fi
}

# @description Get chat information
# @param $1 Chat ID
# @example
#   chat_info=$(telegram_api::get_chat "123456789")
telegram_api::get_chat() {
    local chat_id="$1"
    local payload="{\"chat_id\":\"$chat_id\"}"
    
    response=$(telegram_api::api_call "getChat" "$payload")
    echo "$response"
}

# @description Get chat administrators
# @param $1 Chat ID
# @example
#   admins=$(telegram_api::get_chat_administrators "123456789")
telegram_api::get_chat_administrators() {
    local chat_id="$1"
    local payload="{\"chat_id\":\"$chat_id\"}"
    
    response=$(telegram_api::api_call "getChatAdministrators" "$payload")
    echo "$response"
}

# @description Kick a chat member
# @param $1 Chat ID
# @param $2 User ID to kick
# @example
#   telegram_api::kick_chat_member "123456789" "987654321"
telegram_api::kick_chat_member() {
    local chat_id="$1"
    local user_id="$2"
    
    local payload="{\"chat_id\":\"$chat_id\",\"user_id\":$user_id}"
    
    response=$(telegram_api::api_call "kickChatMember" "$payload")
    
    if echo "$response" | grep -q '"ok":true'; then
        presentation::success "User $user_id kicked from chat $chat_id"
        echo "$response"
    else
        presentation::error "Failed to kick user: $response"
        return 1
    fi
}

# @description Send an action to indicate bot activity
# @param $1 Chat ID
# @param $2 Action (typing, upload_photo, record_video, etc.)
# @example
#   telegram_api::send_chat_action "123456789" "typing"
telegram_api::send_chat_action() {
    local chat_id="$1"
    local action="$2"
    
    local payload="{\"chat_id\":\"$chat_id\",\"action\":\"$action\"}"
    
    response=$(telegram_api::api_call "sendChatAction" "$payload")
    
    if echo "$response" | grep -q '"ok":true'; then
        presentation::success "Chat action '$action' sent to chat ID: $chat_id"
    else
        presentation::error "Failed to send chat action: $response"
    fi
}

# @description Format inline keyboard markup
# @param $@ Button definitions in format: "text1:url1" "text2:callback_data2" ...
# @example
# markup=$(telegram_api::format_inline_keyboard "Button1:https://example.com"
# "Button2:callback_data")
telegram_api::format_inline_keyboard() {
    local buttons=("$@")
    local result="{\"inline_keyboard\":[["
    
    local first_row=true
    for button in "${buttons[@]}"; do
        if [[ "$first_row" == false ]]; then
            result="${result},"
        fi
        
        local text="${button%%:*}"
        local value="${button#*:}"
        
        # Check if it's a URL or callback_data
        if [[ "$value" =~ ^https?:// ]]; then
            result="${result}{\"text\":\"$text\",\"url\":\"$value\"}"
        else
            result="${result}{\"text\":\"$text\",\"callback_data\":\"$value\"}"
        fi
        
        result="${result}]}"
        first_row=false
    done
    
    result="${result}]}"
    echo "$result"
}

# Initialize the telegram API integration module
telegram_api::init