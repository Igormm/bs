#!/usr/bin/env bs
# examples/http_example.sh — HTTP client demo
# Пример использования HTTP-клиента BS.

set -euo pipefail

load "core/utils"
load "lib/integration/http"
load "lib/integration/result"

main() {
    echo "--- HTTP GET ---"
    http::get "https://api.github.com" | head -c 200
    echo ""

    echo ""
    echo "--- HTTP GET to JSON result ---"
    result::run -- http::get "https://api.github.com"

    echo ""
    echo "--- HTTP POST (dry-run) ---"
    export FRAMEWORK_DRY_RUN=true
    http::post "https://api.example.com/users" '{"name":"alice"}' --header "Content-Type: application/json"
    unset FRAMEWORK_DRY_RUN

    echo ""
    echo "--- HTTP download (dry-run) ---"
    export FRAMEWORK_DRY_RUN=true
    http::download "https://example.com/file.iso" "/tmp/file.iso" --timeout 60
    unset FRAMEWORK_DRY_RUN

    echo ""
    echo "--- HTTP retry ---"
    # Retry a command that fails first then succeeds
    local tmp_script
    tmp_script="$(mktemp)"
    cat > "${tmp_script}" <<'EOF'
#!/usr/bin/env bash
if [[ -f /tmp/http_retry_marker ]]; then
  echo "success"
  rm -f /tmp/http_retry_marker
  exit 0
else
  touch /tmp/http_retry_marker
  exit 1
fi
EOF
    chmod +x "${tmp_script}"
    http::retry 2 1 "${tmp_script}"
    rm -f "${tmp_script}"
    echo "Retry succeeded"
}

main "$@"
