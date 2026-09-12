<!-- @format -->

# git-fix-up

Amend the specified commit with current changes and rebase.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `git-fix-up` (invoke via `git fix-up`, since
git resolves any `git-*` executable on `PATH` as a subcommand).

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- `-h` prints usage and exits non-zero
- refuses when a lock file is staged
- refuses when nothing is staged
- creates a fixup commit for the target and autosquashes it in, folding
  the staged content into the target commit with history length preserved
