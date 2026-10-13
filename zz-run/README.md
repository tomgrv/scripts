<!-- @format -->

# zz-run

Fetch a GitHub `org/repo` and run its setup entrypoint — the generic version
of what `vps-setup` does for
[`perspikapps/vps`](https://github.com/perspikapps/vps).

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `zz-run`.

## Usage

```sh
zz-run <org>/<repo>[@<ref>] [args...]

sudo zz-run perspikapps/vps --skip-vps-rancher
sudo zz-run perspikapps/vps@develop
```

Shallow-clones the repo into `<dir>/<repo>` (or fast-forwards an existing
checkout), then runs its entrypoint with the remaining arguments. Entrypoint,
first match wins: `$ZZ_RUN_ENTRY`, `<repo>-setup/run.sh`, `setup.sh`,
`run.sh`. Installs `git` through `zz-install` when missing.

| Variable          | Default                                           |
| ----------------- | ------------------------------------------------- |
| `ZZ_RUN_REF`      | `main` (`@<ref>` wins)                            |
| `ZZ_RUN_DIR`      | `/opt` as root, else `~/.local/share`             |
| `ZZ_RUN_URL_BASE` | `https://github.com`                              |
| `ZZ_RUN_ENTRY`    | auto-detected, path relative to the checkout      |

`sudo` drops exported variables: put them on the `sudo` line.

## Tests

```sh
bats test.bats
```
