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

- `-c Yn` accept one of these letters (any case), re-ask on anything else; the
  uppercase letter is the default. It replaces the former `zz-ask`: `zz-prompt -c Yn "Continue?"`.

## Environment

| Variable                   | Effect                                                                                                                                                         |
| -------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ZZ_PROMPT_TTY=0`          | when stdin is not a terminal (for example under `curl ... \| sh`) do not read `/dev/tty`                                                                       |
| `ZZ_PROMPT_ANSWERS=<file>` | scripted answers: one line per prompt, an empty line is a bare Enter, an exhausted file is end of input; `zz-menu` asks through `zz-prompt`, so it follows too |

```sh
printf 'y\n\n' >answers
ZZ_PROMPT_ANSWERS=answers zz-prompt -c yN "Continue?"   # prints y
```

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
