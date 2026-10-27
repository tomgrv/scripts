<!-- @format -->

# zz-setup

Fetch a GitHub `org/repo` and run its workspaces (or its setup entrypoint).

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `zz-setup`.

## Usage

```sh
zz-setup <org>/<repo>[@<ref>] [options]

zz-setup acme/tool                 # menu on a terminal
zz-setup acme/tool -w a,b          # enable workspaces
zz-setup acme/tool -o a            # run only a
```

1. Shallow-clones the repo into `<dir>/<repo>` (or fast-forwards an existing
   checkout). A local path (`./x`, `../x`, `/x`) is used in place.
2. Runnable workspaces are the root `package.json` workspaces that have a
   `bin` and an `engines.zz-setup` field (the run context, any value such as
   `"*"`); the bin file is what runs. An optional `config` holds their settings:

   ```json
   "bin": { "tool": "run.sh" },
   "engines": { "zz-setup": "*" },
   "config": { "order": 1, "default": true, "inputs": { "FOO": { "default": "bar" } } }
   ```

   `order` sorts, `default` preselects, `inputs` (or `config.input`) declares
   the variables resolved by `zz-vars` (`config.requires`, e.g. `{"root": true, "os": "ubuntu"}`, is checked with `zz-require` for every selected workspace before the first one runs; `config.ports`, a list of `{name, port, access}`, also gives each port a `<NAME>_PORT` input defaulting to the port; `summary: true` marks a bin that answers a `summary` action for `-m`) (environment, then env file, then
   default; required ones abort the run). Workspaces listed in
   `dependencies` / `peerDependencies` are enabled automatically.
   `conflicts` (names of other workspaces) marks workspaces that cannot run on
   the same host: if both end up enabled (explicitly or through a dependency),
   the run aborts before any step starts and names the pair, e.g.
   `"config": { "conflicts": ["k3s"] }`. Only `up` counts; the declaration need
   only be on one side.
3. Runs `down` steps in reverse order, then `up` steps in order; each
   bin gets `up` or `down`.

No runnable workspace (or `ZZ_SETUP_ENTRY` set): execs the first match of
`$ZZ_SETUP_ENTRY`, `<repo>-setup/run.sh`, `setup.sh`, `run.sh` with the
remaining arguments.

## Options

Lists are space- or comma-separated workspace names.

| Option       | Effect                                             |
| ------------ | -------------------------------------------------- |
| `-w <names>` | enable workspaces                                  |
| `-s <names>` | skip workspaces                                    |
| `-d <names>` | bring workspaces down                              |
| `-o <names>` | run ONLY these (overrides `-w`/`-s`/`-d`)          |
| `-D`         | bring every workspace down                         |
| `-F`         | allow `-d` while a dependent stays enabled         |
| `-y`         | do not ask to confirm the workspaces set to `down` in the menu |
| `-S`         | show workspace states and inputs, run nothing      |
| `-a <action>` | with `-o`: run this action (any argument the bin understands) instead of `up` |
| `-m`         | print the `summary` of each workspace declaring `config.summary: true`, run nothing (a normal run prints them after the last step, under a `<repo> summary` header line) |
| `-h`         | help (lists the workspaces)                        |

No options on a terminal opens the menu, preselected with the states of the last
run: every workspace's state is remembered in the env file before the run as
`ZZ_STATE_<name>=up|skip|down`, stored as is: a workspace whose `down` failed (or has not run yet) stays `down`, and one brought down successfully is remembered as `skip`, and the menu's choices are remembered as soon as they are confirmed.
Non-interactive runs without flags ignore it; with flags (`-w`, `-s`, `-d`, ...) the run starts from it and each flag only changes the workspaces it names. Supply inputs as environment
variables when there is no terminal (`sudo` drops them: put them on the
`sudo` line).

| Variable            | Default                                           |
| ------------------- | ------------------------------------------------- |
| `ZZ_SETUP_REF`      | `main` (`@<ref>` wins)                            |
| `ZZ_SETUP_DIR`      | `/opt` as root, else `~/.local/share`             |
| `ZZ_SETUP_URL_BASE` | `https://github.com`                              |
| `ZZ_SETUP_ENTRY`    | forces entrypoint mode; path relative to checkout |
| `ZZ_SETUP_ENV_FILE` | `/etc/<repo>.env` as root, else `<checkout>/.env` |
| `ZZ_SETUP_PROFILE`  | also export persisted inputs from `/etc/profile.d/<name>.sh` |

## Paths

`ZZ_SETUP_DIR` (checkout parent), `ZZ_ETC_DIR` (default `/etc`, root env file),
`ZZ_PROFILE_DIR` (default `/etc/profile.d`), `ZZ_BIN_DIR` (bin directory).

## Tests

```sh
bats test.bats
```

## Bins on PATH

Before it runs anything, `zz-setup` puts the `run.sh` of every workspace that has a `bin` (a step or not) on `PATH` under its folder name, through a local-path `zz-use`. A step can therefore call a sibling that is not a step, such as a shared helper, by name, without a `zz-use` line of its own. An installed bin is a copy, so `zz-setup` also exports `ZZ_SETUP_ROOT` (the checkout) for the bins that need to find the other workspaces, and `ZZ_SETUP_UP` (the names of the workspaces this run brings up, space-separated and padded with spaces) for the steps that only concern those.
