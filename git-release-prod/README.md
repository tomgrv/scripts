<!-- @format -->

# git-release-prod

Finish a release or hotfix branch using Git Flow.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `git-release-prod` (invoke via `git release-prod`, since
git resolves any `git-*` executable on `PATH` as a subcommand).

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- `-h` prints usage and exits non-zero
- fails when there is no release or hotfix branch to finish
- finishes the current release branch: bumps changelog, merges, tags and cleans up
- fails when the working directory is not clean
- refuses to pick a branch when multiple release branches exist
- prefers a checked-out hotfix branch over an ambiguous discovery
- is idempotent: resuming after the finish tag already exists only runs cleanup
- fails cleanly outside a git repository
