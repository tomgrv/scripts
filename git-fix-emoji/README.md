<!-- @format -->

# git-fix-emoji

Fix git emoji.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `git-fix-emoji` (invoke via `git fix-emoji`, since
git resolves any `git-*` executable on `PATH` as a subcommand).

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- `-h` prints usage and exits non-zero
- fails cleanly outside a git repository
- refuses to run with uncommitted changes, leaving the working tree untouched
