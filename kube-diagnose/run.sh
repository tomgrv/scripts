#!/bin/sh
# kube-diagnose <namespace> — what is stuck in a namespace, for a failed wait:
# pods and services, recent events, the k3s ServiceLB pods (a LoadBalancer
# Service whose host ports are taken stays pending there) and why each unready
# pod is not running.

. zz-colors

eval "$(
    zz-args "Show what is stuck in a Kubernetes namespace" "$0" "$@" <<help
- namespace namespace Kubernetes namespace to inspect
help
)"

if [ -z "$namespace" ]; then
    zz-log e "Usage: kube-diagnose <namespace>"
    exit 1
fi

zz-log w "--- diagnostics for namespace $namespace ---"
kubectl -n "$namespace" get pods,svc -o wide 2>&1 || true
kubectl -n "$namespace" get events --sort-by=.lastTimestamp 2>&1 | tail -n 15 || true
kubectl -n kube-system get pods -o wide 2>&1 | grep -E 'NAME|svclb' || true
for pod in $(kubectl -n "$namespace" get pods --no-headers 2>/dev/null | awk '$3 != "Running" && $3 != "Completed" {print $1}'); do
    kubectl -n "$namespace" describe pod "$pod" 2>&1 | sed -n '/^Events:/,$p' | tail -n 8 || true
done
for pod in $(kubectl -n kube-system get pods --no-headers 2>/dev/null | awk '/svclb/ && $3 != "Running" {print $1}'); do
    kubectl -n kube-system describe pod "$pod" 2>&1 | sed -n '/^Events:/,$p' | tail -n 4 || true
done
zz-log w "--- end of diagnostics ---"
