<!-- @format -->

# git-release-hotfix

Create a hotfix branch using Git Flow.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `git-release-hotfix` (invoke via `git release-hotfix`, since
git resolves any `git-*` executable on `PATH` as a subcommand).

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- `-h` prints usage and exits non-zero
- fails when main has no version tag
- creates a hotfix branch without rebasing when commits are not all `fix:`
- creates a hotfix branch and rebases `fix:` commits from develop onto it, resetting develop to the tag
- is idempotent: resumes an already-created hotfix branch instead of failing
- refuses to rebase when develop has already been pushed to remote
- `-r` forces a rebase even when commits are not all `fix:`
- fails cleanly outside a git repository
