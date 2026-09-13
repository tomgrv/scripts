<!-- @format -->

# git-hook-commitmsg

Git `commit-msg` hook. Installs commitizen/commitlint plugins via
`git-hook-installplugins`, applies `commitlint` rules to the commit
message git just wrote, then runs `devmoji` to prepend/rewrite its emoji.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `git-hook-commitmsg` (invoke via
`git hook-commitmsg`, since git resolves any `git-*` executable on `PATH`
as a subcommand). Wire it up as `.git/hooks/commit-msg` (directly, or via
husky) calling `git hook-commitmsg "$@"`.

## Usage

```sh
git-hook-commitmsg <msgfile>
```

`<msgfile>` is the path to the commit message file, as git passes it to a
`commit-msg` hook.

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```
