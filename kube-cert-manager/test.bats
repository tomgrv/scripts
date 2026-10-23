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

stub_cluster() {
    printf '#!/bin/sh\necho "helm $*" >>"%s"\n' "$CALLS" | stub_script helm
    printf '#!/bin/sh\ncase "$1" in get) exit %s ;; esac\ncat >/dev/null 2>&1 </dev/null\necho "kubectl $*" >>"%s"\n' "$1" "$CALLS" | stub_script kubectl
}

@test "kube-cert-manager is installed on PATH and syntactically valid" {
    command -v kube-cert-manager
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "kube-cert-manager does nothing when cert-manager is already installed" {
    stub_cluster 0
    run kube-cert-manager
    [ "$status" -eq 0 ]
    [[ "$output" == *"already installed"* ]]
    ! grep -q 'helm upgrade' "$CALLS"
}

@test "kube-cert-manager installs the chart with CRDs and the pinned version" {
    stub_cluster 1
    run kube-cert-manager -v v1.16.2
    [ "$status" -eq 0 ]
    grep -q '^helm upgrade --install cert-manager jetstack/cert-manager --namespace cert-manager --set crds.enabled=true --version v1.16.2 --wait --timeout 5m$' "$CALLS"
}
