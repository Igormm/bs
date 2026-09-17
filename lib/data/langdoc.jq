# BS langdoc filter: parse `# @description` doc-comment blocks into JSON.
# Used by lib/data/langdoc.sh: jq -Rs --arg file NAME -f langdoc.jq FILE
# Emits one compact JSON object per documented function.

# Function name from a definition line: `name() {`, `name () {`,
# `function name {`, `function name() {`. Null when not a definition.
def fnname:
  (capture("^\\s*function\\s+(?<n>[A-Za-z0-9_:]+)") // capture("^\\s*(?<n>[A-Za-z0-9_:]+)\\s*\\(\\)\\s*\\{?"))
  | if . then .n else null end;

# Convert a doc-comment block (array of "# ..." lines) into metadata.
def docmeta:
  reduce .[] as $line (
    {description: "", returns: "", stdout: "", example: "", deprecated: false, params: [], cur: ""};
    if ($line | test("^#\\s*@[A-Za-z]+")) then
      ($line | capture("^#\\s*@(?<t>[A-Za-z]+)\\s*(?<v>.*)")) as $m
      | .cur = $m.t
      | if $m.t == "description" then .description = $m.v
        elif $m.t == "return" then .returns = $m.v
        elif $m.t == "stdout" then .stdout = $m.v
        elif $m.t == "example" then .example = $m.v
        elif $m.t == "param" then .params += [$m.v]
        elif $m.t == "deprecated" then .deprecated = true
        else . end
    elif ($line | test("^#\\s{3,}")) then
      ($line | capture("^#\\s{3,}(?<v>.*)")) as $m
      | if .cur == "description" then .description += "\n" + $m.v
        elif .cur == "return" then .returns += "\n" + $m.v
        elif .cur == "stdout" then .stdout += "\n" + $m.v
        elif .cur == "example" then .example += "\n" + $m.v
        else . end
    else . end)
  | .example |= sub("^\\n"; "")
  | .params = [.params[] | (split(" ") as $p | {name: $p[0], desc: ($p[1:] | join(" "))})]
  | {description: .description, params: .params, returns: .returns,
     stdout: .stdout, example: .example, deprecated: .deprecated};

# Walk the file: accumulate column-0 comment lines; when a function
# definition follows a comment block, emit a record for it.
split("\n")
| reduce .[] as $line (
    {doc: [], out: []};
    if ($line | startswith("#")) then
      .doc += [$line]
    elif (.doc | length) > 0 and
         ($line | test("^\\s*(function\\s+)?[A-Za-z0-9_:]+(\\s*\\(\\s*\\))?\\s*\\{?")) then
      .out += [{name: ($line | fnname), doc: .doc}]
      | .doc = []
    else
      .doc = []
    end)
| .out[]
| {name: .name, file: $file} + (.doc | docmeta)