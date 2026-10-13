<!-- @format -->

# zz-run

Fetch a GitHub `org/repo` and run its setup entrypoint — the generic version
of what `vps-setup` does for
[`perspikapps/vps`](https://github.com/perspikapps/vps).

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `zz-run`.

## Usage

```sh
zz-run <org>/<repo>[@<ref>] [options]

zz-run perspikapps/vps                       # menu on a terminal
sudo zz-run perspikapps/vps --skip-vps-rancher
sudo zz-run perspikapps/vps --only-vps-k3s
```

Same flow as `vps-setup`:

1. Shallow-clones the repo into `<dir>/<repo>` (or fast-forwards an existing
   checkout). Installs `git`/`jq` through `zz-install` when missing.
2. If the root `package.json` lists `workspaces`, proposes the runnable ones
   (those with a `run.sh`; when any workspace has a `vps` key, only those).
   A `zz-menu` cycles each through `skip → up → down`; `vps.order` sorts,
   `vps.default` preselects. Workspaces named in `dependencies` /
   `peerDependencies` are enabled automatically; `--down-<n>` is refused while
   a dependent is up (`--force-down` overrides).
3. Lists the inputs the selected workspaces declare (`vps.inputs`, or
   `config.input` as in `zz-call`), shows which are set, and offers to set
   them; answers are persisted to the env file and reloaded on the next run.
   Remaining defaults are applied; a required input left empty only warns.
4. Runs `down` steps in reverse order, then `up` steps in order, each
   `run.sh` getting `up`/`down` (workspaces with a `vps` key only).

No workspaces (or `ZZ_RUN_ENTRY` set): execs the repo's entrypoint with the
remaining arguments — first match of `$ZZ_RUN_ENTRY`, `<repo>-setup/run.sh`,
`setup.sh`, `run.sh`.

Without a terminal, use flags: `--skip-<n>`, `--with-<n>`, `--only-<n>`
(repeatable, overrides the others), `--down-<n>`, `--down-all`,
`--force-down`, `-h`. Supply inputs as environment variables.

`--status` shows each workspace's resulting state and every declared input
as `set` / `required` / `optional`, then exits without running anything.
Inputs declared `"secret": true` are read without echo.

| Variable          | Default                                           |
| ----------------- | ------------------------------------------------- |
| `ZZ_RUN_REF`      | `main` (`@<ref>` wins)                            |
| `ZZ_RUN_DIR`      | `/opt` as root, else `~/.local/share`             |
| `ZZ_RUN_URL_BASE` | `https://github.com`                              |
| `ZZ_RUN_ENTRY`    | forces entrypoint mode; path relative to checkout |
| `ZZ_RUN_ENV_FILE` | `/etc/<repo>.env` as root, else `<checkout>/.env` |

`sudo` drops exported variables: put them on the `sudo` line.

## Tests

```sh
bats test.bats
```
