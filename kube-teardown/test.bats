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

# stub_cluster <helm status exit code>: record every helm and kubectl call.
stub_cluster() {
    printf '#!/bin/sh\necho "helm $*" >>"%s"\n[ "$1" = status ] && exit %s\nexit 0\n' "$CALLS" "$1" | stub_script helm
    printf '#!/bin/sh\necho "kubectl $*" >>"%s"\n' "$CALLS" | stub_script kubectl
}

@test "kube-teardown is installed on PATH and syntactically valid" {
    command -v kube-teardown
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "kube-teardown errors without a namespace and a release" {
    run kube-teardown ns
    [ "$status" -ne 0 ]
}

@test "kube-teardown uninstalls an existing release and deletes the namespace" {
    stub_cluster 0
    run kube-teardown coder coder
    [ "$status" -eq 0 ]
    grep -q '^helm uninstall coder -n coder --wait$' "$CALLS"
    grep -q '^kubectl delete namespace coder --ignore-not-found --wait=false$' "$CALLS"
}

@test "kube-teardown only warns for a release that is not installed, still deleting the namespace" {
    stub_cluster 1
    run kube-teardown coder coder
    [ "$status" -eq 0 ]
    [[ "$output" == *"not found in namespace coder"* ]]
    ! grep -q 'helm uninstall' "$CALLS"
    grep -q 'kubectl delete namespace coder' "$CALLS"
}
