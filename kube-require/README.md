<!-- @format -->

# kube-require

Check that `kubectl` and `helm` (3.17 or later: the upstream charts use template functions older versions lack) are installed and print the `KUBECONFIG` export for the caller to evaluate.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `kube-require`.

## Usage

```sh
eval "$(kube-require)"           # exports KUBECONFIG, or logs and makes the caller exit 1
eval "$(kube-require -d)"        # a teardown: a missing kubectl is a warning, the caller returns 0
eval "$(kube-require -k /my/kubeconfig)"
```

The kubeconfig is `-k`, else `KUBECONFIG`, else `/etc/rancher/k3s/k3s.yaml`. Messages go to stderr; stdout carries only shell for `eval`.

## Dependencies

Declared via `zz-use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- prints the export for the default path, `KUBECONFIG` and `-k`
- makes the caller exit 1 when kubectl or helm is missing, or helm is older than 3.17
- `kube-require -H` only checks helm: exit 0 when it is installed and recent enough, nothing printed
- `-d` makes the caller return 0 when kubectl is missing
