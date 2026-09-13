<!-- @format -->

# git-hook-installplugins

Install npm plugins declared at a JSON key of a `package.json` (e.g.
`.prettier.plugins`, or commitizen/commitlint config), tracking what's
already known in a `PLUGINS` file next to this script so repeat runs skip
straight to `npm list`. Called by the other `git-hook-*` scripts before
running a tool that expects those plugins to already be installed.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `git-hook-installplugins` (invoke via
`git hook-installplugins`, since git resolves any `git-*` executable on
`PATH` as a subcommand).

## Usage

```sh
git-hook-installplugins [-f package.json] [-g] <json_key>
```

- `-f <file>` — package.json to read from (default: `./package.json`).
- `-g` — install plugins globally (`npm install -g`).
- `<json_key>` — a `jq` expression selecting the plugin name(s), e.g.
  `'.prettier.plugins//""'`.

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```
