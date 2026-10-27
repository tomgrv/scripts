#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
    WORK=$(mktemp -d)
    CALLS="$WORK/calls"
    : >"$CALLS"
}

teardown() {
    rm -rf "$WORK"
    teardown_scripts_path
}

# stub_cluster <release status ("" for none)> <upgrade exit code>
stub_cluster() {
    printf '#!/bin/sh\necho "helm $*" >>"%s"\ncase "$1" in\nstatus) [ -n "%s" ] && echo "{\\"info\\":{\\"status\\":\\"%s\\"}}" || exit 1 ;;\nupgrade) exit %s ;;\nesac\n' "$CALLS" "$1" "$1" "$2" | stub_script helm
    printf '#!/bin/sh\necho "kubectl $*" >>"%s"\n' "$CALLS" | stub_script kubectl
    printf '#!/bin/sh\necho "diagnose $*" >>"%s"\n' "$CALLS" | stub_script kube-diagnose
    printf '#!/bin/sh\nshift 2\nexec "$@"\n' | stub_script kube-progress
}

@test "helm-install is installed on PATH and syntactically valid" {
    command -v helm-install
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "helm-install needs a namespace, a release and a chart" {
    run helm-install ns rel
    [ "$status" -ne 0 ]
}

@test "helm-install ensures the namespace, then upgrades --install with the helm arguments and the timeout" {
    stub_cluster "" 0
    run helm-install -t 3m coder coder repo/coder --version 2 --values v.yaml
    [ "$status" -eq 0 ]
    grep -q '^kubectl create namespace coder' "$CALLS"
    grep -qx 'helm upgrade --install coder repo/coder -n coder --version 2 --values v.yaml --timeout 3m' "$CALLS"
    ! grep -q '^diagnose' "$CALLS"
}

@test "helm-install waits for a terminating namespace to be gone before creating it" {
    stub_cluster "" 0
    printf '#!/bin/sh\necho "kubectl $*" >>"%s"\n[ "$1" = get ] && echo Terminating\nexit 0\n' "$CALLS" | stub_script kubectl
    run helm-install ns rel chart
    [ "$status" -eq 0 ]
    wait_line=$(grep -n '^kubectl wait --for=delete namespace/ns' "$CALLS" | head -1 | cut -d: -f1)
    create_line=$(grep -n '^kubectl create namespace ns' "$CALLS" | head -1 | cut -d: -f1)
    [ -n "$wait_line" ] && [ "$wait_line" -lt "$create_line" ]
}

@test "helm-install forgets the record of a failed release, keeping its resources" {
    stub_cluster failed 0
    run helm-install ns rel chart
    [ "$status" -eq 0 ]
    grep -q '^kubectl -n ns delete secret -l owner=helm,name=rel$' "$CALLS"
    ! grep -q 'helm uninstall' "$CALLS"
}

@test "helm-install diagnoses the namespace and keeps helm's exit status on failure" {
    stub_cluster "" 7
    run helm-install ns rel chart
    [ "$status" -eq 7 ]
    grep -q '^diagnose ns$' "$CALLS"
}
