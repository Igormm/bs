#!/bin/sh
# find_git_bash.sh - Locate Git Bash on Windows
# Prints GIT_BASH_PATH if found, exits 1 if not

set -eu

git_path=""

if command -v git >/dev/null 2>&1; then
  git_path=$(command -v git)
fi

if [ -z "$git_path" ]; then
  git_path=$(where git 2>/dev/null || echo "")
fi

if [ -z "$git_path" ]; then
  echo "Error: Git not found. Is Git for Windows installed?"
  echo "Download: https://git-scm.com/downloads"
  exit 1
fi

git_install_dir=$(dirname "$(dirname "$git_path")")
git_bash="${git_install_dir}/bin/bash.exe"

if [ -f "$git_bash" ]; then
  echo "$git_bash"
  if [ -f "${git_install_dir}/usr/bin/pacman.exe" ]; then
    echo "GIT_SDK_AVAILABLE=true"
  fi
  exit 0
else
  echo "Error: Git Bash not found at: $git_bash"
  echo "Expected Git for Windows install layout: <Git>\\bin\\bash.exe"
  exit 1
fi
