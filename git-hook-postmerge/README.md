<!-- @format -->

# git-hook-postmerge

Git `post-merge` hook. If the merge changed `package-lock.json` or
`composer.lock`, keeps the merged-in ("theirs") version staged and prints
a reminder to reinstall dependencies.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `git-hook-postmerge` (invoke via
`git hook-postmerge`, since git resolves any `git-*` executable on `PATH`
as a subcommand). Wire it up as `.git/hooks/post-merge` (directly, or via
husky) calling `git hook-postmerge "$@"`.

## Usage

```sh
git-hook-postmerge <squash>
```

`<squash>` matches what git passes to a `post-merge` hook (`1` if the
merge was a squash merge, `0` otherwise).

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```
