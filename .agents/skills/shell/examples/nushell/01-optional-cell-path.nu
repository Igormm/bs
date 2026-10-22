# GOOD: use optional cell paths so a missing column yields null instead of a
# hard error. Static-checks clean with `nu --ide-check`.
#
# BAD (would error at runtime): `$user | get email` on a record without an
# `email` column raises "cannot find column". Shown here in prose, not as a
# committed file, because a failing example would break `task nushell`.

let user = {name: "ada"}

# Optional access — null instead of an error when the column is absent.
let email = ($user | get -o email)

print $"name=($user.name) email=($email | default 'none')"
