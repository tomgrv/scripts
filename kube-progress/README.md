<!-- @format -->

# kube-progress

Run a command, logging the pod status of a namespace while it works.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `kube-progress`.

## Usage

```sh
kube-progress [-i seconds] <namespace> <label> <command...>

kube-progress -i 30 cattle-system "Rancher install" helm upgrade --install rancher rancher/rancher --wait
```

Runs the command as is (its output and exit status untouched) and, while it works, logs a status line every `-i` seconds (default `PROGRESS_INTERVAL`, else 15): elapsed time, pods ready/total in the namespace and what the others are doing (`ContainerCreating`, `ImagePullBackOff`...), so a long `helm --wait` or `kubectl rollout status` does not look frozen. Needs `kubectl`.

## Dependencies

Declared via `zz-use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- errors without a namespace, a label and a command
- logs elapsed time and pod states while the command runs, keeps its output
- returns the command's exit status and stops reporting afterwards
- says so when the namespace has no pod yet
