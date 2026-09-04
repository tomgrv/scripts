<!-- @format -->

# git-align

Align the current branch with its remote counterpart.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `git-align` (invoke via `git align`, since
git resolves any `git-*` executable on `PATH` as a subcommand).

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- fails cleanly outside a git repository
- with no remote configured, logs a failure and leaves branch/history intact
- aligns the current branch to a newer remote commit, restoring stashed local edits
- preserves the branch name and leaves no leftover temp/stash branch
- aligns cleanly when there are no uncommitted changes to stash/pop
