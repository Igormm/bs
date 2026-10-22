# GOOD: a custom command with typed parameters, a flag, and an input/output
# signature. Types are checked at parse time. Static-checks clean with
# `nu --ide-check`.

def greet [name: string, --caps]: nothing -> string {
  let msg = $"Hello, ($name)!"
  if $caps { $msg | str uppercase } else { $msg }
}

def main [] {
  print (greet "nushell")
  print (greet "world" --caps)
}
