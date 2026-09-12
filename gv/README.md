<!-- @format -->

# gv

Call the `gitversion`/`docker-gitversion` CLI against this repo's
`.gitversion` configuration.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `gv`.

## Dependencies

Assumes a `docker-gitversion` (or `dotnet-gitversion`) wrapper is already on
`PATH` at `/usr/local/bin/docker-gitversion` — see
[`tomgrv/actions/setup-gitversion`](https://github.com/tomgrv/actions) or the
`gitversion` devcontainer feature in
[`tomgrv/devcontainer-features`](https://github.com/tomgrv/devcontainer-features),
either of which installs it alongside this script.

## Tests

```sh
bats test.bats
```
