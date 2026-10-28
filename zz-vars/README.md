<!-- @format -->

# zz-vars

Show, ask and resolve the inputs workspaces declare (`config.ports` too: each `{name, port, access}` is the input `<NAME>_PORT`, defaulting to its port; `config.inputs`, keyed by
variable, and `config.input`, the deprecated array form; `config.output` filters what is printed). Used by `zz-setup` and `zz-call`; `zz-vars` stops at the `export` lines, running a command is `zz-call`'s.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `zz-vars`.

## Usage

<!-- prettier-ignore -->
```sh
zz-vars [-S] [-n | -a] [-m] [-e] -f <envfile> [-P profile] <name>=<dir>...
eval "$(zz-vars -f .env -P myprofile a=packages/a b=packages/b)"
```

- `-S` status only: each input as `set`, `required` or `optional`.
- Otherwise, on a terminal, offers to set unset inputs (`zz-menu`, then
  `zz-persist`, secrets masked), resolves every input with `zz-call` (caller's
  environment, env file, default) and prints the `export` lines to `eval`.
- `-n` never asks (defaults, required not enforced); `-a` asks each unset input on stdin without the menu; `-e` also persists values already in the environment.
- `-m` shows the menu even when every input is set (to change or delete a saved value).
- The menu lists each input as `[set|req|opt] x name - description` under the step that declares it (the menu's `-g`), `x` being the source: `f` file, `e` env, `E` env overriding a different saved value, `d` default, `-` unset; item `0` resets a saved value (it falls back to its default). It only runs when `zz-interactive` says so (`ZZ_INTERACTIVE=0` keeps it off).
- Exits 1 when a required input is still empty (or an input name is not a shell identifier). `q` in the menu leaves it and proceeds with what is set (the menu never aborts the run); Enter validates.

## Tests

```sh
bats test.bats
```

## Deleting a saved value

On a terminal the inputs menu shows a saved value with source `f` and starts with item **0, Reset a saved value...**: it lists the inputs stored in the env file (and the profile snippet), and the one you pick is forgotten, so its default applies again. A secret is only deleted after a `y` to the confirmation. A value that comes from the caller's environment is not touched. The menu only appears while an input is unset; `-m` shows it anyway, to change or delete a value when everything is set.
