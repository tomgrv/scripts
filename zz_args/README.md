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
