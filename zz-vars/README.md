<!-- @format -->

# zz-vars

Show, ask and resolve the inputs workspaces declare (`config.ports` too: each `{name, port, access}` is the input `<NAME>_PORT`, defaulting to its port; `config.inputs`, keyed by
variable, and `config.input`, the deprecated array form; `config.output` filters what is printed). Used by `zz-setup` and `zz-call`; `zz-vars` stops at the `export` lines, running a command is `zz-call`'s.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `zz-vars`.

## Usage

<!-- prettier-ignore -->
```sh
zz-vars [-S] [-n | -a] [-e] -f <envfile> [-P profile] <name>=<dir>...
eval "$(zz-vars -f .env -P myprofile a=packages/a b=packages/b)"
```

- `-S` status only: each input as `set`, `required` or `optional`.
- Otherwise, on a terminal, offers to set unset inputs (`zz-menu`, then
  `zz-persist`, secrets masked), resolves every input with `zz-call` (caller's
  environment, env file, default) and prints the `export` lines to `eval`.
- `-n` never asks (defaults, required not enforced); `-a` asks each unset input on stdin without the menu; `-e` also persists values already in the environment.
- Exits 1 when a required input is still empty (or an input name is not a shell identifier), 3 when the user aborted.

## Tests

```sh
bats test.bats
```
