<!-- @format -->

# helm-install

Install or upgrade a Helm release with progress lines and diagnostics.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `helm-install`.

## Usage

```sh
helm-install [-t timeout] <namespace> <release> <chart> [helm args...]

helm-install cattle-system rancher rancher-latest/rancher --values values.yaml --version 2.9
```

1. waits for the namespace to be gone when an earlier `down` is still deleting it (`Terminating`), then creates it when missing;
2. forgets the record of a release an earlier attempt left `failed` (its resources are kept: `helm uninstall` would delete them);
3. runs `helm upgrade --install` under [`kube-progress`](../kube-progress/README.md), with `--timeout` (default `10m`) after your arguments;
4. on failure runs [`kube-diagnose`](../kube-diagnose/README.md) and exits with helm's status.

Everything after the chart goes to helm (`--values`, `--set`, `--version`, `--wait`...). Needs `helm`, `kubectl` and `jq`.

## Dependencies

Declared via `zz-use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- needs a namespace, a release and a chart
- ensures the namespace, then upgrades with the helm arguments and the timeout
- forgets the record of a failed release, keeping its resources
- diagnoses and keeps helm's exit status on failure
