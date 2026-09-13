<!-- @format -->

# git-hook-postcheckout

Git `post-checkout` hook. Skips when `$GIT_COMMAND` is `rebase`.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `git-hook-postcheckout` (invoke via
`git hook-postcheckout`, since git resolves any `git-*` executable on
`PATH` as a subcommand). Wire it up as `.git/hooks/post-checkout`
(directly, or via husky) calling `git hook-postcheckout "$@"`.

## Usage

```sh
git-hook-postcheckout <prevhead> <newhead> <flag>
```

Arguments match what git passes to a `post-checkout` hook (`flag` is `1`
for a branch checkout, `0` for a file checkout).

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```
