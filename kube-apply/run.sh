#!/bin/sh
# kube-apply [-n namespace] <template> [KEY=VALUE...] — render a manifest template with
# yaml-render and kubectl apply it (KUBECONFIG defaults to k3s's).

. zz-colors

eval "$(
    zz-args "Render a manifest template and kubectl apply it" "$0" "$@" <<help
n namespace namespace Namespace to apply into (default: the manifest's own)
- template template Manifest template (yaml-render)
# vars vars KEY=VALUE substitutions (left in "$@")
help
)"

[ -n "$template" ] || {
    zz-log e "Usage: kube-apply [-n namespace] <template> [KEY=VALUE...]"
    exit 1
}

export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
yaml-render "$template" "$@" | kubectl apply ${namespace:+-n "$namespace"} -f -
