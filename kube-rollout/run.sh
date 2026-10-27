#!/bin/sh
# kube-rollout [-t timeout] [-w] <namespace> <deployment> — wait for a Deployment's
# rollout with progress lines (kube-progress); when it does not finish, print what is
# stuck (kube-diagnose) and fail, or only warn with -w.

. zz-colors

eval "$(
    zz-args "Wait for a Deployment rollout with progress and diagnostics" "$0" "$@" <<help
t timeout timeout Rollout timeout (default 5m)
w - warn_flag Only warn when the rollout does not finish, and exit 0
- namespace namespace Kubernetes namespace
- deployment deployment Deployment name
help
)"

if [ -z "$namespace" ] || [ -z "$deployment" ]; then
    zz-log e "Usage: kube-rollout [-t timeout] [-w] <namespace> <deployment>"
    exit 1
fi

if kube-progress "$namespace" "$deployment rollout" kubectl -n "$namespace" rollout status "deploy/$deployment" --timeout "${timeout:-5m}"; then
    exit 0
fi
kube-diagnose "$namespace"
if [ -n "$warn_flag" ]; then
    zz-log w "$deployment did not become ready in time (see the diagnostics above)."
    exit 0
fi
zz-log e "$deployment did not become ready in time (see the diagnostics above)."
exit 1
