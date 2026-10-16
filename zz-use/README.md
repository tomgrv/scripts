<!-- @format -->

# zz-use

Activator: on-demand dependency management (apt/download, and single-shot zz-* bundle install).

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `zz-use`.

## Usage

```sh
zz-use "<tool>" [tool...]
zz-use [tool...] -x "<tool>" [arg...] # install <tool>, then exec it
```

## Dependencies

Declared in `package.json` `peerDependencies` (installed recursively,
from the same origin/ref as the script when it ships them). npm packages
a script only runs through `npx`/`zz-npx` go in `dependencies`, which
`zz-use` ignores. `config/zz-use.json` entries may carry a `sha256` (a
single hash, or an object keyed `<os>_<arch>`) verified before install.

Environment: `ZZ_CACHE_TTL` (minutes, default 1440, `0` = never) sets
when a cached archive for a mutable ref (branch, npm `latest`) is
refetched; tags and commit shas never expire.

## Tests

```sh
bats test.bats
```

- skips a tool already on PATH, reporting "already available"
- requires at least one tool argument
- prints its usage error even when zz-log isn't resolvable yet
- rejects an unknown option instead of treating it as a tool name
- installs a functional script individually, not the whole set
- installs a single zz-* tool individually, not the whole set
- errors with "Unable to provide required dependency" when a tool can't be resolved
- `--force` re-installs a zz-* tool even when already on PATH
- recognizes `--force` after a tool name, not just as the first arg
- resolves a functional script's `config/` folder alongside it
- `-x` installs the target and execs it, passing arguments through
- `-x` propagates the exec'd command's exit status
- `-x` resolves leading dependencies before installing/exec'ing the target
- `-x` strips an `[org/repo/]` prefix from the exec target's command name
- `-x` without a tool name errors
- persists a script's zz-* peers, not just the scratch boot-dir copies
- resolves a local-origin script's peers from that same origin
- keeps a glob's origin for every match
- skips a pinned re-request whose install stamp matches
- verifies a download's sha256, rejecting a mismatch
