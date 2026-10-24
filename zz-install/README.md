<!-- @format -->

# zz-install

Install a system package with whichever package manager is available,
escalating through `sudo` when not root.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `zz-install`.

## Usage

```sh
zz-install [-m] [-r] [-f] <pkg>... | <pkg> [<manager>=<name>...]

zz-install jq
zz-install git-flow apk=gitflow-avh dnf=gitflow yum=gitflow \
    brew=git-flow-avh pacman=gitflow-avh
```

`-m` skips recommended packages (apt `--no-install-recommends`, dnf
`install_weak_deps=False`; other managers ignore it). `-r` removes the package
instead (apt purges, so its configuration goes too), with the same
`<manager>=<name>` overrides.

`-x <shell>` with `-u` runs the downloaded file with that shell instead of installing it (an installer script such as `get-helm-3`; curl retries the download five times).

With `-u <url>` it installs a downloaded binary instead, into the directory
`zz-bindir` resolves: `[-a tar.gz|tgz|tar.xz|zip] [-b binpath] [-v version] [-s sha256]`;
`{VERSION}`, `{OS}`, `{ARCH}` are expanded in `url`/`binpath`, and `sha256` is a
hash or a JSON object keyed `<os>_<arch>`. This is what `zz-use` calls for the
tools it downloads.

Several `<pkg>` may follow each other (`zz-install -m curl wget jq`); `<manager>=<name>` overrides apply to a single package. `<pkg>` is the default package name; append `<manager>=<name>` pairs where a `-f` upgrades every installed package first (apt update+upgrade, dnf/yum upgrade, zypper update...) and then installs; it cannot be combined with `-r` or `-u`.
manager names it differently. Managers, tried in order: `apt` (`apt-get`),
`apk`, `dnf`, `yum`, `brew`, `pacman`, `zypper`, `winget` (Git Bash on Windows, no root needed). Exits 1 when none is found,
or when root is needed and neither root nor `sudo` is available.

## Dependencies

Declared via `zz-use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- picks the first available manager and installs the default package name
- applies a `<manager>=<name>` override for the selected manager only
- ignores overrides for other managers
- goes through `sudo` when not root
- installs through `winget` by exact name (no root/sudo)
- fails without a package manager, or without root/sudo
