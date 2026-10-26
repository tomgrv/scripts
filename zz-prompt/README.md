<!-- @format -->

# zz-prompt

Interactive free-form input with an optional default.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `zz-prompt`.

## Usage

```sh
value=$(zz-prompt "Question?" [default])
```

## Dependencies

Declared via `zz-use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Options

- `-s` secret: masked input, default shown as `***`.
- `-e` exit 1 when input ends.

When stdin is not a terminal (for example under `curl ... | sh`) the answer is read from `/dev/tty` if one can be opened; `ZZ_PROMPT_TTY=0` disables this.
- `-c Yn` accept one of these letters (any case), re-ask on anything else; the
  uppercase letter is the default. It replaces the former `zz-ask`: `zz-prompt -c Yn "Continue?"`.

## Tests

```sh
bats test.bats
```

- empty input returns the given default
- entered input is returned as typed
- no default and empty input returns an empty string
- question and bracketed default are written to stderr, not stdout
- with no default, the bracketed default is omitted from the prompt text
- stdout carries only the value, cleanly separated from the prompt
