#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
    WORK=$(mktemp -d)
    CALLS="$WORK/calls"
    : >"$CALLS"
    printf '#!/bin/sh\necho "yaml-render $*"\n' | stub_script yaml-render
    printf '#!/bin/sh\necho "kubectl $*" >>"%s"\ncat >>"%s"\n' "$CALLS" "$CALLS" | stub_script kubectl
}

teardown() {
    rm -rf "$WORK"
    teardown_scripts_path
}

@test "kube-apply is installed on PATH and syntactically valid" {
    command -v kube-apply
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "kube-apply needs a template" {
    run kube-apply
    [ "$status" -eq 1 ]
}

@test "kube-apply pipes the rendered template into kubectl apply" {
    run kube-apply m.yaml A=1 B=two
    [ "$status" -eq 0 ]
    grep -q '^kubectl apply -f -$' "$CALLS"
    grep -q '^yaml-render m.yaml A=1 B=two$' "$CALLS"
}

@test "kube-apply -n applies into the namespace" {
    run kube-apply -n ns m.yaml
    [ "$status" -eq 0 ]
    grep -q '^kubectl apply -n ns -f -$' "$CALLS"
}
