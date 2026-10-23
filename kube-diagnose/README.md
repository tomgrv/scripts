<!-- @format -->

# kube-diagnose

Show what is stuck in a Kubernetes namespace.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `kube-diagnose`.

## Usage

```sh
kube-diagnose <namespace>

kube-diagnose cattle-system
```

Prints, for a failed wait: pods and services, recent events, the k3s ServiceLB pods (a LoadBalancer Service whose host ports are taken stays pending there) and why each unready pod is not running. Needs `kubectl`; always exits 0.

## Dependencies

Declared via `zz-use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- errors without a namespace
- shows pods, events, and why an unready pod or a ServiceLB pod is stuck
