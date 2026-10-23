<!-- @format -->

# zz-persist

Upsert a `KEY=VALUE` pair into an env file and/or `/etc/profile.d`.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `zz-persist`.

## Usage

```sh
zz-persist [-f file] [-p profile] [-s] [-g length] <key> [value]
zz-persist [-f file] [-p profile] (-r | -u) <key>
zz-persist [-f file] [-p profile] [-s] -i "question" [-v default] <key>
```

| Option        | Meaning                                                                |
| ------------- | ---------------------------------------------------------------------- |
| `-f file`     | upsert `KEY=VALUE` into this env-style file                            |
| `-p profile`  | upsert `export KEY=VALUE` into `/etc/profile.d/<profile>.sh`           |
| `-i question` | ask for the value (terminal only; otherwise the default is used as-is) |
| `-v default`  | default offered by `-i`; a value already stored for the key wins       |
| `-s`          | the value is a secret (see below)                                      |
| `-q`          | do not log the write (for internal state)                              |
| `-g length`   | no value given or stored: generate `length` letters/digits, keep it once stored, print it on stdout |
| `-r`          | print the stored value of the key (empty when unset); nothing is written |
| `-u`          | remove the key from the file / profile                                 |

At least one of `-f`/`-p` is required. Both are idempotent: running twice
replaces the existing entry instead of duplicating it.

**Secrets (`-s`).** The prompt is masked, the stored value is shown as `***`
in the log, and the value is only written to an owner-only file: a target
that others can read is refused with a warning. Nothing else is implied: a
key is never treated as secret just because it already has a value.

**Files it creates.** A new env file (`-f`) is always created owner-only
(`600`), so a secret can be stored right away and later values can share the
file. A new profile.d snippet is owner-only only for a secret; otherwise every
shell must be able to source it.

## Dependencies

Declared via `zz-use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Environment

`ZZ_PROFILE_DIR` (default `/etc/profile.d`) is where `-p` writes. The env file
holds the value literally; a profile snippet is sourced by shells, so a value
with anything but plain characters is single-quoted there. Values are upserted
through `awk` (no character is interpreted) and a multi-line value is refused.
On a terminal, a secret aimed at a file that is not owner-only offers `chmod 600`
through `zz-prompt -c`.

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
