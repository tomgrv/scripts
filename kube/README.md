<!-- @format -->

# kube

Dispatch to the `kube-<subcommand>` utilities, so `kube <subcommand>` and `kube-<subcommand>` are the same command.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `kube`.

## Usage

```sh
kube apply [-n namespace] <template> [KEY=VALUE...]   # kube-apply
kube rollout <namespace> <deployment>                  # kube-rollout
kube require | progress | diagnose | teardown | service-port
```

The `kube-*` names keep working. `helm-install` and `helm-repo` stay apart: `helm` is the real Helm binary.

## Tests

```sh
bats test.bats
```
