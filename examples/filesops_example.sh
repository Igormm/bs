#!/usr/bin/env bs
# examples/filesops_example.sh — FSH (io::files) usage demo
# Пример использования модуля файловых операций BS.

set -euo pipefail

load "core/utils"
load "lib/io/files"

main() {
    local work_dir
    work_dir="$(mktemp -d)"
    echo "Working in: ${work_dir}"

    # Создаём структуру / Create structure
    mkdir -p "${work_dir}/project/src"
    printf '#!/bin/bash\necho hello\n' > "${work_dir}/project/src/hello.sh"
    printf 'docs\n' > "${work_dir}/project/readme.md"
    printf 'skip\n' > "${work_dir}/project/cache.tmp"

    # Копируем каталог / Copy directory
    io::files::copy_dir "${work_dir}/project" "${work_dir}/project_backup"
    echo "Backed up project -> ${work_dir}/project_backup"

    # Синхронизируем по правилам / Sync matching files only
    io::files::copy_matching "${work_dir}/project" "${work_dir}/release" "*.sh *.md" "*.tmp"
    echo "Copied release files:"
    find "${work_dir}/release" -type f

    # Перемещаем / Move
    io::files::move "${work_dir}/project/readme.md" "${work_dir}/project/README.md"
    echo "Moved readme.md -> README.md"

    # Удаляем временное / Remove tmp
    io::files::remove "${work_dir}/project/cache.tmp"
    echo "Removed cache.tmp"

    # Синхронизация каталогов / Directory sync (mirror)
    io::files::sync_dir "${work_dir}/project" "${work_dir}/project_backup" true
    echo "Mirrored project_backup to project"

    # Атомарное копирование с резервной копией / Atomic copy with backup
    printf 'v2\n' > "${work_dir}/project/version.txt"
    printf 'v1\n' > "${work_dir}/project_backup/version.txt"
    io::files::copy_file "${work_dir}/project/version.txt" "${work_dir}/project_backup/version.txt" true ".bak"
    echo "Atomically copied version.txt with .bak backup"

    # Move с fallback / Move with cross-device fallback
    io::files::move "${work_dir}/project/src/hello.sh" "${work_dir}/project/moved_hello.sh" true
    echo "Moved hello.sh with atomic fallback enabled"

    echo "Done. Inspect ${work_dir} or remove it manually."
}

main "$@"
