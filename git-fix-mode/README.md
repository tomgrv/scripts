<!-- @format -->

# git-fix-mode

Fix file mode changes from diff.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `git-fix-mode` (invoke via `git fix-mode`, since
git resolves any `git-*` executable on `PATH` as a subcommand).

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- does nothing (exit 0) when there is no mode diff
- reverts a tracked file's mode change back to what git recorded
- leaves deleted files alone
