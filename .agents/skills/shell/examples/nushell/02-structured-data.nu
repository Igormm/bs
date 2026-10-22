# GOOD: operate on structured data with built-ins instead of text munging.
# Static-checks clean with `nu --ide-check`.
#
# The POSIX-shell habit would be `ls -l | awk '$5 > 15 {print $9}'` — fragile
# column counting. In Nushell the columns are named and typed.

let files = [
  {name: "a.txt", size: 10}
  {name: "big.bin", size: 2000}
  {name: "b.txt", size: 20}
]

$files
| where size > 15
| sort-by size
| select name size
| print
