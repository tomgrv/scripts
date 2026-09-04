<!-- @format -->

# git-fix-del

Delete a specified commit and rebase subsequent history.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `git-fix-del` (invoke via `git fix-del`, since
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
- refuses to delete the initial (parentless) commit
- fails on an invalid/unknown sha
- deletes a middle commit and rebases descendants in auto mode, preserving
  surviving commits' order and content
