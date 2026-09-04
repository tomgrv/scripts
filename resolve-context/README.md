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

- help/usage output and exit code
- resolves source/feature/target from an explicit caller path
- strips a trailing `_NNN` suffix from the feature name
- `-s` overrides the source derived from the caller path
- creates the target directory when it doesn't already exist
- defaults target under `/usr/local/share` when writable
