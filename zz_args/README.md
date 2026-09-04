# zz_args

Parse $@ per a heredoc spec, print eval-able var=value assignments.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `zz_args`.

## Usage

```sh
eval $(zz_args "<title>" "$0" "$@" <<-help
<argname> <datatype> <varname> <help>
help
)
```

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- flags with values, positionals, and defaults all eval into the right vars
- `-h`/`--help`-style usage exits 1 and prints the title plus per-arg help text
- unknown option doesn't silently succeed as if it were valid
- `+` collects remaining args as one space-joined var, `#` as escaped tokens
- values containing quotes or spaces round-trip safely through eval
- `-` (no datatype) sets a boolean-style marker var
- no arguments at all prints usage and returns non-zero
