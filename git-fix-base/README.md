<!-- @format -->

# git-fix-base

Rebase commits from one branch onto another.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `git-fix-base` (invoke via `git fix-base`, since
git resolves any `git-*` executable on `PATH` as a subcommand).

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- `-h` prints usage; missing target exits non-zero
- rejects a nonexistent target or source branch, and identical source/target
- `-n` dry-run lists the commits that would move without changing any branch
- with no unpushed commits, reports nothing to move and exits 0
- moves unpushed commits from source onto target and resets source to the merge base (with confirmation)
- declining the confirmation prompt cancels without changing any branch
- fails cleanly outside a git repository
