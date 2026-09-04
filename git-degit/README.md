<!-- @format -->

# git-degit

Clone and degit a repository.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `git-degit` (invoke via `git degit`, since
git resolves any `git-*` executable on `PATH` as a subcommand).

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- no arguments and `-h` both print usage (no args exits non-zero)
- an unsupported host is rejected without attempting a download
- degits a github repo URL into the current directory by default
- degits into a given target directory, creating it if needed
- recognizes gitlab.com and bitbucket.org hosts
- strips a trailing `.git` suffix from the reported repository name
