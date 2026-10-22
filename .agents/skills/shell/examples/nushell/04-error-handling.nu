# GOOD: recover from a failure with try/catch, and read a maybe-missing column
# safely with an optional cell path plus a default. Static-checks clean.

let result = try { 10 / 2 } catch {|err| $"error: ($err.msg)" }
print $result

let rec = {name: "ada"}
print ($rec | get -o email | default "none")
