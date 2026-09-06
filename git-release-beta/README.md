<!-- @format -->

# git-release-beta

Start a new release branch using Git Flow.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `git-release-beta` (invoke via `git release-beta`, since
git resolves any `git-*` executable on `PATH` as a subcommand).

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- creates and pushes a release branch named after the computed version
- is idempotent: re-running resumes an already-created release branch
- refuses to proceed when a different release branch already exists
- fails cleanly when the version cannot be computed
- fails cleanly outside a git repository
