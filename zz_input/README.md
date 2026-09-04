# zz_input

Read from a literal argument, a file argument, or stdin.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `zz_input`.

## Usage

```sh
zz_input [file|literal]
```

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- reads a literal argument, a file argument, or stdin (when no argument given)
- a non-existent path is treated as a literal string, not an error
- reading a file logs which file it read from, to stderr
- multi-line file content is preserved
- an empty literal argument falls back to reading stdin
