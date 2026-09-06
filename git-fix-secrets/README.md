<!-- @format -->

# git-fix-secrets

Redact a secret from files, commit messages and/or tag annotations across all git history.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `git-fix-secrets` (invoke via `git fix-secrets`, since
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
- requires a glob pattern and a secret value
- refuses to run with uncommitted changes
- reports no occurrences when the secret is absent, leaving files unchanged
- `-d` dry-run lists matches without modifying anything
- redacts a planted secret from tracked file content across all history
- aborts the rewrite when the user declines the confirmation prompt
- `-m` also redacts the secret from commit messages
