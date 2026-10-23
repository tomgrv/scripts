<!-- @format -->

# kube-service-port

Change the port of a Service's named port.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `kube-service-port`.

## Usage

```sh
kube-service-port <namespace> <service> <port-name> <new-port>

kube-service-port cattle-system rancher https 7083
```

Replaces the `port` of the Service's port called `<port-name>`; its `targetPort` stays. Exits 1, leaving the Service alone, when it has no port of that name. Needs `kubectl` and `jq`.

## Dependencies

Declared via `zz-use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- errors with missing arguments
- patches the named port
- leaves the Service alone when the port name is unknown
