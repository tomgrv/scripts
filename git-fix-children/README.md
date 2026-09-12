<!-- @format -->

# git-fix-children

Delete all descendant tags and branches of a commit.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `git-fix-children` (invoke via `git fix-children`, since
git resolves any `git-*` executable on `PATH` as a subcommand).

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- `-h` prints usage; fails cleanly outside a git repository
- with no descendant tags or branches, succeeds cleanly
- deletes descendant tags and branches, but preserves current/main/master
- without `-p`, warns that remote deletions were not pushed
- `-p` pushes tag deletions to the remote
