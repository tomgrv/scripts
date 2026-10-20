# zz-log

Colored, leveled log line on stderr (i/n/w/e/s/d/-).

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `zz-log`.

## Usage

```sh
zz-log <i|n|w|e|s|d|-> <message...>
```

Inside a GitHub Actions run (`GITHUB_ACTIONS=true`), `n`/`w`/`e` also emit a
leading `::notice::`/`::warning::`/`::error::` workflow-command line
(message only, `{Color text}` markup stripped, `%`/CR/LF percent-escaped
per GitHub's workflow-command syntax) ahead of the usual colored job-log
line, so the message surfaces as a PR/checks-UI annotation too. `i`/`s`/`-`
are never annotated, and outside Actions the annotation line is skipped
entirely.

`d` (debug) is silent unless `ZZ_DEBUG` is set (to any non-empty value), in
which case it prints like `-` but dimmed.

## Dependencies

Declared via `zz-use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Step, indent, operation output, library mode

- `ZZ_LOG_STEP` tags every script line with `[step]`; `ZZ_LOG_INDENT` indents it
  (a caller nesting a child raises it by 2). Both are inherited by children.
- Level `o` is what a command printed (git, an installer): from the message or
  stdin, dimmed behind a `│` gutter, no pictogram, no step tag.
- Sourced (`ZZ_LOG_LIB=1; . zz-log`) it only defines `zz_log <level> <msg...>`,
  which logs in the caller's shell with no fork per message. Run as a command
  it behaves as before.

## Tests

```sh
bats test.bats
```

- writes to stderr, never stdout
- each of i/n/w/e/s/d/- picks the right pictogram (→, i, !, ✕, ✔, ·, none)
- `d` (debug) prints only when `ZZ_DEBUG` is set, silent otherwise
- an unknown level falls back to printing the level string itself
- multiple message words are joined with spaces
- `{Color text}` inline highlight syntax is supported
- `n`/`e`/`w` prepend `::notice::`/`::error::`/`::warning::` when `GITHUB_ACTIONS=true`, stripped of `{Color text}` markup
- the annotation line percent-escapes `%`, CR, and LF per GitHub's workflow-command syntax
- no `::notice::`/`::error::`/`::warning::` line outside GitHub Actions, or for `i`/`s`/`-`
