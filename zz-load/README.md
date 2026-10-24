<!-- @format -->

# zz-load

Read from a URL, a file, a literal argument, or stdin.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `zz-load`.

## Usage

```sh
zz-load [-r] [file|url|literal]
```

- `-r` requires a file or URL: a missing path is an error, not a literal.
- An `http(s)://` argument is downloaded (`curl -fsSL`, so an HTTP error fails).
- No argument reads stdin; on a terminal it prints usage instead of waiting.

```sh
# examples
zz-load notes.txt
zz-load -r https://example.com/x.json
```

## Dependencies

Declared via `zz-use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- reads a literal argument, a file argument, a URL, or stdin (when no argument given)
- a non-existent path is treated as a literal string, not an error
- reading a file logs which file it read from, to stderr
- multi-line file content is preserved
- an empty literal argument falls back to reading stdin
- `-r` errors on a missing file, on an empty source, and fails on a failed download
