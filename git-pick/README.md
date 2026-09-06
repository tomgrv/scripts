<!-- @format -->

# git-pick

Pick files from a specific commit.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `git-pick` (invoke via `git pick`, since
git resolves any `git-*` executable on `PATH` as a subcommand).

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- `-h` prints usage and exits non-zero
- restores current directory content from the given commit into the worktree and index
- restores only the given path when one is provided, leaving other files untouched
- defaults the path to the current directory relative to the repo root
- fails cleanly when given an invalid commit
- fails cleanly outside a git repository
