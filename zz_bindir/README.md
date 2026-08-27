# zz_bindir

Resolve (and create if needed) a writable bin directory on PATH.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `zz_bindir`.

## Usage

```sh
eval "$(zz_bindir [-t target])"
```

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```
