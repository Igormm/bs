#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testtreeunit.sh — unit tests for lib/io/tree
# tests/unit/testtreeunit.sh — модульные тесты lib/io/tree

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

load "lib/io/tree"

tree_test::dump_has() {
  local -r kind="${1}" path="${2}"
  local dump
  dump="$(io::tree::dump)"
  [[ "${dump}" == *"${kind}"$'\t'"${path}"* ]]
}

main() {
  print_header "IO Tree Unit Tests / Модульные тесты io::tree"
  testframework::init

  local tmp
  tmp="$(mktemp -d)"

  testframework::section "Module loading / Загрузка модуля"
  testframework::assert_true "${IO_TREE_LOADED:-}" "module loaded"

  testframework::section "TXT path list / Список путей"
  io::tree::parse_text $'src/main.sh\ndocs/\nREADME.md\n' txt
  testframework::assert_command "tree_test::dump_has f src/main.sh" \
    "txt file path"
  testframework::assert_command "tree_test::dump_has d docs" "txt dir slash"
  testframework::assert_command "tree_test::dump_has f README.md" \
    "txt root file"

  testframework::section "TXT indent tree / Дерево отступами"
  io::tree::parse_text $'src/\n  lib/\n    util.sh\nREADME.md\n' txt
  testframework::assert_command "tree_test::dump_has d src" "indent src dir"
  testframework::assert_command "tree_test::dump_has d src/lib" \
    "indent nested dir"
  testframework::assert_command "tree_test::dump_has f src/lib/util.sh" \
    "indent nested file"

  testframework::section "CSV / CSV"
  io::tree::parse_text \
    $'path,kind,content\nsrc,dir,\nsrc/app.sh,file,"hello"\n' csv
  testframework::assert_command "tree_test::dump_has d src" "csv dir"
  testframework::assert_command "tree_test::dump_has f src/app.sh" "csv file"

  testframework::section "INI / INI"
  io::tree::parse_text $'[src]\napp.sh = #!/usr/bin/env bs\n[docs]\n' ini
  testframework::assert_command "tree_test::dump_has d src" "ini section dir"
  testframework::assert_command "tree_test::dump_has f src/app.sh" \
    "ini section file"
  testframework::assert_command "tree_test::dump_has d docs" \
    "ini empty section"

  testframework::section "YAML mapping / YAML-отображение"
  io::tree::parse_text $'src:\n  app.sh: "hi"\nREADME.md: title\nempty/:\n' \
    yaml
  testframework::assert_command "tree_test::dump_has d src" "yaml dir"
  testframework::assert_command "tree_test::dump_has f src/app.sh" \
    "yaml nested file"
  testframework::assert_command "tree_test::dump_has f README.md" \
    "yaml root file"
  testframework::assert_command "tree_test::dump_has d empty" \
    "yaml empty dir slash"

  testframework::section "YAML block scalar / YAML-блок"
  io::tree::parse_text $'note.txt: |\n  line1\n  line2\n' yaml
  testframework::assert_equal $'line1\nline2' \
    "${IO_TREE_BODY[0]%$'\n'}" "yaml block body"

  testframework::section "Detect / Определение формата"
  printf 'a: b\n' > "${tmp}/t.yaml"
  printf '[x]\n' > "${tmp}/t.ini"
  printf 'path,kind\n' > "${tmp}/t.csv"
  printf 'a/b\n' > "${tmp}/t.txt"
  testframework::assert_equal "yaml" "$(io::tree::detect "${tmp}/t.yaml")" \
    "detect yaml ext"
  testframework::assert_equal "ini" "$(io::tree::detect "${tmp}/t.ini")" \
    "detect ini ext"
  testframework::assert_equal "csv" "$(io::tree::detect "${tmp}/t.csv")" \
    "detect csv ext"
  testframework::assert_equal "txt" "$(io::tree::detect "${tmp}/t.txt")" \
    "detect txt ext"

  testframework::section "Reject traversal / Запрет обхода"
  local rc=0
  io::tree::parse_text $'../etc/passwd\n' txt || rc=$?
  testframework::assert_equal "${E_INVALID}" "${rc}" "reject .. in txt"
  rc=0
  io::tree::parse_text $'/etc/passwd:\n' yaml || rc=$?
  testframework::assert_equal "${E_INVALID}" "${rc}" "reject absolute yaml"

  testframework::section "Apply / Создание"
  io::tree::parse_text $'src:\n  app.sh: "hello"\nempty/:\n' yaml
  io::tree::apply "${tmp}/proj"
  testframework::assert_file_exists "${tmp}/proj/src/app.sh" "wrote file"
  testframework::assert_equal "hello" "$(cat "${tmp}/proj/src/app.sh")" \
    "file body"
  testframework::assert_command "is::dir '${tmp}/proj/empty'" "empty dir"

  testframework::section "No overwrite / Без перезаписи"
  printf 'old' > "${tmp}/proj/src/app.sh"
  io::tree::apply "${tmp}/proj"
  testframework::assert_equal "old" "$(cat "${tmp}/proj/src/app.sh")" \
    "keeps existing without force"
  io::tree::apply "${tmp}/proj" 1
  testframework::assert_equal "hello" "$(cat "${tmp}/proj/src/app.sh")" \
    "force overwrites"

  testframework::section "Dry-run / Сухой прогон"
  IO_TREE_DRY_RUN=1
  io::tree::parse_text $'ghost.txt: x\n' yaml
  io::tree::apply "${tmp}/dry"
  IO_TREE_DRY_RUN=0
  testframework::assert_false "is::file '${tmp}/dry/ghost.txt'" \
    "dry-run does not write"

  testframework::section "create from file / create из файла"
  printf 'ok.sh: "ok"\n' > "${tmp}/spec.yaml"
  io::tree::create "${tmp}/spec.yaml" "${tmp}/out"
  testframework::assert_file_exists "${tmp}/out/ok.sh" "create writes"
  testframework::assert_equal "ok" "$(cat "${tmp}/out/ok.sh")" \
    "create body"

  io::tree::create --dry-run "${tmp}/spec.yaml" "${tmp}/ghost2"
  testframework::assert_false "is::file '${tmp}/ghost2/ok.sh'" \
    "create --dry-run skips write"

  testframework::section "Plan / План"
  io::tree::parse_text $'a.txt: z\n' yaml
  local plan
  plan="$(io::tree::plan "${tmp}/out")"
  testframework::assert_true "'${plan}' =~ WRITE" "plan mentions WRITE"

  rm -rf -- "${tmp}"
  testframework::summary
}

main "$@"
