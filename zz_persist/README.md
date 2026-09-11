# zz_persist

Upsert a `KEY=VALUE` pair into an env file and/or `/etc/profile.d`.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `zz_persist`.

## Usage

```sh
zz_persist [-f file] [-p profile] <key> <value>
zz_persist [-f file] [-p profile] -i "question" [-v default|-s default] <key>
```

At least one of `-f`/`-p` is required. Both are idempotent — running twice
replaces the existing entry instead of duplicating it.

With `-i`, the value is asked for interactively instead of being passed on
the command line (only when stdin is a terminal; otherwise the default is
used as-is, so non-interactive/piped runs still work). If the key is
already persisted, its current value is shown for reference and offered as
the default — as-is with `-v`, masked as `***` with `-s` since it's a
secret.

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- upserts `KEY=VALUE` into an env file, replacing an existing value on re-run
- appends a new key without disturbing existing entries
- creates the target file if it doesn't exist
- requires a key argument, and rejects an invalid variable name
- requires at least one of `-f`/`-p`
- writes an `export KEY=value` line to a `/etc/profile.d` snippet via `-p`
- can write to `-f` and `-p` simultaneously, and upsert replaces the profile.d export line
