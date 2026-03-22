#!/usr/bin/env bash

helper::usage() {

    printf "BS installer

Usage:
  ./install.sh [--local] [install|uninstall] [--path|--update-path]
  sudo ./install.sh [install|uninstall]

Notes:
  --path and --update-path are valid only with --local.
  --path и --update-path работают только с --local.

Examples:
  sudo ./install.sh
  sudo ./install.sh install
  sudo ./install.sh uninstall

  ./install.sh --local
  sudo ./install.sh --local install
  ./install.sh --local uninstall

  ./install.sh --local --path
  ./install.sh --local --update-path"

}

# PATH snippet (local) / Сниппет PATH (локально)
helper::path_snippet() {
  cat <<'SNIP'
# BS (local) - add to PATH / добавить в PATH
export PATH="$HOME/.local/bin:$PATH"
SNIP
}

# Print PATH hint / Подсказка по PATH
helper::print_path_hint() {
  printf "To use shebang: #!/usr/bin/env bs\n"
  printf "Чтобы работало: #!/usr/bin/env bs\n"
  printf "Add ~/.local/bin to PATH (e.g., in ~/.bashrc or ~/.zshrc):\n"
  printf "Добавьте ~/.local/bin в PATH (например, в ~/.bashrc или ~/.zshrc):\n\n"
  path_snippet
  printf "\n"
}
