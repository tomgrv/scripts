<!-- @format -->

# kube-apply

Render a manifest template with [`yaml-render`](../yaml-render/README.md) and `kubectl apply` it.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `kube-apply`.

## Usage

```sh
kube-apply [-n namespace] <template> [KEY=VALUE...]

kube-apply helm/ingress.yaml INGRESS_HOST=rancher.example.com
kube-apply -n devcontainer-builder helm/registry.yaml registry_port=5000
```

`KUBECONFIG` defaults to `/etc/rancher/k3s/k3s.yaml`. Run [`kube-require`](../kube-require/README.md) first when the step must also check kubectl and helm are installed.

## Tests

```sh
bats test.bats
```
