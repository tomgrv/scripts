#!/bin/sh
# kube-teardown <namespace> <release> — uninstall a Helm release, then delete
# its namespace (without waiting for it). A release that is not there is only
# reported.

. zz-colors

eval "$(
    zz-args "Uninstall a Helm release and delete its namespace" "$0" "$@" <<help
- namespace namespace Namespace of the release (deleted afterwards)
- release release Helm release name
help
)"

if [ -z "$namespace" ] || [ -z "$release" ]; then
    zz-log e "Usage: kube-teardown <namespace> <release>"
    exit 1
fi

if helm status "$release" -n "$namespace" >/dev/null 2>&1; then
    zz-log i "Uninstalling Helm release $release (namespace $namespace)..."
    helm uninstall "$release" -n "$namespace" --wait || zz-log w "helm uninstall $release timed out or failed."
else
    zz-log w "Helm release $release not found in namespace $namespace; nothing to uninstall."
fi
kubectl delete namespace "$namespace" --ignore-not-found --wait=false >/dev/null 2>&1 || true
