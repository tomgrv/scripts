<!-- @format -->

# git-release-alpha

Squash-merge the current feature branch into develop.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `git-release-alpha` (invoke via `git release-alpha`, since
git resolves any `git-*` executable on `PATH` as a subcommand).

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- `-h` prints usage and exits non-zero
- fails when no message is provided, or when not on a `feature/xxx` branch
- squash-merges the feature branch into develop, scoping the commit message with the feature name
- marks the squash commit as breaking when a source commit uses the `!` convention
- with `-o`, uses the most occurring commit type for the squash commit
- restores stashed working-tree changes after finishing
- pushes develop to origin when `-p` is given
- fails cleanly outside a git repository
