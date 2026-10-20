<!-- @format -->

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

## Layout, operation output, inline colour

- Levels: `i` a step starts, `s` it is done, `n` a decision the tool made for you,
  `w` degraded but the run continues, `e` the run stops (follow it with `-` lines
  saying what to do), `d` internals (needs `ZZ_DEBUG`), `-` a detail line, `o` command output.
- Headline levels (`i n w e s`) start at column 0. A `-` line or `o` output hangs under the
  headline above it behind a dim tree guide:
  ```
  → Fetching https://… at main
     |  Cloning into /opt/vps
     │ From https://…
  ✕ Could not fetch vps at nope
     |  @ref and ZZ_SETUP_REF set the ref of vps
  ```
- `ZZ_LOG_INDENT` is a nesting depth in levels (default 0, not spaces); each level adds a guide.
  Child scripts inherit it. Most callers never set it: a child's `-` lines already hang under the
  headline that started it.
- Level `o` is what a command printed (git, an installer): from the message or stdin, dimmed behind a
  `│` gutter, no pictogram.
- Any other level string is printed as the line's own prefix (as `json-validate` does).
- `{Name text}` prints `text` in the `zz-colors` variable `Name` (`{Purple x}`);
  a single capital is that style in the line's own colour (`{U path}`). No fork
  and no `eval` of the message: it runs on shell builtins (about 3× faster).
  Nested markers are not supported.

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
