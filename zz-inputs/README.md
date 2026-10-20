<!-- @format -->

# zz-inputs

Show, ask and resolve the inputs workspaces declare (`config.inputs`, keyed by
variable, and `config.input`, the `zz-call` array). Used by `zz-setup`.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `zz-inputs`.

## Usage

```sh
zz-inputs [-S] -f <envfile> [-P profile] <name>=<dir>...
eval "$(zz-inputs -f .env -P myprofile a=packages/a b=packages/b)"
```

- `-S` status only: each input as `set`, `required` or `optional`.
- Otherwise, on a terminal, offers to set unset inputs (`zz-menu`, then
  `zz-persist`, secrets masked), resolves every input with `zz-call` (caller's
  environment, env file, default) and prints the `export` lines to `eval`.
- Exits 1 when a required input is still empty, 3 when the user aborted.

## Tests

```sh
bats test.bats
```
