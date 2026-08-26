# zz_dispatch

Dispatch an underscore-prefixed caller to a sibling `<name>-<subcmd>` script.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `zz_dispatch`.

## Usage

```sh
zz_dispatch <caller> <subcmd> [args...]
```

Example: a script named `_foo.sh` that wants to fan out to sibling
`foo-<subcmd>` scripts invokes `zz_dispatch "$0" "$@"`.

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```
