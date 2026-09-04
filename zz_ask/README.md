# zz_ask

Interactive single-character confirm/choice prompt.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `zz_ask`.

## Usage

```sh
choice=$(zz_ask "Yn" "Continue?")
```

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- empty input returns the default option
- a valid non-default answer is returned as-is
- typed case is preserved, not lowercased
- invalid input re-prompts (with a warning) until a valid option is given
- default is derived from whichever letter is uppercase, not the first char
- question and `[options]` prompt are written to stderr, not stdout
