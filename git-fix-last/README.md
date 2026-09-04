<!-- @format -->

# git-fix-last

Edit the last commit message and content.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `git-fix-last` (invoke via `git fix-last`, since
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
- `-m` rewrites the last commit's message without adding a new commit
- rewriting the message leaves the commit's tree and file content intact
