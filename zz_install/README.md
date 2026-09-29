<!-- @format -->

# zz_install

Install a system package with whichever package manager is available,
escalating through `sudo` when not root.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `zz_install`.

## Usage

```sh
zz_install <pkg> [<manager>=<name>...]

zz_install jq
zz_install git-flow apk=gitflow-avh dnf=gitflow yum=gitflow \
    brew=git-flow-avh pacman=gitflow-avh
```

`<pkg>` is the default package name; append `<manager>=<name>` pairs where a
manager names it differently. Managers, tried in order: `apt` (`apt-get`),
`apk`, `dnf`, `yum`, `brew`, `pacman`, `zypper`. Exits 1 when none is found,
or when root is needed and neither root nor `sudo` is available.

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- picks the first available manager and installs the default package name
- applies a `<manager>=<name>` override for the selected manager only
- ignores overrides for other managers
- goes through `sudo` when not root
- fails without a package manager, or without root/sudo
