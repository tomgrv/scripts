# zz_update

Force a fresh download of the zz_* bundle, bypassing the local cache
(`ZZ_CACHE_DIR`, default `~/.cache/zz_scripts`), and re-link the core
`zz_*` scripts from it. Equivalent to `zz_use --force <core zz_*>`.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `zz_update`.

## Usage

```sh
zz_update
```

No-op download-wise (and a no-network fast path) when run from a local
checkout of this repo: `zz_use` always installs the bundle straight from
disk there, ignoring the cache entirely.

## Tests

```sh
bats test.bats
```
