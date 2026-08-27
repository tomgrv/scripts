# resolve-context

Resolve a feature's source/target directories from the calling script.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `resolve-context`.

## Usage

```sh
resolve-context [-s source] [-t target] [caller]
```

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```
