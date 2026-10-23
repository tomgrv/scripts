<!-- @format -->

# kube-teardown

Uninstall a Helm release and delete its namespace.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `kube-teardown`.

## Usage

```sh
kube-teardown <namespace> <release>

kube-teardown coder coder
```

Uninstalls the release (waiting for it), then deletes the namespace without waiting. A release that is not there is only reported. Needs `helm` and `kubectl`.

## Dependencies

Declared via `zz-use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- errors without a namespace and a release
- uninstalls an existing release and deletes the namespace
- only warns for a release that is not installed, still deleting the namespace
