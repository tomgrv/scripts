<!-- @format -->

# git-fix-date

Fix commit dates and times in git history.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `git-fix-date` (invoke via `git fix-date`, since
git resolves any `git-*` executable on `PATH` as a subcommand).

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- `-h` prints usage; fails cleanly outside a git repository
- refuses to run with uncommitted changes present
- rejects invalid `-s`/`-e`/`-b`/`-a` time formats
- `-d` dry-run reports the reschedule plan without rewriting history
- reschedules commits in the first/second half of the range to the before/after time
- leaves commits outside the configured days/time range untouched
- an sha argument limits rescheduling to commits made after it
- declining the confirmation prompt cancels without rewriting history
