# mtest/t_lang.sh — core/lang.sh predicates (bs_is_*) in every shell
. "$(dirname "$0")/lib.sh"; mt_init
T=$(mktemp -d); : > "$T/empty"; echo x > "$T/full"; ln -s full "$T/lnk"; printf '#!/bin/sh\n' > "$T/exe"; chmod +x "$T/exe"; mkdir "$T/dir"

# S1
mt_rc "S1 is_dir" 0 bs_is_dir "$T/dir"
mt_rc "S1 is_file" 0 bs_is_file "$T/full"
mt_rc "S1 is_exists" 0 bs_is_exists "$T/full"
mt_rc "S1 is_symlink" 0 bs_is_symlink "$T/lnk"
mt_rc "S1 is_executable" 0 bs_is_executable "$T/exe"
mt_rc "S1 is_readable" 0 bs_is_readable "$T/full"
mt_rc "S1 is_writable" 0 bs_is_writable "$T/full"
mt_rc "S1 is_number" 0 bs_is_number 42
mt_rc "S1 is_command" 0 bs_is_command ls
mt_rc "S1 is_empty" 0 bs_is_empty ""
mt_rc "S1 is_file_not_empty" 0 bs_is_file_not_empty "$T/full"

# S2
mt_rc "S2 dir is not a file" 1 bs_is_file "$T/dir"
mt_rc "S2 file is not a dir" 1 bs_is_dir "$T/full"
mt_rc "S2 empty file is not file_not_empty" 1 bs_is_file_not_empty "$T/empty"
mt_rc "S2 plain file not a symlink" 1 bs_is_symlink "$T/full"
mt_rc "S2 plain file not executable" 1 bs_is_executable "$T/full"
mt_rc "S2 missing path" 1 bs_is_exists "$T/none"
mt_rc "S2 not number" 1 bs_is_number 1a
mt_rc "S2 not command" 1 bs_is_command no_such_cmd_zz
mt_rc "S2 non-empty string is not empty" 1 bs_is_empty x
mt_rc "S2 not_empty" 0 bs_is_not_empty x

# S3 parameters
: > "$T/with space"; mt_rc "S3 path with space exists" 0 bs_is_file "$T/with space"
mt_rc "S3 number leading zero" 0 bs_is_number 007
mt_rc "S3 number negative is not number" 1 bs_is_number -1
mt_rc "S3 number with newline" 1 bs_is_number "1
2"
mt_rc "S3 path starting with dash" 1 bs_is_file "-f"
mt_rc "S3 path glob star literal" 1 bs_is_exists "$T/*"
ln -s nowhere "$T/dangling"; mt_rc "S3 dangling is symlink" 0 bs_is_symlink "$T/dangling"; mt_rc "S3 dangling does not exist" 1 bs_is_exists "$T/dangling"

# S4
mt_rc "S4 is_number no arg" 1 bs_is_number
mt_rc "S4 is_dir no arg" 1 bs_is_dir
mt_rc "S4 is_file empty arg" 1 bs_is_file ""
mt_nz "S4 is_command no arg" bs_is_command
mt_rc "S4 is_empty no arg" 0 bs_is_empty
rm -rf "$T"
mt_done
