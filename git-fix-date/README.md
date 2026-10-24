<!-- @format -->

# git-fix-date

Fix commit dates and times in git history.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `git-fix-date` (invoke via `git fix-date`, since
git resolves any `git-*` executable on `PATH` as a subcommand).

## Usage

```sh
git fix-date [-f] [-p] [-d] [-r <days>] [-s <start>] [-e <end>] [-b <before>] [-a <after>] <sha>
```

| Argument      | Effect                                                                            |
| ------------- | --------------------------------------------------------------------------------- |
| `-f`          | allow overwriting pushed history                                                  |
| `-p`          | push changes after rewriting history                                              |
| `-d`          | dry-run mode: output change plan without applying changes                         |
| `-r <days>`   | days of week to reschedule (default: 1,2,3,4,5 for Mon-Fri; 0=Sunday, 6=Saturday) |
| `-s <start>`  | start time for rescheduling (default: 08:00, HH:MM format)                        |
| `-e <end>`    | end time for rescheduling (default: 17:00, HH:MM format)                          |
| `-b <before>` | time to move first half commits to (default: 06:00, HH:MM format)                 |
| `-a <after>`  | time to move second half commits to (default: 20:00, HH:MM format)                |
| `<sha>`       | sha commit to fix from                                                            |

## Examples

```sh
git fix-date -d    # preview the change plan, change nothing
git fix-date -f    # default weekday rescheduling, asks for confirmation
git fix-date -f -r 0 -s 08:00 -e 20:00 -b 07:30 -a 20:30  # Sunday commits: first half to 07:30, second half to 20:30
```

Without options it reschedules Monday-Friday commits made between 08:00 and 17:00: the first half (08:00-12:30) moves to 06:00, the second half (12:30-17:00) to 20:00. A change plan is displayed and confirmation is asked before anything is rewritten:

```
=== Change Plan ===

a1b2c3d | 2024-03-04 09:00:00 → 2024-03-04 06:00:00 | Monday morning work
e4f5g6h | 2024-03-04 14:00:00 → 2024-03-04 20:00:00 | Monday afternoon work

=== End of Change Plan ===
```

## Notes

- The sequential order of commits is always preserved.
- Only the time is modified, never the date.
- History is rewritten with `git filter-branch`; use `-f` carefully, it allows overwriting pushed history.

## Dependencies

Declared via `zz-use` at the top of `run.sh` and resolved on demand
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
