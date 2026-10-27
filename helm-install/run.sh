#!/bin/sh
# helm-install [-t timeout] <namespace> <release> <chart> [helm args...] — install or
# upgrade a Helm release: ensure the namespace, forget the record of a release an earlier
# attempt left failed (its resources are kept), run `helm upgrade --install` with progress
# lines (kube-progress), and print what is stuck (kube-diagnose) when it fails.
# Everything after the chart goes to helm (--values, --set, --version, --wait...).

. zz-colors

eval "$(
    zz-args "Install or upgrade a Helm release with progress and diagnostics" "$0" "$@" <<help
t timeout timeout helm --timeout (default 10m)
- namespace namespace Kubernetes namespace (created when missing)
- release release Helm release name
- chart chart Chart reference or directory
# helmargs helmargs Arguments for helm upgrade --install
help
)"

if [ -z "$namespace" ] || [ -z "$release" ] || [ -z "$chart" ]; then
    zz-log e "Usage: helm-install [-t timeout] <namespace> <release> <chart> [helm args...]"
    exit 1
fi

kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f - >/dev/null || exit 1

# A release left "failed" by an earlier attempt makes `helm upgrade` choke on resources it
# lists but that are gone. Forget the record only: `helm uninstall` would delete what it lists.
status=$(helm status "$release" -n "$namespace" -o json 2>/dev/null | jq -r '.info.status // empty') || status=""
if [ -n "$status" ] && [ "$status" != "deployed" ]; then
    zz-log w "Dropping the record of the $status $release release from an earlier attempt (resources are kept)."
    kubectl -n "$namespace" delete secret -l "owner=helm,name=$release"
fi

rc=0
kube-progress "$namespace" "$release install" \
    helm upgrade --install "$release" "$chart" -n "$namespace" "$@" --timeout "${timeout:-10m}" || rc=$?
if [ "$rc" -ne 0 ]; then
    kube-diagnose "$namespace"
    exit "$rc"
fi
