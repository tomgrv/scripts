# zz-update

Force a fresh download of the zz-* bundle, bypassing the local cache
(`ZZ_CACHE_DIR`, default `~/.cache/zz_scripts`), and re-link the core
`zz-*` scripts from it. Equivalent to `zz-use --force <core zz-*>`.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `zz-update`.

## Usage

```sh
zz-update
```

No-op download-wise (and a no-network fast path) when run from a local
checkout of this repo: `zz-use` always installs the bundle straight from
disk there, ignoring the cache entirely.

## Tests

```sh
bats test.bats
```

- re-links the zz-* bundle from a local checkout without touching the network
- force re-installs every core zz-* script, bypassing the already-available skip
- makes no `curl` call at all when run from a local checkout
