<!-- @format -->

# kube-cert-manager

Install cert-manager unless it is already installed.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `kube-cert-manager`.

## Usage

```sh
kube-cert-manager [-v version]

kube-cert-manager -v v1.16.2
```

Installs cert-manager (with its CRDs) through Helm into the `cert-manager` namespace, logging progress through `kube-progress`; does nothing when the deployment exists. The chart version comes from `-v`, else `CERT_MANAGER_VERSION`, else the latest. Needs `helm` and `kubectl`.

## Dependencies

Declared via `zz-use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- does nothing when cert-manager is already installed
- installs the chart with CRDs and the pinned version
