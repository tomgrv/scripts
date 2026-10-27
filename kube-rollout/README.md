<!-- @format -->

# kube-rollout

Wait for a Deployment's rollout with progress lines, and print what is stuck when it does not finish.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `kube-rollout`.

## Usage

```sh
kube-rollout [-t timeout] [-w] <namespace> <deployment>

kube-rollout -t 10m cattle-system rancher
kube-rollout -w kube-system traefik     # only warn when it is not ready in time
```

Runs `kubectl rollout status` under [`kube-progress`](../kube-progress/README.md); on failure runs [`kube-diagnose`](../kube-diagnose/README.md) and exits 1 (exit 0 with `-w`). The timeout defaults to `5m`.

## Dependencies

Declared via `zz-use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- errors without a namespace and a deployment
- waits with the timeout and stays quiet on success
- diagnoses and fails when the rollout does not finish, or only warns with `-w`
