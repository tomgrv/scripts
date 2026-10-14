<!-- @format -->

# zz-setup

Fetch a GitHub `org/repo` and run its setup entrypoint — the generic version
of what `vps-setup` does for
[`perspikapps/vps`](https://github.com/perspikapps/vps).

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `zz-setup`.

## Usage

```sh
zz-setup <org>/<repo>[@<ref>] [options]

zz-setup perspikapps/vps                       # menu on a terminal
sudo zz-setup perspikapps/vps -s vps-rancher
sudo zz-setup perspikapps/vps -o vps-k3s
sudo zz-setup perspikapps/vps -w vps-k3s,vps-rancher
```

Same flow as `vps-setup`:

1. Shallow-clones the repo into `<dir>/<repo>` (or fast-forwards an existing
   checkout). Installs `git`/`jq` through `zz-install` when missing.
2. If the root `package.json` lists `workspaces`, proposes the runnable ones
   (those with a `run.sh`; when any workspace has a `vps` key, only those).
   A `zz-menu` cycles each through `skip → up → down`; `vps.order` sorts,
   `vps.default` preselects. Workspaces named in `dependencies` /
   `peerDependencies` are enabled automatically; `-d` is refused while
   a dependent is up (`-F` overrides).
3. Lists the inputs the selected workspaces declare (`vps.inputs`, or
   `config.input`), shows which are set, and offers to set them with
   `zz-persist -i` (masked for `"secret": true`, current value shown and kept
   on enter). Then `zz-call -n -e` resolves them all: the caller's
   environment first (also persisted), then the env file, then the default.
   The env file is plain `KEY=VALUE`, created owner-only by `zz-persist` and read literally,
   never sourced. A required input left empty only warns.
4. Runs `down` steps in reverse order, then `up` steps in order, each
   `run.sh` getting `up`/`down` (workspaces with a `vps` key only).

No workspaces (or `ZZ_SETUP_ENTRY` set): execs the repo's entrypoint with the
remaining arguments — first match of `$ZZ_SETUP_ENTRY`, `<repo>-setup/run.sh`,
`setup.sh`, `run.sh`.

Options come after the repository and are parsed with `zz-args`; each list
takes space- or comma-separated workspace names:

| Option | Effect |
| ------ | ------ |
| `-w <names>` | enable workspaces |
| `-s <names>` | skip workspaces |
| `-d <names>` | bring workspaces down |
| `-o <names>` | run ONLY these (overrides `-w`/`-s`/`-d`) |
| `-D` | bring every workspace down |
| `-F` | allow `-d` while a dependent stays enabled |
| `-S` | show each workspace's state and every declared input as `set` / `required` / `optional`, run nothing |
| `-h` | help (lists the workspaces) |

No options on a terminal opens the menu. Supply inputs as environment
variables when there is no terminal.


| Variable          | Default                                           |
| ----------------- | ------------------------------------------------- |
| `ZZ_SETUP_REF`      | `main` (`@<ref>` wins)                            |
| `ZZ_SETUP_DIR`      | `/opt` as root, else `~/.local/share`             |
| `ZZ_SETUP_URL_BASE` | `https://github.com`                              |
| `ZZ_SETUP_ENTRY`    | forces entrypoint mode; path relative to checkout |
| `ZZ_SETUP_ENV_FILE` | `/etc/<repo>.env` as root, else `<checkout>/.env` |
| `ZZ_SETUP_PROFILE`  | unset; a name also exports persisted inputs from `/etc/profile.d/<name>.sh` |

`sudo` drops exported variables: put them on the `sudo` line.

## Tests

```sh
bats test.bats
```
