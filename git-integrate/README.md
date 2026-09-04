<!-- @format -->

# git-integrate

Integrate modifications from the remote repository.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `git-integrate` (invoke via `git integrate`, since
git resolves any `git-*` executable on `PATH` as a subcommand).

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- forces `core.autocrlf` to false
- reverts a modified file whose only diff is whitespace/CRLF
- stages a modified file with real content changes
- stages a new untracked file
- leaves a clean working tree untouched
- fails cleanly outside a git repository
