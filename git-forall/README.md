<!-- @format -->

# git-forall

Execute a command for all files in the repository.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `git-forall` (invoke via `git forall`, since
git resolves any `git-*` executable on `PATH` as a subcommand).

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- runs the command against every tracked and untracked (non-ignored) file
- excludes gitignored files
- invokes the command once per file, with the file as the final argument
- produces no output when there are no matching files
- fails cleanly outside a git repository
