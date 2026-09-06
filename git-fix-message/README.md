<!-- @format -->

# git-fix-message

Rewrite an arbitrary commit message.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `git-fix-message` (invoke via `git fix-message`, since
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
- refuses to run with uncommitted changes
- rejects an invalid commit sha
- errors when the given commit isn't an ancestor of HEAD
- rewrites the message of an arbitrary (non-HEAD) commit, preserving
  history length and file content
- aborts when the user declines the confirmation prompt
