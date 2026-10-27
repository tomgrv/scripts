#!/bin/sh
# kube-require [-d] [-H] [-k kubeconfig] — check that kubectl and helm (3.17 or later: the
# upstream charts use template functions older versions lack) are installed and
# print what the caller must evaluate, so a step needs no preflight of its own:
#   eval "$(kube-require)"        # exports KUBECONFIG, or logs and exits 1
#   eval "$(kube-require -d)"     # a teardown: logs and returns 0 when kubectl is missing
#   kube-require -H               # only: exit 0 when helm is installed and recent enough
# The messages go to stderr (zz-log); stdout carries only shell for eval.

. zz-colors

eval "$(
    zz-args "Check kubectl and helm and print the KUBECONFIG export for eval" "$0" "$@" <<help
H - helm_flag Only check helm: exit 0 when it is installed and 3.17 or later, else 1, nothing printed
d - down_flag Teardown mode: a missing kubectl is only a warning and the caller returns 0
k kubeconfig kubeconfig Kubeconfig to export (default: KUBECONFIG, else /etc/rancher/k3s/k3s.yaml)
help
)"

kubeconfig="${kubeconfig:-${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}}"

# helm_version: the installed helm's "major.minor", empty when there is none.
helm_version() {
    local v
    v="$(helm version --template '{{.Version}}' 2>/dev/null)" || return 0
    v="${v#v}"
    printf '%s.%s' "${v%%.*}" "$(printf '%s' "${v#*.}" | cut -d. -f1)"
}
# helm_recent: helm is 3.17 or later.
helm_recent() {
    local v major minor
    v="$(helm_version)"
    [ -n "$v" ] || return 1
    major="${v%%.*}" minor="${v#*.}"
    [ "$major" -gt 3 ] 2>/dev/null || { [ "$major" -eq 3 ] && [ "$minor" -ge 17 ]; } 2>/dev/null
}

if [ -n "$helm_flag" ]; then
    command -v helm >/dev/null 2>&1 && helm_recent
    exit $?
fi

if ! command -v kubectl >/dev/null 2>&1; then
    if [ -n "$down_flag" ]; then
        zz-log w "kubectl not found; nothing to remove."
        echo 'return 0'
    else
        zz-log e "kubectl not found; run svc-k3s/run.sh first."
        echo 'exit 1'
    fi
    exit 0
fi
if [ -z "$down_flag" ] && ! command -v helm >/dev/null 2>&1; then
    zz-log e "helm not found; run svc-k3s/run.sh first."
    echo 'exit 1'
    exit 0
fi
if [ -z "$down_flag" ] && ! helm_recent; then
    zz-log e "helm $(helm_version) is too old (3.17 or later is needed): remove it and re-run svc-k3s/run.sh."
    echo 'exit 1'
    exit 0
fi
printf "export KUBECONFIG='%s'\n" "$kubeconfig"
