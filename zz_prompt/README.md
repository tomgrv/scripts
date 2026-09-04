# zz_prompt

Interactive free-form input with an optional default.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `zz_prompt`.

## Usage

```sh
value=$(zz_prompt "Question?" [default])
```

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

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
