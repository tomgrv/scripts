<!-- @format -->

# zz-workspaces

List the runnable workspaces of a package: those with a `bin` file that exists
and an `engines.zz-setup` field, sorted by `config.order`.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `zz-workspaces`. Used by `zz-setup`.

## Usage

```sh
zz-workspaces [<dir>]
```

One row per workspace, fields separated by `\037` (a tab would collapse empty
fields): `order name dir description default deps conflicts bin summary requires functions`. Names have
their `@scope/` removed; `deps` and `conflicts` are comma-separated. One `jq`
call per workspace. Prints nothing without a `package.json` or runnable
workspace.

## Tests

```sh
bats test.bats
```
