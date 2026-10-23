<!-- @format -->

# json-render

Fill the `${NAME}` placeholders of a JSON file and print the result, with every
value escaped for JSON, so a template never breaks on a quote, a backslash or a
newline in a value (what hand-built `printf`/`sed` templates get wrong).

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `json-render`, also reachable as `json render`.

## Usage

```sh
json-render <file> [NAME[=value] | NAME:=json]...

json-render body.json user='Ada "the" Lovelace' | curl -d @- "$url"
json-render body.json items:='["a","b"]' count:=3
json-render body.json user          # value taken from the environment
```

`NAME=value` inserts a string's content, escaped: write the template as
`"name": "${NAME}"`. `NAME:=json` inserts raw JSON (a number, an array, an
object), which must parse; write it unquoted: `"items": ${items}`. Only the
listed names are replaced; any other `${...}` is left as is. A name that is not
`[A-Za-z_][A-Za-z0-9_]*` is refused.

Sibling of [`yaml-render`](../yaml-render), which inserts values verbatim.

## Dependencies

Declared via `zz-use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list. `jq`
must be on `PATH`.

## Tests

```sh
bats test.bats
```

- help/usage output and exit code
- errors with no arguments or a missing file
- fills `NAME=value` pairs and variables from the environment
- escapes quotes, backslashes and newlines in a string value
- `NAME:=json` inserts raw JSON, and refuses invalid JSON
- leaves unlisted `${...}` text untouched; refuses an invalid name
- the output stays valid JSON for awkward values
