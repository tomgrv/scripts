# zz_persist

Upsert a `KEY=VALUE` pair into an env file and/or `/etc/profile.d`.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `zz_persist`.

## Usage

```sh
zz_persist [-f file] [-p profile] <key> <value>
```

At least one of `-f`/`-p` is required. Both are idempotent — running twice
replaces the existing entry instead of duplicating it.

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```
