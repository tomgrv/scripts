<!-- @format -->

# helm-repo

Add and refresh Helm repositories.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `helm-repo`.

## Usage

```sh
helm-repo <name> <url> [<name> <url>...]

helm-repo bitnami https://charts.bitnami.com/bitnami jetstack https://charts.jetstack.io
```

Each repository is added with `--force-update` (an alias whose URL changed is replaced), then all of them are refreshed in one `helm repo update`. A failure names the URL. Only `http(s)` URLs: OCI charts need no repository.

## Dependencies

Declared via `zz-use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- needs name/url pairs
- adds every repository, then refreshes them once
- rejects a non-http URL and names the URL when the add fails
