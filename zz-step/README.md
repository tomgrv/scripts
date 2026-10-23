<!-- @format -->

# zz-step

Run the `up`, `down` or `summary` function of a `zz-setup` step. **Source it**
(`. zz-step`) at the end of the step's `run.sh`, after defining the functions:
it runs in the caller's shell, so it can call them.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `zz-step`.

## Usage

```sh
#!/bin/sh
set -eu

up() { ...; }
down() { ...; }
summary() { echo "..."; }

. zz-step
```

The action is the step's first argument (default `up`):

- `up`, `down`: first the step's `config.requires` (its `package.json`, beside the
  script) are checked with `zz-require`, then the function runs. `down` without a
  `down()` is an error.
- `summary`: runs `summary()` when the step has one, else prints nothing. No
  requirement is checked.
- anything else is an error.

## Dependencies

Declared via `zz-use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- `up` is the default action and runs `up()`
- `down` runs `down()`, and errors without one
- `summary` runs `summary()`, and prints nothing without one
- an unknown action is an error
- `config.requires` is enforced for `up` and `down`, not for `summary`
