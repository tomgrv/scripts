# zz_log

Colored, leveled log line on stderr (i/w/e/s/-).

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `zz_log`.

## Usage

```sh
zz_log <i|w|e|s|-> <message...>
```

Inside a GitHub Actions run (`GITHUB_ACTIONS=true`), `w`/`e` also emit a
leading `::warning::`/`::error::` workflow-command line (message only,
`{Color text}` markup stripped, `%`/CR/LF percent-escaped per GitHub's
workflow-command syntax) ahead of the usual colored job-log line, so the
message surfaces as a PR/checks-UI annotation too. `i`/`s`/`-` are never
annotated, and outside Actions the annotation line is skipped entirely.

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- writes to stderr, never stdout
- each of i/w/e/s/- picks the right pictogram (→, !, ✕, ✔, none)
- an unknown level falls back to printing the level string itself
- multiple message words are joined with spaces
- `{Color text}` inline highlight syntax is supported
- `e`/`w` prepend `::error::`/`::warning::` when `GITHUB_ACTIONS=true`, stripped of `{Color text}` markup
- the annotation line percent-escapes `%`, CR, and LF per GitHub's workflow-command syntax
- no `::error::`/`::warning::` line outside GitHub Actions, or for `i`/`s`/`-`
