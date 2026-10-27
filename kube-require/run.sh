#!/bin/sh
# kube-require [-d] [-k kubeconfig] — check that kubectl and helm are installed and
# print what the caller must evaluate, so a step needs no preflight of its own:
#   eval "$(kube-require)"        # exports KUBECONFIG, or logs and exits 1
#   eval "$(kube-require -d)"     # a teardown: logs and returns 0 when kubectl is missing
# The messages go to stderr (zz-log); stdout carries only shell for eval.

. zz-colors

eval "$(
    zz-args "Check kubectl and helm and print the KUBECONFIG export for eval" "$0" "$@" <<help
d - down_flag Teardown mode: a missing kubectl is only a warning and the caller returns 0
k kubeconfig kubeconfig Kubeconfig to export (default: KUBECONFIG, else /etc/rancher/k3s/k3s.yaml)
help
)"

kubeconfig="${kubeconfig:-${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}}"

if ! command -v kubectl >/dev/null 2>&1; then
    if [ -n "$down_flag" ]; then
        zz-log w "kubectl not found; nothing to remove."
        echo 'return 0'
    else
        zz-log e "kubectl not found; run vps-k3s/run.sh first."
        echo 'exit 1'
    fi
    exit 0
fi
if [ -z "$down_flag" ] && ! command -v helm >/dev/null 2>&1; then
    zz-log e "helm not found; run vps-k3s/run.sh first."
    echo 'exit 1'
    exit 0
fi
printf "export KUBECONFIG='%s'\n" "$kubeconfig"
