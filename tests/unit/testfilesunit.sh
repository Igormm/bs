#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testfilesunit.sh — Unit tests for lib/io/files
# tests/unit/testfilesunit.sh — Модульные тесты для модуля io::files

set -euo pipefail

# Подключаем тестовый фреймворк / Source test framework
readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

# Инициализируем BS / Initialize BS
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

# Подключаем тестируемый модуль / Load module under test
load "lib/io/files"

main() {
    print_header "IO Files Unit Tests"
    print_header "Модульные тесты файловых операций"

    testframework::init

    local tmp_dir
    tmp_dir="$(mktemp -d)"

    # ==========================================
    # ensure_dir
    # ==========================================
    testframework::section "ensure_dir"

    io::files::ensure_dir "${tmp_dir}/newdir"
    testframework::assert_command "io::files::is_dir '${tmp_dir}/newdir'" "ensure_dir creates directory"

    io::files::ensure_dir "${tmp_dir}/modedir" "700"
    local mode
    mode="$(stat -c '%a' "${tmp_dir}/modedir")"
    testframework::assert_equal "700" "${mode}" "ensure_dir sets mode"

    # ==========================================
    # copy_file
    # ==========================================
    testframework::section "copy_file"

    printf 'hello\n' > "${tmp_dir}/src.txt"
    io::files::copy_file "${tmp_dir}/src.txt" "${tmp_dir}/dst.txt"
    testframework::assert_command "io::files::is_file '${tmp_dir}/dst.txt'" "copy_file creates destination file"
    testframework::assert_equal "hello" "$(cat "${tmp_dir}/dst.txt")" "copy_file copies content"

    # Отсутствующий источник / Missing source
    local rc=0
    io::files::copy_file "${tmp_dir}/missing.txt" "${tmp_dir}/x.txt" || rc=$?
    testframework::assert_equal "${LIB_ERROR_FILE_NOT_FOUND}" "${rc}" "copy_file returns FILE_NOT_FOUND for missing source"

    # ==========================================
    # copy_dir
    # ==========================================
    testframework::section "copy_dir"

    mkdir -p "${tmp_dir}/srcdir/sub"
    printf 'nested\n' > "${tmp_dir}/srcdir/sub/file.txt"
    io::files::copy_dir "${tmp_dir}/srcdir" "${tmp_dir}/dstdir"
    testframework::assert_command "io::files::is_dir '${tmp_dir}/dstdir/sub'" "copy_dir creates nested directory"
    testframework::assert_equal "nested" "$(cat "${tmp_dir}/dstdir/sub/file.txt")" "copy_dir copies nested content"

    # ==========================================
    # sync_dir
    # ==========================================
    testframework::section "sync_dir"

    mkdir -p "${tmp_dir}/syncsrc/sub"
    mkdir -p "${tmp_dir}/syncdst"
    printf 'new\n' > "${tmp_dir}/syncsrc/sub/a.txt"
    printf 'old\n' > "${tmp_dir}/syncdst/keep.txt"

    io::files::sync_dir "${tmp_dir}/syncsrc" "${tmp_dir}/syncdst" false
    testframework::assert_command "io::files::exists '${tmp_dir}/syncdst/sub/a.txt'" "sync_dir additive copies new files"
    testframework::assert_command "io::files::exists '${tmp_dir}/syncdst/keep.txt'" "sync_dir additive keeps existing files"

    io::files::sync_dir "${tmp_dir}/syncsrc" "${tmp_dir}/syncdst" true
    testframework::assert_false "io::files::exists '${tmp_dir}/syncdst/keep.txt'" "sync_dir mirror removes extra files"
    testframework::assert_command "io::files::exists '${tmp_dir}/syncdst/sub/a.txt'" "sync_dir mirror keeps source files"

    # ==========================================
    # copy_matching
    # ==========================================
    testframework::section "copy_matching"

    mkdir -p "${tmp_dir}/matchsrc"
    printf 'sh\n' > "${tmp_dir}/matchsrc/a.sh"
    printf 'md\n' > "${tmp_dir}/matchsrc/b.md"
    printf 'tmp\n' > "${tmp_dir}/matchsrc/c.tmp"
    mkdir -p "${tmp_dir}/matchsrc/deep"
    printf 'deep\n' > "${tmp_dir}/matchsrc/deep/d.sh"

    io::files::copy_matching "${tmp_dir}/matchsrc" "${tmp_dir}/matchdst" "*.sh *.md" "*.tmp"
    testframework::assert_command "io::files::exists '${tmp_dir}/matchdst/a.sh'" "copy_matching includes .sh"
    testframework::assert_command "io::files::exists '${tmp_dir}/matchdst/b.md'" "copy_matching includes .md"
    testframework::assert_command "io::files::exists '${tmp_dir}/matchdst/deep/d.sh'" "copy_matching preserves structure"
    testframework::assert_false "io::files::exists '${tmp_dir}/matchdst/c.tmp'" "copy_matching excludes .tmp"

    # ==========================================
    # move / cut / remove
    # ==========================================
    testframework::section "move, cut and remove"

    printf 'move-me\n' > "${tmp_dir}/move_src.txt"
    io::files::move "${tmp_dir}/move_src.txt" "${tmp_dir}/move_dst.txt"
    testframework::assert_false "io::files::exists '${tmp_dir}/move_src.txt'" "move removes source"
    testframework::assert_command "io::files::exists '${tmp_dir}/move_dst.txt'" "move creates destination"

    printf 'cut-me\n' > "${tmp_dir}/cut_src.txt"
    io::files::cut "${tmp_dir}/cut_src.txt" "${tmp_dir}/cut_dst.txt"
    testframework::assert_false "io::files::exists '${tmp_dir}/cut_src.txt'" "cut removes source"
    testframework::assert_command "io::files::exists '${tmp_dir}/cut_dst.txt'" "cut creates destination"

    mkdir -p "${tmp_dir}/remdir/sub"
    io::files::remove "${tmp_dir}/remdir" true
    testframework::assert_false "io::files::exists '${tmp_dir}/remdir'" "remove recursive deletes directory"

    printf 'delete-me\n' > "${tmp_dir}/remfile.txt"
    io::files::remove "${tmp_dir}/remfile.txt"
    testframework::assert_false "io::files::exists '${tmp_dir}/remfile.txt'" "remove deletes file"

    # ==========================================
    # dry-run
    # ==========================================
    testframework::section "dry-run mode"

    export FRAMEWORK_DRY_RUN=true
    printf 'dry\n' > "${tmp_dir}/dry_src.txt"
    io::files::copy_file "${tmp_dir}/dry_src.txt" "${tmp_dir}/dry_dst.txt"
    testframework::assert_false "io::files::exists '${tmp_dir}/dry_dst.txt'" "dry-run does not create files"
    unset FRAMEWORK_DRY_RUN

    # ==========================================
    # Atomic copy_file
    # ==========================================
    testframework::section "copy_file atomic"

    printf 'atomic-content\n' > "${tmp_dir}/atomic_src.txt"
    io::files::copy_file "${tmp_dir}/atomic_src.txt" "${tmp_dir}/atomic_dst.txt" true
    testframework::assert_equal "atomic-content" "$(cat "${tmp_dir}/atomic_dst.txt")" "atomic copy_file copies content"
    testframework::assert_false "ls '${tmp_dir}' | grep -q 'atomic_dst.txt.tmp\\.'" "atomic copy_file leaves no temp file"

    # ==========================================
    # copy_file backup
    # ==========================================
    testframework::section "copy_file backup"

    printf 'old-content\n' > "${tmp_dir}/backup_dst.txt"
    printf 'new-content\n' > "${tmp_dir}/backup_src.txt"
    io::files::copy_file "${tmp_dir}/backup_src.txt" "${tmp_dir}/backup_dst.txt" false ".bak"
    testframework::assert_equal "new-content" "$(cat "${tmp_dir}/backup_dst.txt")" "backup copy_file updates destination"
    testframework::assert_equal "old-content" "$(cat "${tmp_dir}/backup_dst.txt.bak")" "backup copy_file keeps backup"

    # ==========================================
    # Atomic copy_dir
    # ==========================================
    testframework::section "copy_dir atomic"

    mkdir -p "${tmp_dir}/atomic_src/sub"
    printf 'deep\n' > "${tmp_dir}/atomic_src/sub/file.txt"
    io::files::copy_dir "${tmp_dir}/atomic_src" "${tmp_dir}/atomic_dst" true
    testframework::assert_equal "deep" "$(cat "${tmp_dir}/atomic_dst/sub/file.txt")" "atomic copy_dir copies nested content"
    testframework::assert_false "ls -A '${tmp_dir}' | grep -q 'atomic_dst.tmp\\.'" "atomic copy_dir leaves no temp dir"

    # ==========================================
    # copy_dir backup
    # ==========================================
    testframework::section "copy_dir backup"

    mkdir -p "${tmp_dir}/backup_dsrc/sub"
    mkdir -p "${tmp_dir}/backup_ddst/old"
    printf 'new-deep\n' > "${tmp_dir}/backup_dsrc/sub/file.txt"
    printf 'old-deep\n' > "${tmp_dir}/backup_ddst/old/file.txt"
    io::files::copy_dir "${tmp_dir}/backup_dsrc" "${tmp_dir}/backup_ddst" false ".bak"
    testframework::assert_equal "new-deep" "$(cat "${tmp_dir}/backup_ddst/sub/file.txt")" "backup copy_dir updates destination"
    testframework::assert_equal "old-deep" "$(cat "${tmp_dir}/backup_ddst.bak/old/file.txt")" "backup copy_dir keeps backup"

    # ==========================================
    # move backup
    # ==========================================
    testframework::section "move backup"

    printf 'move-old\n' > "${tmp_dir}/move_backup_dst.txt"
    printf 'move-new\n' > "${tmp_dir}/move_backup_src.txt"
    io::files::move "${tmp_dir}/move_backup_src.txt" "${tmp_dir}/move_backup_dst.txt" false ".bak"
    testframework::assert_false "io::files::exists '${tmp_dir}/move_backup_src.txt'" "move backup removes source"
    testframework::assert_equal "move-new" "$(cat "${tmp_dir}/move_backup_dst.txt")" "move backup updates destination"
    testframework::assert_equal "move-old" "$(cat "${tmp_dir}/move_backup_dst.txt.bak")" "move backup keeps backup"

    # ==========================================
    # move atomic fallback
    # ==========================================
    testframework::section "move atomic fallback"

    printf 'fallback-content\n' > "${tmp_dir}/fallback_src.txt"
    io::files::move "${tmp_dir}/fallback_src.txt" "${tmp_dir}/fallback_dst.txt" true
    testframework::assert_false "io::files::exists '${tmp_dir}/fallback_src.txt'" "move fallback removes source"
    testframework::assert_command "io::files::is_file '${tmp_dir}/fallback_dst.txt'" "move fallback creates destination"
    testframework::assert_equal "fallback-content" "$(cat "${tmp_dir}/fallback_dst.txt")" "move fallback preserves content"

    # ==========================================
    # Cleanup and summary
    # ==========================================
    rm -rf "${tmp_dir}"

    testframework::summary
}

main "$@"
