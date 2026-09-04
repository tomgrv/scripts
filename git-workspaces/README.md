<!-- @format -->

# git-workspaces

List workspace directories and affected workspaces.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `git-workspaces` (invoke via `git workspaces`, since
git resolves any `git-*` executable on `PATH` as a subcommand).

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- help/usage output and exit code
- falls back to listing all top-level directories with no `package.json`
- lists directories matching `package.json` workspaces globs
- lists a literal (non-glob) workspace entry
- `-r` reports only workspaces touched within a commit range
- `-r` prints nothing when the range touches no workspace
