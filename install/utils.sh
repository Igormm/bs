#!/usr/bin/env bash

# Utility functions for the installer

# Ask user to confirm
confirm() {
  local prompt="$1"
  local ans
  read -r -p "${prompt} [y/N]: " ans
  [[ "${ans}" == "y" || "${ans}" == "Y" ]]
}

# PATH snippet (local)
path_snippet() {
  cat <<'SNIP'
# BS (local) - add to PATH
export PATH="$HOME/.local/bin:$PATH"
SNIP
}

# Print PATH hint
print_path_hint() {
  printf "To use shebang: #!/usr/bin/env bs\n"
  printf "Чтобы работало: #!/usr/bin/env bs\n"
  printf "Add ~/.local/bin to PATH (e.g., in ~/.bashrc or ~/.zshrc):\n"
  printf "Добавьте ~/.local/bin в PATH (например, в ~/.bashrc или ~/.zshrc):\n\n"
  path_snippet
  printf "\n"
}