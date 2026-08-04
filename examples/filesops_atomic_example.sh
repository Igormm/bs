#!/usr/bin/env bs
# examples/filesops_atomic_example.sh — FSH atomic/backup/fallback demo
# Пример атомарного копирования, резервных копий и move-fallback в BS.

set -euo pipefail

load "core/utils"
load "lib/io/files"

main() {
    local work_dir
    work_dir="$(mktemp -d)"
    echo "Working in: ${work_dir}"

    # ==========================================
    # 1. Atomic file copy with backup
    # Атомарное копирование файла с бэкапом
    # ==========================================
    echo "--- 1. Atomic copy_file with backup ---"
    printf 'old config\n' > "${work_dir}/config.yml"
    printf 'new config\n' > "${work_dir}/config.yml.new"

    io::files::copy_file "${work_dir}/config.yml.new" "${work_dir}/config.yml" true ".bak"

    echo "Current config:"
    cat "${work_dir}/config.yml"
    echo "Backup config:"
    cat "${work_dir}/config.yml.bak"

    # ==========================================
    # 2. Atomic directory copy with backup
    # Атомарное копирование каталога с бэкапом
    # ==========================================
    echo ""
    echo "--- 2. Atomic copy_dir with backup ---"
    mkdir -p "${work_dir}/release_v2/bin"
    printf 'v2 binary\n' > "${work_dir}/release_v2/bin/app"

    mkdir -p "${work_dir}/current/bin"
    printf 'v1 binary\n' > "${work_dir}/current/bin/app"

    io::files::copy_dir "${work_dir}/release_v2" "${work_dir}/current" true ".previous"

    echo "Current app version:"
    cat "${work_dir}/current/bin/app"
    echo "Previous app version:"
    cat "${work_dir}/current.previous/bin/app"

    # ==========================================
    # 3. Move with cross-device fallback
    # Move с fallback между разными ФС
    # ==========================================
    echo ""
    echo "--- 3. Move with atomic fallback ---"
    printf 'log line\n' > "${work_dir}/app.log"
    mkdir -p "${work_dir}/logs"

    io::files::move "${work_dir}/app.log" "${work_dir}/logs/app.log" true ".bak"

    if [[ ! -e "${work_dir}/app.log" && -f "${work_dir}/logs/app.log" ]]; then
        echo "Move succeeded (direct mv or fallback cp+rm)"
    fi

    # ==========================================
    # 4. Env defaults
    # Глобальные настройки через env
    # ==========================================
    echo ""
    echo "--- 4. Env defaults (BS_FILES_*) ---"
    export BS_FILES_ATOMIC=true
    export BS_FILES_BACKUP_SUFFIX=".envbak"
    export BS_FILES_ATOMIC_FALLBACK=true

    printf 'env source\n' > "${work_dir}/env_src.txt"
    printf 'env old\n' > "${work_dir}/env_dst.txt"

    # Теперь atomic=true и backup=.envbak по умолчанию
    io::files::copy_file "${work_dir}/env_src.txt" "${work_dir}/env_dst.txt"

    echo "Destination content:"
    cat "${work_dir}/env_dst.txt"
    echo "Backup content:"
    cat "${work_dir}/env_dst.txt.envbak"

    unset BS_FILES_ATOMIC BS_FILES_BACKUP_SUFFIX BS_FILES_ATOMIC_FALLBACK

    # ==========================================
    # 5. Dry-run mode
    # Режим сухого прогона
    # ==========================================
    echo ""
    echo "--- 5. Dry-run mode ---"
    export FRAMEWORK_DRY_RUN=true

    printf 'will not appear\n' > "${work_dir}/dry_src.txt"
    io::files::copy_file "${work_dir}/dry_src.txt" "${work_dir}/dry_dst.txt" true ".bak"

    if [[ ! -e "${work_dir}/dry_dst.txt" ]]; then
        echo "Dry-run did not create dry_dst.txt as expected"
    fi

    unset FRAMEWORK_DRY_RUN

    echo ""
    echo "Done. Inspect ${work_dir} or remove it manually."
}

main "$@"
